import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../app/controller.dart';
import '../../core/models.dart';
import '../../core/widgets/dashboard_widgets.dart';

class LargeFilesPage extends ConsumerStatefulWidget {
  const LargeFilesPage({super.key, required this.files});
  final List<IndexedFile> files;
  @override
  ConsumerState<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends ConsumerState<LargeFilesPage> {
  int minimum = 0;
  String category = 'All', search = '';
  bool descending = true;
  final selected = <String>{}, removed = <String>{};
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    final files =
        widget.files
            .where(
              (f) =>
                  !removed.contains(f.path) &&
                  f.size >= minimum &&
                  (category == 'All' || f.category == category) &&
                  f.path.toLowerCase().contains(search.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => descending
                ? b.size.compareTo(a.size)
                : a.size.compareTo(b.size),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Files by size')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Indexed accessible subset · ${files.length} matching files · ${bytes(files.fold<int>(0, (n, f) => n + f.size))}',
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Filter name or location',
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
                ActionWrap(
                  children: [
                    DropdownButton<int>(
                      value: minimum,
                      items: [
                        for (final n in [
                          0,
                          10 * 1024 * 1024,
                          100 * 1024 * 1024,
                          1024 * 1024 * 1024,
                        ])
                          DropdownMenuItem(
                            value: n,
                            child: Text(
                              n == 0 ? 'All sizes' : 'At least ${bytes(n)}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => minimum = v!),
                    ),
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
                      onPressed: () => setState(() => descending = !descending),
                      child: Text(
                        descending ? 'Largest first' : 'Smallest first',
                      ),
                    ),
                    if (selected.isNotEmpty)
                      FilledButton(
                        onPressed: app.busy ? null : remove,
                        child: Text('Remove ${selected.length} selected'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (c, i) {
                final f = files[i];
                return ListTile(
                  leading: Checkbox(
                    value: selected.contains(f.path),
                    onChanged: app.busy
                        ? null
                        : (v) => setState(
                            () => v == true
                                ? selected.add(f.path)
                                : selected.remove(f.path),
                          ),
                  ),
                  title: Text(p.basename(f.path)),
                  subtitle: Text('${f.path}\n${f.category} · ${f.modified}'),
                  trailing: Text(bytes(f.size)),
                  onTap: () => OpenFilex.open(f.path),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> remove() async {
    final app = ref.read(controllerProvider);
    final targets = selected.toList();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${targets.length} files?'),
        content: Text(
          Platform.isWindows
              ? 'Windows will try to recycle these files; it may request permanent removal on unsupported volumes.'
              : 'These files will be permanently deleted. Recovery is not guaranteed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await app.run('Remove reviewed files', (token) async {
      for (final path in targets) {
        token.check();
        if (Platform.isWindows) {
          await app.native.invoke('recycle', {'path': path});
        } else {
          await app.files.deleteFile(path);
        }
        removed.add(path);
        app.files.index.removeWhere((f) => f.path == path);
        selected.remove(path);
      }
      await app.db.saveIndex(app.files.index);
      await app.db.save('files', 'User-reviewed removal', {
        'count': removed.length,
      });
    });
    if (mounted) setState(() {});
  }
}
