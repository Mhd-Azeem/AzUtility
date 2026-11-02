import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';

class ScanUpdate {
  const ScanUpdate(
    this.files,
    this.total,
    this.location,
    this.errors, {
    this.done = false,
  });
  final int files, total, errors;
  final String location;
  final bool done;
}

String safeChild(String root, String name) {
  if (name.trim().isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains(RegExp(r'[\\/:\x00]')) ||
      name.endsWith('.') ||
      name.endsWith(' ')) {
    throw ArgumentError('Enter a valid single file name.');
  }
  final result = p.normalize(p.join(root, name));
  if (!p.isWithin(root, result)) {
    throw ArgumentError('Destination is outside selected folder');
  }
  return result;
}

String archiveDestination(String root, String name) {
  final normalized = name.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      normalized.contains(':') ||
      normalized.split('/').contains('..') ||
      normalized.contains('\x00')) {
    throw const FormatException('Unsafe archive path');
  }
  final target = p.normalize(p.join(root, normalized));
  if (!p.isWithin(root, target)) {
    throw const FormatException('Archive path escapes destination');
  }
  return target;
}

class FileService {
  final List<IndexedFile> index = [];
  Future<void> refreshDirectory(String directory) async {
    await _noLink(directory);
    final updated = <IndexedFile>[];
    await for (final entry in Directory(directory).list(followLinks: false)) {
      if (entry is File) {
        final stat = await entry.stat();
        updated.add(
          IndexedFile(
            entry.path,
            stat.size,
            stat.modified,
            classify(entry.path),
          ),
        );
      }
      if (updated.length >= 10000) break;
    }
    index.removeWhere((f) => p.dirname(f.path) == directory);
    index.addAll(updated.take(100000 - index.length));
  }

  // Stream directory entries, do not follow links, and cap retained index size.
  Stream<ScanUpdate> scan(
    String root,
    Cancellation cancel, {
    List<String> exclusions = const ['.git', 'node_modules'],
    int maxFiles = 100000,
  }) async* {
    cancel.check();
    await _noLink(root);
    index.clear();
    int total = 0, errors = 0;
    int last = 0;
    final folders = <Directory>[Directory(root)];
    while (folders.isNotEmpty) {
      cancel.check();
      final directory = folders.removeLast();
      try {
        await for (final entity in directory.list(followLinks: false)) {
          cancel.check();
          if (exclusions.contains(p.basename(entity.path))) continue;
          if (entity is Directory) {
            if (folders.length < 10000) {
              folders.add(entity);
            } else {
              errors++;
            }
          }
          if (entity is File) {
            try {
              final stat = await entity.stat();
              index.add(
                IndexedFile(
                  entity.path,
                  stat.size,
                  stat.modified,
                  classify(entity.path),
                ),
              );
              total += stat.size;
            } on FileSystemException {
              errors++;
            }
            if (index.length >= maxFiles) {
              yield ScanUpdate(
                index.length,
                total,
                entity.path,
                errors + 1,
                done: true,
              );
              return;
            }
          }
          if (index.length - last >= 100) {
            last = index.length;
            yield ScanUpdate(index.length, total, entity.path, errors);
            await Future<void>.delayed(Duration.zero);
          }
        }
      } on FileSystemException {
        errors++;
      }
    }
    yield ScanUpdate(index.length, total, root, errors, done: true);
  }

  Future<List<List<IndexedFile>>> duplicates(
    Cancellation cancel,
    void Function(int, int) progress, {
    int minimumBytes = 1,
  }) async {
    final sizes = <int, List<IndexedFile>>{};
    for (final file in index) {
      if (file.size >= minimumBytes) (sizes[file.size] ??= []).add(file);
    }
    final candidates = sizes.values
        .where((g) => g.length > 1)
        .expand((g) => g)
        .toList();
    final hashes = <String, List<IndexedFile>>{};
    int done = 0;
    for (final file in candidates) {
      cancel.check();
      try {
        final before = await File(file.path).stat();
        // Incremental hashing with backpressure, outside the UI isolate.
        final hash = await _cancellableHash(file.path, cancel);
        final after = await File(file.path).stat();
        cancel.check();
        if (before.size == file.size &&
            after.size == before.size &&
            after.modified == before.modified) {
          (hashes['${file.size}:$hash'] ??= []).add(file);
        }
      } on FileSystemException {
        /* File changed or became inaccessible. */
      }
      progress(++done, candidates.length);
    }
    return hashes.values.where((g) => g.length > 1).toList();
  }

