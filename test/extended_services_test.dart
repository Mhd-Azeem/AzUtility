import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:az_utility/core/database/app_database.dart';
import 'package:az_utility/core/models.dart';
import 'package:az_utility/core/reporting/comparison.dart';
import 'package:az_utility/core/reporting/report_service.dart';
import 'package:az_utility/features/smart_file_manager/file_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'comparisons retain missing observations and summarize measured latency',
    () {
      final result = numericObservations({
        'samples': [
          {'tcpMs': 10},
          {'tcpMs': null},
          {'tcpMs': 30},
        ],
        'seconds': 2,
      });
      expect(result['mean TCP (ms)'], 20);
      expect(result['successive jitter (ms)'], 20);
      expect(result['DNS/TCP failure (%)'], closeTo(100 / 3, 0.001));
      expect(result.containsKey('missing'), false);
      expect(observationText(null), 'Not measured');
    },
  );
  test(
    'retention prunes age, reset preserves diagnostic history, monitoring clears independently',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.set('light', true);
      await db.save('device', 'recent', {});
      await db.customStatement(
        'INSERT INTO records(category,title,created,payload) VALUES (?,?,?,?)',
        [
          'network',
          'old',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 100))
              .toIso8601String(),
          '{}',
        ],
      );
      await db.saveMonitoring([const Metric('RAM', '50%', ratio: .5)]);
      expect((await db.monitoring()).single['ratio'], .5);
      await db.prune(30);
      expect((await db.history()).map((r) => r['title']), ['recent']);
      await db.resetSettings();
      expect(await db.settings(), isEmpty);
      expect(await db.history(), hasLength(1));
      await db.clear('network');
      expect(await db.monitoring(), hasLength(1));
      await db.clear('device');
      expect(await db.monitoring(), isEmpty);
      expect(() => db.prune(0), throwsArgumentError);
    },
  );
  test(
    'recursive copy preserves structure, rejects containment and conflicts, move removes only copied tree',
    () async {
      final temp = await Directory.systemTemp.createTemp('az-tree-');
      addTearDown(() => temp.delete(recursive: true));
      final source = Directory(p.join(temp.path, 'source'));
      await Directory(p.join(source.path, 'nested')).create(recursive: true);
      await File(
        p.join(source.path, 'nested', 'a.txt'),
      ).writeAsString('real bytes');
      final service = FileService();
      final target = p.join(temp.path, 'copy');
      await service.copy(source.path, target, Cancellation());
      expect(
        await File(p.join(target, 'nested', 'a.txt')).readAsString(),
        'real bytes',
      );
      expect(await source.exists(), true);
      await expectLater(
        service.copy(source.path, target, Cancellation()),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        service.copy(
          source.path,
          p.join(source.path, 'inside'),
          Cancellation(),
        ),
        throwsArgumentError,
      );
      final moved = p.join(temp.path, 'moved');
      await service.copy(source.path, moved, Cancellation(), move: true);
      expect(await source.exists(), false);
      expect(
        await File(p.join(moved, 'nested', 'a.txt')).readAsString(),
        'real bytes',
      );
    },
  );
  test(
    'cancelled recursive copy creates no destination or staging directory',
    () async {
      final temp = await Directory.systemTemp.createTemp('az-cancel-tree-');
      addTearDown(() => temp.delete(recursive: true));
      final source = Directory(p.join(temp.path, 'source'));
      await source.create();
      await File(p.join(source.path, 'file')).writeAsString('x');
      final cancel = Cancellation()..cancel();
      await expectLater(
        FileService().copy(source.path, p.join(temp.path, 'target'), cancel),
        throwsA(isA<Cancelled>()),
      );
      expect(await temp.list().length, 1);
    },
  );
  test(
    'encrypted ZIP rejects incorrect passwords and cleans staging, then reports extraction progress',
    () async {
      final temp = await Directory.systemTemp.createTemp('az-password-');
      addTearDown(() => temp.delete(recursive: true));
      final data = [1, 2, 3, 4];
      final archive = Archive()
        ..addFile(ArchiveFile('nested/data.bin', data.length, data));
      final zip = File(p.join(temp.path, 'encrypted.zip'));
      await zip.writeAsBytes(
        ZipEncoder(password: 'local-test').encodeBytes(archive),
      );
      final service = FileService();
      final target = p.join(temp.path, 'extracted');
      await expectLater(
        service.extractZip(zip.path, target, Cancellation(), password: 'wrong'),
        throwsA(isA<FormatException>()),
      );
      expect(await Directory(target).exists(), false);
      expect(
        (await temp.list().toList()).where((f) => f.path.contains('.az-part-')),
        isEmpty,
      );
      final progress = <double>[];
      await service.extractZip(
        zip.path,
        target,
        Cancellation(),
        password: 'local-test',
        onProgress: progress.add,
      );
      expect(
        await File(p.join(target, 'nested', 'data.bin')).readAsBytes(),
        data,
      );
      expect(progress.last, 1);
    },
  );
  test(
    'incremental directory updates retain untouched index entries',
    () async {
      final temp = await Directory.systemTemp.createTemp('az-index-update-');
      addTearDown(() => temp.delete(recursive: true));
      final sub = Directory(p.join(temp.path, 'sub'));
      await sub.create();
      final rootFile = File(p.join(temp.path, 'root.txt'));
      await rootFile.writeAsString('first');
      final subFile = File(p.join(sub.path, 'nested.txt'));
      await subFile.writeAsString('preserved');
      final service = FileService();
      await service.scan(temp.path, Cancellation()).drain<void>();
      await rootFile.writeAsString('updated content');
      await service.refreshDirectory(temp.path);
      expect(
        service.index.singleWhere((f) => f.path == rootFile.path).size,
        15,
      );
      expect(service.index.singleWhere((f) => f.path == subFile.path).size, 9);
      await rootFile.delete();
      await service.refreshDirectory(temp.path);
      expect(service.index, hasLength(1));
    },
  );
  test(
    'multilingual PDF and network chart generate with bundled fonts',
    () async {
      final temp = await Directory.systemTemp.createTemp('az-pdf-unicode-');
      addTearDown(() => temp.delete(recursive: true));
      expect(await ReportService.fonts(), hasLength(6));
      final path = await ReportService().export(temp.path, 'pdf', [
        {
          'category': 'network',
          'title': 'Résumé 日本語 中文 தமிழ் සිංහල العربية',
          'created': '2026-11-02',
          'payload': {
            'samples': [
              {'tcpMs': 12},
              {'tcpMs': 30},
            ],
          },
        },
      ]);
      expect(await File(path).length(), greaterThan(10000));
    },
  );
}
