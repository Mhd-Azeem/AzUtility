import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:fl_chart/fl_chart.dart';
import '../../app/controller.dart';
import '../../core/models.dart';
import '../../core/widgets/dashboard_widgets.dart';
import 'file_service.dart';
import 'saf_page.dart';
import 'storage_treemap.dart';
import 'large_files_page.dart';

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});
  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  String? current;
  List<FileSystemEntity> entries = [];
  final entryStats = <String, FileStat>{};
  String search = '', category = 'All';
  bool grid = false, descending = false;
  String sort = 'Name';
  final selected = <String>{};
  List<String> clipboard = [];
  bool cut = false;
  String? listingError;
  StreamSubscription<FileSystemEvent>? watcher;
  Timer? watchDebounce;
  @override
  void dispose() {
    watcher?.cancel();
    watchDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final app = ref.read(controllerProvider);
    app.ready.then((_) async {
      if (!mounted) return;
      grid = app.settings['fileGrid'] == true;
      sort = app.settings['fileSort'] as String? ?? 'Name';
      current = app.root;
      if (current != null) {
        await watchFolder();
        await load();
      }
    });
  }

  Future<void> choose() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose an accessible folder',
    );
    if (path == null || !mounted) return;
    ref.read(controllerProvider).root = path;
    current = path;
    await watchFolder();
    await load();
  }

  Future<void> watchFolder() async {
    await watcher?.cancel();
    try {
      watcher = Directory(current!).watch().listen(
        (_) {
          watchDebounce?.cancel();
          watchDebounce = Timer(const Duration(milliseconds: 600), () {
            if (mounted) {
              load();
              final app = ref.read(controllerProvider);
              if (!app.busy &&
                  app.root != null &&
                  (current == app.root || p.isWithin(app.root!, current!)) &&
                  app.files.index.isNotEmpty) {
                unawaited(
                  app.files
                      .refreshDirectory(current!)
                      .then((_) => app.db.saveIndex(app.files.index))
                      .then((_) => app.notifyListeners())
                      .catchError((Object e) {
                        if (mounted) {
                          setState(
                            () => listingError = 'Index update failed: $e',
                          );
                        }
                      }),
                );
              }
            }
          });
        },
        onError: (Object e) {
          if (mounted) {
            setState(() => listingError = 'Live updates unavailable: $e');
          }
        },
      );
    } catch (_) {
      /* Manual refresh remains available on unsupported providers. */
    }
  }

  Future<void> load() async {
    try {
      final list = await Directory(
        current!,
      ).list(followLinks: false).take(10000).toList();
      final stats = <String, FileStat>{};
      for (final entry in list) {
        stats[entry.path] = await entry.stat();
      }
      if (mounted) {
        setState(() {
          entries = list;
          entryStats
            ..clear()
            ..addAll(stats);
          selected.clear();
          listingError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => listingError = e.toString());
    }
  }

  Future<String?> prompt(
    String title, {
    String initial = '',
    bool secret = false,
  }) async {
    final input = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          obscureText: secret,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    // Dialog closing animations may still reference the controller.
    return value;
  }

  Future<void> operation(
    String title,
    Future<void> Function(Cancellation) action,
  ) async {
    final app = ref.read(controllerProvider);
    await app.run(title, (token) async {
      await action(token);
      await app.db.save('files', title, {'items': selected.length});
    });
    if (current != null) await load();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    final filtered =
        entries
            .where(
              (e) =>
                  p
                      .basename(e.path)
                      .toLowerCase()
                      .contains(search.toLowerCase()) &&
                  (category == 'All' || classify(e.path) == category),
            )
            .toList()
          ..sort((a, b) {
            final order = sort == 'Size'
                ? (entryStats[a.path]?.size ?? 0).compareTo(
                    entryStats[b.path]?.size ?? 0,
                  )
                : sort == 'Modified'
                ? (entryStats[a.path]?.modified ?? DateTime(1970)).compareTo(
                    entryStats[b.path]?.modified ?? DateTime(1970),
                  )
                : p
                      .basename(a.path)
                      .toLowerCase()
                      .compareTo(p.basename(b.path).toLowerCase());
            return descending ? -order : order;
          });
    final categories = <String, int>{};
    for (final file in app.files.index) {
      categories.update(
        file.category,
        (n) => n + file.size,
        ifAbsent: () => file.size,
      );
    }
    final total = categories.values.fold<int>(0, (a, b) => a + b);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () => load(),
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () {
          if (current != null && current != app.root) {
            navigate(p.dirname(current!));
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          if (!app.busy) {
            setState(
              () => selected.addAll(
                filtered.where((e) => e is! Link).map((e) => e.path),
              ),
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          clipboard = selected.toList();
          cut = false;
        },
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          clipboard = selected.toList();
          cut = true;
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            paste(),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (!app.busy && selected.isNotEmpty) remove();
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (!app.busy && selected.length == 1) {
            final entry = entries
                .where((e) => e.path == selected.single)
                .firstOrNull;
            if (entry != null) fileAction('Rename', entry);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: PageBody(
          title: 'Smart File Manager',
          subtitle:
              'Selected accessible folders only · Symlinks are never followed',
          children: [
            if (app.droppedPaths.isNotEmpty)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${app.droppedPaths.length} dropped items ready to review',
                    ),
                    for (final path in app.droppedPaths.take(10)) Text(path),
                    ActionWrap(
                      children: [
                        OutlinedButton(
                          onPressed: app.busy || current == null
                              ? null
                              : () async {
                                  final paths = app.droppedPaths.toList();
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Copy dropped items?'),
                                      content: Text(
                                        '${paths.length} items → $current\nExisting names will be rejected.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('Copy'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (yes == true) {
                                    await operation('Copy dropped items', (
                                      token,
                                    ) async {
                                      for (final path in paths) {
                                        await app.files.copy(
                                          path,
                                          safeChild(current!, p.basename(path)),
                                          token,
                                        );
                                      }
                                    });
                                    app.droppedPaths.clear();
                                    app.notifyListeners();
                                  }
                                },
                          child: const Text('Copy into current folder'),
                        ),
                        if (app.droppedPaths.length == 1)
                          TextButton(
                            onPressed: () async {
                              final path = app.droppedPaths.single;
                              if (await Directory(path).exists()) {
                                app.root = path;
                                await navigate(path);
                                app.droppedPaths.clear();
                                app.notifyListeners();
                              }
                            },
                            child: const Text('Open dropped folder'),
                          ),
                        TextButton(
                          onPressed: () {
                            app.droppedPaths.clear();
                            app.notifyListeners();
                          },
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (Platform.isAndroid)
              ActionWrap(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SafPage(uri: '', media: true),
                      ),
                    ),
                    child: const Text('Media library'),
                  ),
                  if (app.settings['lastSafTree'] is String)
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SafPage(
                            uri: app.settings['lastSafTree'] as String,
                          ),
                        ),
                      ),
                      child: const Text('Reopen granted folder'),
                    ),
                ],
              ),
            if (total > 0)
              Panel(
                child: StorageTreemap(
                  categories: categories,
                  onSelect: (category) => showLarge(
                    app.files.index
                        .where((file) => file.category == category)
                        .toList(),
                  ),
                ),
              ),
            ActionWrap(
              children: [
                FilledButton.icon(
                  onPressed: app.busy ? null : choose,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose folder'),
                ),
                OutlinedButton(
                  onPressed: app.busy || app.root == null ? null : app.scan,
                  child: const Text('Scan folder'),
                ),
                OutlinedButton(
                  onPressed: app.busy || app.files.index.isEmpty
                      ? null
                      : app.findDuplicates,
                  child: const Text('Find duplicates'),
                ),
                OutlinedButton(
                  onPressed: app.files.index.isEmpty
                      ? null
                      : () => showLarge(app.files.index),
                  child: const Text('Largest files'),
                ),
              ],
            ),
            if (Platform.isAndroid)
              const Panel(
                child: Text(
                  'Android scoped storage applies. This browser only uses readable selected paths. For document-provider folders, use the SAF browser below; no access to other apps’ private data is requested.',
                ),
              ),
            if (Platform.isAndroid)
              OutlinedButton(
                onPressed: () => openSaf(),
                child: const Text(
                  'Open Android document-provider folder (SAF)',
                ),
              ),
            if (total > 0)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Indexed coverage: ${app.files.index.length} files · ${bytes(total)}',
                    ),
                    const Text(
                      'This is the selected scan subset, not whole-volume capacity.',
                    ),
                    SizedBox(
                      height: 160,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            for (int i = 0; i < categories.length; i++)
                              PieChartSectionData(
                                value: categories.values
                                    .elementAt(i)
                                    .toDouble(),
                                title: categories.keys.elementAt(i),
                                radius: 40,
                                color: Colors
                                    .primaries[i % Colors.primaries.length],
                              ),
                          ],
                          centerSpaceRadius: 40,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              final i =
                                  response?.touchedSection?.touchedSectionIndex;
                              if (event.isInterestedForInteractions &&
                                  i != null &&
                                  i >= 0 &&
                                  i < categories.length) {
                                setState(
                                  () => category = categories.keys.elementAt(i),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    for (final entry in categories.entries)
                      ListTile(
                        title: Text(entry.key),
                        trailing: Text(bytes(entry.value)),
                        subtitle: LinearProgressIndicator(
                          value: total > 0 ? entry.value / total : 0,
                        ),
                        onTap: () => showLarge(
                          app.files.index
                              .where((f) => f.category == entry.key)
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            if (current == null)
              const Panel(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Choose a folder to browse real files. Scans are read-only. File changes always require an explicit action.',
                  ),
                ),
              )
            else
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Parent folder',
                          onPressed: current == app.root
                              ? null
                              : () => navigate(p.dirname(current!)),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        Expanded(child: SelectableText(current!)),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: load,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: 'Grid or list',
                          onPressed: () {
                            setState(() => grid = !grid);
                            app.set('fileGrid', grid);
                          },
                          icon: Icon(grid ? Icons.view_list : Icons.grid_view),
                        ),
                      ],
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final path in breadcrumbs(current!))
                            TextButton(
                              onPressed: () => navigate(path),
                              child: Text(
                                p.basename(path).isEmpty
                                    ? path
                                    : p.basename(path),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search this folder',
                      ),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    ActionWrap(
                      children: [
                        DropdownButton<String>(
                          value: category,
                          items: [
                            for (final c in [
                              'All',
                              'Images',
                              'Videos',
                              'Audio',
                              'Documents',
                              'Archives',
                              'Other',
                            ])
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) => setState(() => category = v!),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => descending = !descending),
                          child: Text(descending ? 'Descending' : 'Ascending'),
                        ),
                        DropdownButton<String>(
                          value: sort,
                          items: [
                            for (final mode in ['Name', 'Size', 'Modified'])
                              DropdownMenuItem(value: mode, child: Text(mode)),
                          ],
                          onChanged: (value) {
                            setState(() => sort = value!);
                            app.set('fileSort', value);
                          },
                        ),
                        TextButton(
                          onPressed: app.busy ? null : () => newFolder(),
                          child: const Text('New folder'),
                        ),
                        if (selected.isNotEmpty) ...[
                          Text('${selected.length} selected'),
                          TextButton(
                            onPressed: app.busy ? null : () => transfer(false),
                            child: const Text('Copy'),
                          ),
                          TextButton(
                            onPressed: app.busy ? null : () => transfer(true),
                            child: const Text('Move'),
                          ),
                          TextButton(
                            onPressed: app.busy ? null : zip,
                            child: const Text('Create ZIP'),
                          ),
                          TextButton(
                            onPressed: app.busy ? null : remove,
                            child: const Text('Delete'),
                          ),
                        ],
                      ],
                    ),
                    if (listingError != null)
                      Text(
                        listingError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No accessible matching entries.'),
                      ),
                    SizedBox(
                      height: 480,
                      child: grid
                          ? GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 200,
                                    mainAxisExtent: 150,
                                  ),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) =>
                                  fileTile(filtered[i], true),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, i) =>
                                  fileTile(filtered[i], false),
                            ),
                    ),
                  ],
                ),
              ),
            if (app.files.index.isNotEmpty)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Folder size ranking · indexed subset'),
                    ...folderRanking(app.files.index)
                        .take(20)
                        .map(
                          (entry) => ListTile(
                            title: Text(entry.key),
                            trailing: Text(bytes(entry.value)),
                            onTap: () => showLarge(
                              app.files.index
                                  .where((f) => p.dirname(f.path) == entry.key)
                                  .toList(),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            if (app.duplicateGroups.isNotEmpty)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Verified SHA-256 duplicate groups — review copies before deleting',
                    ),
                    for (final group in app.duplicateGroups.take(100))
                      ExpansionTile(
                        title: Text(
                          '${group.length} copies · ${bytes(group.first.size * (group.length - 1))} potentially reclaimable',
                        ),
                        children: [
                          for (final file in group)
                            ListTile(
                              leading: Checkbox(
                                value: selected.contains(file.path),
                                onChanged: (v) => setState(
                                  () => v == true
                                      ? selected.add(file.path)
                                      : selected.remove(file.path),
                                ),
                              ),
                              title: Text(p.basename(file.path)),
                              subtitle: Text(file.path),
                              onTap: () => OpenFilex.open(file.path),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget fileTile(FileSystemEntity entity, bool compact) {
    final name = p.basename(entity.path);
    final folder = entity is Directory;
    final link = entity is Link;
    final stat = entryStats[entity.path];
    final thumbnail =
        !folder &&
            !link &&
            classify(name) == 'Images' &&
            ref.read(controllerProvider).settings['thumbnails'] != false &&
            [
              'jpg',
              'jpeg',
              'png',
              'webp',
              'gif',
            ].contains(p.extension(name).substring(1).toLowerCase())
        ? Image.file(
            File(entity.path),
            width: 32,
            height: 32,
            cacheWidth: 96,
            errorBuilder: (_, _, _) => const Icon(Icons.image),
          )
        : Icon(
            folder
                ? Icons.folder
                : link
                ? Icons.link
                : Icons.insert_drive_file,
            color: cyan,
          );
    if (compact) {
      return Card(
        child: Column(
          children: [
            Expanded(
              child: InkWell(
                onTap: link
                    ? null
                    : () => folder
                          ? navigate(entity.path)
                          : OpenFilex.open(entity.path),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      thumbnail,
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Checkbox(
                  value: selected.contains(entity.path),
                  onChanged: link
                      ? null
                      : (v) => setState(
                          () => v == true
                              ? selected.add(entity.path)
                              : selected.remove(entity.path),
                        ),
                ),
                Expanded(
                  child: Text(
                    folder ? 'Folder' : bytes(stat?.size ?? 0),
                    maxLines: 1,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) => fileAction(action, entity),
                  itemBuilder: (_) => [
                    for (final action in [
                      'Details',
                      'Rename',
                      if (!folder && !link) 'Share',
                    ])
                      PopupMenuItem(value: action, child: Text(action)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }
    return ListTile(
      selected: selected.contains(entity.path),
      leading: SizedBox(
        width: 76,
        child: Row(
          children: [
            Checkbox(
              value: selected.contains(entity.path),
              onChanged: link
                  ? null
                  : (v) => setState(
                      () => v == true
                          ? selected.add(entity.path)
                          : selected.remove(entity.path),
                    ),
            ),
            Expanded(child: thumbnail),
          ],
        ),
      ),
      title: Text(
        name,
        maxLines: compact ? 3 : 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        folder
            ? 'Folder'
            : link
            ? 'Symlink · not followed'
            : '${classify(name)} · ${bytes(stat?.size ?? 0)}\n${stat?.modified.toString().substring(0, 16) ?? 'Modified date unavailable'}',
      ),
      isThreeLine: !folder && !link,
      onTap: link
          ? null
          : () => folder ? navigate(entity.path) : OpenFilex.open(entity.path),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => fileAction(action, entity),
        itemBuilder: (_) => [
          for (final action in [
            'Details',
            'Rename',
            if (!folder && !link) 'Share',
            if (!folder && !link && p.extension(name).toLowerCase() == '.zip')
              'Inspect ZIP',
            if (!folder && !link && p.extension(name).toLowerCase() == '.zip')
              'Extract ZIP',
          ])
            PopupMenuItem(value: action, child: Text(action)),
        ],
      ),
    );
  }

  Future<void> navigate(String path) async {
    current = path;
    await watchFolder();
    await load();
  }

  Future<void> newFolder() async {
    final name = await prompt('New folder name');
    if (name != null) {
      await operation(
        'Create folder',
        (_) => Directory(safeChild(current!, name)).create(),
      );
    }
  }

  Future<void> paste() async {
    final app = ref.read(controllerProvider);
    if (app.busy || current == null || clipboard.isEmpty) return;
    final targets = clipboard.toList();
    final destination = current!;
    final moving = cut;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${moving ? 'Move' : 'Copy'} ${targets.length} items?'),
        content: Text(
          'Destination: $destination\nExisting names will be rejected. Original items are removed only after copying succeeds when moving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await operation(moving ? 'Move clipboard items' : 'Copy clipboard items', (
      token,
    ) async {
      for (final path in targets) {
        await app.files.copy(
          path,
          safeChild(destination, p.basename(path)),
          token,
          move: moving,
        );
      }
    });
    if (moving && app.error == null) clipboard.clear();
  }

  Future<void> transfer(bool move) async {
    final destination = await FilePicker.getDirectoryPath();
    if (destination == null) return;
    final sources = selected.toList();
    await operation(move ? 'Move files' : 'Copy files', (token) async {
      for (final source in sources) {
        await ref
            .read(controllerProvider)
            .files
            .copy(
              source,
              safeChild(destination, p.basename(source)),
              token,
              move: move,
            );
      }
    });
  }

  Future<void> remove() async {
    final targets = selected.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Platform.isWindows
              ? 'Recycle ${targets.length} items?'
              : 'Permanently delete ${targets.length} items?',
        ),
        content: Text(
          Platform.isWindows
              ? 'Windows will attempt to send these items to the Recycle Bin. Some volumes cannot recycle; Windows may ask for permanent deletion. Folder contents are included.'
              : 'Recovery is not guaranteed. Selected folders and their contents will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(Platform.isWindows ? 'Recycle' : 'Permanently delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await operation('Delete files', (token) async {
        for (final path in targets) {
          token.check();
          if (Platform.isWindows) {
            await ref.read(controllerProvider).native.invoke('recycle', {
              'path': path,
            });
          } else {
            await ref.read(controllerProvider).files.deleteFile(path);
          }
        }
      });
    }
  }

  Future<void> zip() async {
    final name = await prompt('ZIP filename', initial: 'Archive.zip');
    if (name == null) return;
    final password = await prompt(
      'ZIP password (leave empty for unencrypted)',
      secret: true,
    );
    if (password == null) return;
    final paths = selected.toList();
    await operation(
      'Create ZIP',
      (token) => ref
          .read(controllerProvider)
          .files
          .createZip(
            paths,
            safeChild(current!, name),
            token,
            password: password.isEmpty ? null : password,
            onProgress: (v) {
              final app = ref.read(controllerProvider);
              app.progress = v;
              app.notifyListeners();
            },
          ),
    );
  }

  Future<void> fileAction(String action, FileSystemEntity entity) async {
    final service = ref.read(controllerProvider).files;
    if (action == 'Share') {
      await operation('Share file', (_) async {
        await ref.read(controllerProvider).native.invoke('shareFile', {
          'path': entity.path,
        });
      });
    }
    if (action == 'Rename') {
      final name = await prompt('Rename', initial: p.basename(entity.path));
      if (name != null) {
        await operation('Rename', (_) => service.rename(entity.path, name));
      }
    }
    if (action == 'Details') {
      final stat = await entity.stat();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(p.basename(entity.path)),
            content: SelectableText(
              '${entity.path}\n${bytes(stat.size)}\nModified: ${stat.modified}\nType: ${stat.type}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
    if (action == 'Inspect ZIP') {
      await operation('Inspect ZIP', (token) async {
        final names = await service.inspectZip(entity.path);
        token.check();
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Archive contents'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: ListView(children: names.map((n) => Text(n)).toList()),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      });
    }
    if (action == 'Extract ZIP') {
      final name = await prompt(
        'New extraction folder',
        initial: p.basenameWithoutExtension(entity.path),
      );
      if (name != null) {
        final password = await prompt(
          'ZIP password (leave empty if none)',
          secret: true,
        );
        if (password == null) return;
        await operation(
          'Extract ZIP',
          (token) => service.extractZip(
            entity.path,
            safeChild(current!, name),
            token,
            password: password.isEmpty ? null : password,
            onProgress: (v) {
              final app = ref.read(controllerProvider);
              app.progress = v;
              app.notifyListeners();
            },
          ),
        );
      }
    }
  }

  Future<void> showLarge(List<IndexedFile> input) => Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => LargeFilesPage(files: input)),
  );

  List<String> breadcrumbs(String path) {
    final output = <String>[path];
    var parent = p.dirname(path);
    while (parent != output.last && output.length < 64) {
      output.add(parent);
      parent = p.dirname(parent);
    }
    return output.reversed.toList();
  }

  Iterable<MapEntry<String, int>> folderRanking(List<IndexedFile> files) {
    final totals = <String, int>{};
    for (final file in files) {
      totals.update(
        p.dirname(file.path),
        (v) => v + file.size,
        ifAbsent: () => file.size,
      );
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  Future<void> openSaf() async {
    final app = ref.read(controllerProvider);
    try {
      final uri = await app.native.chooseTree();
      if (uri != null && mounted) {
        await app.set('lastSafTree', uri);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => SafPage(uri: uri)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => listingError = '$e');
    }
  }
}