  static Future<String> _hash(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
  static Future<void> _hashEntry(List<Object> arguments) async {
    final destination = arguments[1] as SendPort;
    try {
      destination.send({'hash': await _hash(arguments[0] as String)});
    } catch (e) {
      destination.send({'error': e.toString()});
    }
  }

  static Future<String> _cancellableHash(
    String path,
    Cancellation cancel,
  ) async {
    final port = ReceivePort();
    final completer = Completer<String>();
    final isolate = await Isolate.spawn(_hashEntry, <Object>[
      path,
      port.sendPort,
    ]);
    final subscription = port.listen((dynamic message) {
      if (completer.isCompleted) return;
      final data = message as Map;
      if (data['error'] != null) {
        completer.completeError(
          FileSystemException(data['error'] as String, path),
        );
      } else {
        completer.complete(data['hash'] as String);
      }
    });
    cancel.onCancel(() {
      isolate.kill(priority: Isolate.immediate);
      if (!completer.isCompleted) completer.completeError(const Cancelled());
    });
    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
      port.close();
      isolate.kill();
    }
  }

  Future<void> _noLink(String path) async {
    var current = p.absolute(path);
    while (true) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('Symbolic links are not followed', current);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  Future<void> copy(
    String source,
    String destination,
    Cancellation cancel, {
    bool move = false,
  }) async {
    await _noLink(source);
    await _noLink(p.dirname(destination));
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException(
        'Destination exists; overwriting is disabled',
      );
    }
    if (p.equals(source, destination) || p.isWithin(source, destination)) {
      throw ArgumentError('Cannot copy into the source');
    }
    cancel.check();
    if (await FileSystemEntity.isDirectory(source)) {
      await _copyDirectory(source, destination, cancel, move: move);
      return;
    }
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('Select a regular file or directory');
    }
    final original = await File(source).stat();
    final temporary =
        '$destination.az-part-${DateTime.now().microsecondsSinceEpoch}';
    final output = File(temporary).openWrite();
    try {
      await for (final chunk in File(source).openRead()) {
        cancel.check();
        output.add(chunk);
        await output.flush();
      }
      await output.close();
      cancel.check();
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Destination appeared during copy');
      }
      await File(temporary).rename(destination);
      final after = await File(source).stat();
      if (after.size != original.size || after.modified != original.modified) {
        throw const FileSystemException(
          'Source changed during copy; source retained',
        );
      }
      if (move) await File(source).delete();
    } catch (_) {
      await output.close();
      if (await File(temporary).exists()) await File(temporary).delete();
      rethrow;
    }
  }

  Future<void> _copyDirectory(
    String source,
    String destination,
    Cancellation cancel, {
    required bool move,
  }) async {
    final staging =
        '$destination.az-part-${DateTime.now().microsecondsSinceEpoch}';
    // Snapshot metadata before copying. Never remove a changed source tree.
    final original = <String, FileStat>{};
    final dirs = <String>{source};
    await for (final entry in Directory(
      source,
    ).list(recursive: true, followLinks: false)) {
      cancel.check();
      await _noLink(entry.path);
      if (entry is Directory) {
        dirs.add(entry.path);
      } else if (entry is File) {
        original[entry.path] = await entry.stat();
      } else {
        throw const FileSystemException('Unsupported entry in directory');
      }
      if (original.length + dirs.length > 100000) {
        throw const FileSystemException('Copy exceeds 100,000 entries');
      }
    }
    try {
      await Directory(staging).create();
      for (final dir in dirs.skip(1)) {
        cancel.check();
        await Directory(
          p.join(staging, p.relative(dir, from: source)),
        ).create(recursive: true);
      }
      for (final file in original.keys) {
        await copy(
          file,
          p.join(staging, p.relative(file, from: source)),
          cancel,
        );
      }
      cancel.check();
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Destination appeared during copy');
      }
      await Directory(staging).rename(destination);
      if (move) {
        final current = <String>{};
        await for (final entry in Directory(
          source,
        ).list(recursive: true, followLinks: false)) {
          cancel.check();
          await _noLink(entry.path);
          current.add(entry.path);
          if (entry is File) {
            final before = original[entry.path], after = await entry.stat();
            if (before == null ||
                before.size != after.size ||
                before.modified != after.modified) {
              throw const FileSystemException(
                'Source changed; copied destination and source both retained',
              );
            }
          }
        }
        if (current.length != original.length + dirs.length - 1) {
          throw const FileSystemException(
            'Source tree changed; source retained',
          );
        }
        // Delete only the known, unchanged files, then empty directories. A new file prevents directory removal.
        for (final file in original.keys) {
          cancel.check();
          await File(file).delete();
        }
        final deepest = dirs.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        for (final dir in deepest) {
          cancel.check();
          await Directory(dir).delete();
        }
      }
    } finally {
      if (await Directory(staging).exists()) {
        await Directory(staging).delete(recursive: true);
      }
    }
  }

  Future<void> rename(String source, String name) async {
    await _noLink(source);
    final destination = safeChild(p.dirname(source), name);
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Destination already exists');
    }
    if (await FileSystemEntity.isDirectory(source)) {
      await Directory(source).rename(destination);
    } else {
      await File(source).rename(destination);
    }
  }

  Future<void> deleteFile(String path) async {
    await _noLink(path);
    if (await FileSystemEntity.isDirectory(path)) {
      // Explicit recursive folder deletion is exposed only after UI confirmation.
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  Future<List<String>> inspectZip(String path) => Isolate.run(() {
    final input = InputFileStream(path);
    try {
      return ZipDecoder()
          .decodeStream(input)
          .files
          .map((f) => '${f.name} (${bytes(f.size)})')
          .toList();
    } finally {
      input.closeSync();
    }
  });
  Future<void> createZip(
    List<String> files,
    String destination,
    Cancellation cancel, {
    void Function(double)? onProgress,
    String? password,
  }) async {
    if (await File(destination).exists()) {
      throw const FileSystemException('Destination already exists');
    }
    final names = <String>{};
    for (final file in files) {
      await _noLink(file);
      if (await Directory(file).exists() && p.isWithin(file, destination)) {
        throw ArgumentError('ZIP destination must be outside selected folders');
      }
      if (!names.add(p.basename(file))) {
        throw ArgumentError('Selected files have conflicting names');
      }
    }
    final temporary =
        '$destination.az-part-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _archiveJob(
        {
          'action': 'create',
          'files': files,
          'destination': temporary,
          'password': ?password,
        },
        cancel,
        onProgress,
      );
      cancel.check();
      if (await File(destination).exists()) {
        throw const FileSystemException('Destination already exists');
      }
      await File(temporary).rename(destination);
    } finally {
      if (await File(temporary).exists()) await File(temporary).delete();
    }
  }

  Future<void> extractZip(
    String path,
    String destination,
    Cancellation cancel, {
    String? password,
    void Function(double)? onProgress,
  }) async {
    await _noLink(destination);
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException(
        'Choose a new extraction folder; overwriting is disabled',
      );
    }
    final staging =
        '$destination.az-part-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _archiveJob(
        {
          'action': 'extract',
          'path': path,
          'destination': staging,
          'password': ?password,
        },
        cancel,
        onProgress,
      );
      cancel.check();
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'Destination appeared during extraction',
        );
      }
      await Directory(staging).rename(destination);
    } finally {
      if (await Directory(staging).exists()) {
        await Directory(staging).delete(recursive: true);
      }
    }
  }

  static Future<void> _archiveEntry(List<Object> arguments) async {
    final job = arguments[0] as Map<String, Object>;
    final port = arguments[1] as SendPort;
    try {
      if (job['action'] == 'create') {
        final paths = job['files'] as List<String>;
        final entries = <MapEntry<String, String>>[];
        int bytes = 0;
        Future<void> collect(String source, String name) async {
          await FileService()._noLink(source);
          final stat = await FileStat.stat(source);
          if (stat.type == FileSystemEntityType.directory) {
            entries.add(MapEntry(source, '$name/'));
            await for (final entry in Directory(
              source,
            ).list(recursive: true, followLinks: false)) {
              await FileService()._noLink(entry.path);
              final relative = p.posix.fromUri(
                p.toUri(p.relative(entry.path, from: source)),
              );
              final child = await entry.stat();
              entries.add(
                MapEntry(
                  entry.path,
                  '$name/$relative${entry is Directory ? '/' : ''}',
                ),
              );
              if (entry is File) bytes += child.size;
              if (entries.length > 10000 || bytes > 512 * 1024 * 1024) {
                throw const FileSystemException(
                  'ZIP creation exceeds 10,000 entries or 512 MiB',
                );
              }
            }
          } else if (stat.type == FileSystemEntityType.file) {
            entries.add(MapEntry(source, name));
            bytes += stat.size;
          } else {
            throw const FileSystemException('Unsupported archive source');
          }
          if (entries.length > 10000 || bytes > 512 * 1024 * 1024) {
            throw const FileSystemException(
              'ZIP creation exceeds 10,000 entries or 512 MiB',
            );
          }
        }

        for (final source in paths) {
          await collect(source, p.basename(source));
        }
        final encoder = ZipFileEncoder(password: job['password'] as String?);
        encoder.create(job['destination'] as String);
        try {
          int done = 0;
          for (final entry in entries) {
            if (entry.value.endsWith('/')) {
              encoder.addArchiveFile(ArchiveFile.directory(entry.value));
            } else {
              await encoder.addFile(File(entry.key), entry.value);
            }
            port.send({'progress': ++done / entries.length});
          }
        } finally {
          await encoder.close();
        }
      } else {
        await _extractWorker(
          job['path'] as String,
          job['destination'] as String,
          password: job['password'] as String?,
          progress: (value) => port.send({'progress': value}),
        );
      }
      port.send({'done': true});
    } catch (e) {
      port.send({'error': e.toString(), 'format': e is FormatException});
    }
  }

  static Future<void> _archiveJob(
    Map<String, Object> job,
    Cancellation cancel, [
    void Function(double)? onProgress,
  ]) async {
    cancel.check();
    final port = ReceivePort();
    final completer = Completer<void>();
    final isolate = await Isolate.spawn(_archiveEntry, <Object>[
      job,
      port.sendPort,
    ]);
    final subscription = port.listen((dynamic message) {
      if (completer.isCompleted) return;
      final data = message as Map;
      if (data['progress'] is num) {
        onProgress?.call((data['progress'] as num).toDouble());
        return;
      }
      if (data['error'] != null) {
        completer.completeError(
          data['format'] == true
              ? FormatException(data['error'] as String)
              : FileSystemException(data['error'] as String),
        );
      } else {
        completer.complete();
      }
    });
    cancel.onCancel(() {
      isolate.kill(priority: Isolate.immediate);
      if (!completer.isCompleted) completer.completeError(const Cancelled());
    });
    try {
      await completer.future;
    } finally {
      await subscription.cancel();
      port.close();
      isolate.kill();
    }
  }

  static Future<void> _extractWorker(
    String path,
    String destination, {
    String? password,
    void Function(double)? progress,
  }) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        password: password,
        verify: true,
      );
      int expanded = 0;
      if (archive.files.length > 10000) {
        throw const FormatException('Archive exceeds 10,000 entry limit');
      }
      final names = <String>{};
      for (final file in archive) {
        if (!names.add(
          Platform.isWindows ? file.name.toLowerCase() : file.name,
        )) {
          throw const FormatException('Conflicting ZIP paths');
        }
        archiveDestination(destination, file.name);
        if (file.isSymbolicLink) {
          throw const FormatException('Archive symlinks are rejected');
        }
        expanded += file.size;
        if (expanded > 512 * 1024 * 1024) {
          throw const FormatException(
            'Archive exceeds 512 MiB expansion limit',
          );
        }
      }
      await Directory(destination).create();
      // Windows TEMP may contain a DOS 8.3 alias (e.g. RUNNER~1). Use the
      // resolved root consistently for the archive library's containment checks.
      final canonical = await Directory(destination).resolveSymbolicLinks();
      int actual = 0, done = 0;
      for (final entry in archive) {
        await extractArchiveToDisk(
          Archive()..addFile(entry),
          canonical,
          maxSize: 512 * 1024 * 1024 - actual,
          throwOnError: true,
        );
        if (entry.isFile) {
          final file = File(archiveDestination(canonical, entry.name));
          if (!await file.exists()) {
            throw FileSystemException(
              'Archive entry was not extracted',
              entry.name,
            );
          }
          actual += await file.length();
          if (actual > 512 * 1024 * 1024) {
            throw const FormatException('Archive expansion limit exceeded');
          }
        }
        progress?.call(++done / archive.length);
      }
    } finally {
      await input.close();
    }
  }
}
