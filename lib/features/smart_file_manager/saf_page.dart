import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/controller.dart';
import '../../core/models.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/widgets/dashboard_widgets.dart';

class SafPage extends ConsumerStatefulWidget {
  const SafPage({super.key, required this.uri, this.media = false});
  final String uri;
  final bool media;
  @override
  ConsumerState<SafPage> createState() => _SafPageState();
}

class _SafPageState extends ConsumerState<SafPage> {
  final native = const NativeBridge();
  List<Map<dynamic, dynamic>> rows = [];
  List<Map<dynamic, dynamic>> indexed = [];
  List<List<Map<dynamic, dynamic>>> groups = [];
  final selected = <String>{};
  String? error;
  String search = '';
  String status = '';
  bool loading = true, busy = false;
  Timer? polling;
  @override
  void initState() {
    super.initState();
    load();
    final cached = ref.read(controllerProvider).settings['safLatestIndex'];
    if (cached is Map &&
        cached['root'] == widget.uri &&
        cached['rows'] is List) {
      indexed = (cached['rows'] as List).cast<Map<dynamic, dynamic>>();
    }
  }

  @override
  void dispose() {
    polling?.cancel();
    if (busy) unawaited(native.invoke('cancelDocuments'));
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result =
          await native.invoke(widget.media ? 'listMedia' : 'listSaf', {
                'uri': widget.uri,
              })
              as List;
      if (mounted) {
        setState(() {
          rows = result.cast<Map<dynamic, dynamic>>();
          loading = false;
          error = null;
          selected.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<String?> prompt(String title, {String initial = ''}) async {
    final input = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<dynamic> job(String method, Map<String, dynamic> args) async {
    if (busy) return null;
    final app = ref.read(controllerProvider);
    setState(() {
      busy = true;
      error = null;
      status = 'Working…';
    });
    polling = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final p = await native.invoke('documentProgress');
        if (mounted && busy) setState(() => status = '$p');
      } catch (_) {
        /* Operation result carries failures. */
      }
    });
    try {
      final value = await native.invoke(method, args);
      await app.db.save('files', method, {
        'root': widget.uri,
        'summary': method == 'documentScan'
            ? {
                'files': (value as List).length,
                'coverage': 'Granted provider tree only',
              }
            : method == 'documentDuplicates'
            ? {'groups': (value as List).length}
            : value,
      });
      if (mounted) setState(() => status = 'Completed');
      return value;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      return null;
    } finally {
      polling?.cancel();
      if (mounted) setState(() => busy = false);
      await app.refresh();
    }
  }

  Future<void> scan(bool duplicate) async {
    final value = await job(duplicate ? 'documentDuplicates' : 'documentScan', {
      'uri': widget.uri,
      'exclusions':
          (ref.read(controllerProvider).settings['exclusions'] as String? ??
                  '.git,node_modules')
              .split(','),
    });
    if (value is List && mounted) {
      setState(() {
        if (duplicate) {
          groups = value
              .map((g) => (g as List).cast<Map<dynamic, dynamic>>())
              .toList();
        } else {
          indexed = value.cast<Map<dynamic, dynamic>>()
            ..sort((a, b) => (b['size'] as num).compareTo(a['size'] as num));
        }
      });
      if (!duplicate) {
        await ref.read(controllerProvider).db.set('safLatestIndex', {
          'root': widget.uri,
          'rows': indexed.map((r) => Map<String, dynamic>.from(r)).toList(),
        });
      }
    }
  }

  Future<void> action(String method, Map<dynamic, dynamic> row) async {
    try {
      if (method == 'safOpen' || method == 'safShare') {
        await native.invoke(method, {'uri': row['uri'], 'mime': row['mime']});
        return;
      }
      if (method == 'copy' || method == 'move') {
        final destination = await native.chooseTree();
        if (destination == null) return;
        await job('documentCopy', {
          'uri': row['uri'],
          'destination': destination,
          'move': method == 'move',
        });
        await load();
        return;
      }
      if (method == 'documentInspect') {
        final contents = await job(method, {'uri': row['uri']});
        if (mounted && contents != null) {
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('ZIP contents'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: SingleChildScrollView(
                  child: SelectableText((contents as List).join('\n')),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
        return;
      }
      if (method == 'documentExtract') {
        final destination = await native.chooseTree();
        if (destination == null) return;
        final name = await prompt(
          'New extraction folder',
          initial: 'Extracted',
        );
        if (name == null || name.isEmpty) return;
        await job(method, {
          'uri': row['uri'],
          'destination': destination,
          'name': name,
        });
        await load();
        return;
      }
      if (method == 'safDelete') {
        if (!mounted) return;
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Permanently delete document?'),
            content: Text(
              '${row['name']}\nFolders include their contents. Recovery is not guaranteed by the document provider.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Delete permanently'),
              ),
            ],
          ),
        );
        if (yes != true) return;
        await native.invoke(method, {'uri': row['uri']});
        await load();
        return;
      }
      final name = await prompt(
        method == 'safRename' ? 'Rename document' : 'New folder',
        initial: method == 'safRename' ? '${row['name']}' : '',
      );
      if (name == null || name.trim().isEmpty) return;
      await native.invoke(method, {'uri': row['uri'], 'name': name});
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = rows
        .where(
          (r) => '${r['name']}'.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    final categories = <String, int>{};
    for (final r in indexed) {
      categories.update(
        classify('${r['name']}'),
        (v) => v + (r['size'] as num).toInt(),
        ifAbsent: () => (r['size'] as num).toInt(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.media ? 'Accessible media library' : 'Document storage',
        ),
        actions: [
          if (!widget.media)
            IconButton(
              tooltip: 'Create folder',
              onPressed: busy
                  ? null
                  : () => action('safCreateFolder', {'uri': widget.uri}),
              icon: const Icon(Icons.create_new_folder),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        widget.media
                            ? 'MediaStore: only media currently granted by Android. Partial photo access and denied audio access reduce coverage. Reselect permissions to change access.'
                            : 'Only the selected provider tree is accessible. Scan and hashing are read-only. Copies never overwrite existing names.',
                      ),
                      if (error != null)
                        SelectableText(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search this folder',
                        ),
                        onChanged: (v) => setState(() => search = v),
                      ),
                      ActionWrap(
                        children: [
                          if (widget.media)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      await native.invoke(
                                        'requestMediaPermission',
                                      );
                                      await load();
                                    },
                              child: const Text('Choose media access'),
                            ),
                          if (!widget.media) ...[
                            TextButton(
                              onPressed: busy ? null : () => scan(false),
                              child: const Text('Scan & largest files'),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => scan(true),
                              child: const Text('Find duplicates'),
                            ),
                            if (selected.isNotEmpty)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final name = await prompt(
                                          'New ZIP name',
                                          initial: 'Archive.zip',
                                        );
                                        if (name != null) {
                                          await job('documentZip', {
                                            'uri': widget.uri,
                                            'selected': selected.toList(),
                                            'name': name,
                                          });
                                          await load();
                                        }
                                      },
                                child: Text('ZIP ${selected.length} selected'),
                              ),
                          ],
                          if (busy)
                            OutlinedButton(
                              onPressed: () => native.invoke('cancelDocuments'),
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                      if (status.isNotEmpty) Text(status),
                      if (busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (c, i) {
                      final row = filtered[i];
                      final directory =
                          row['mime'] == 'vnd.android.document/directory';
                      return ListTile(
                        leading: Checkbox(
                          value: selected.contains(row['uri']),
                          onChanged: busy
                              ? null
                              : (v) => setState(
                                  () => v == true
                                      ? selected.add(row['uri'] as String)
                                      : selected.remove(row['uri']),
                                ),
                        ),
                        title: Text('${row['name']}'),
                        subtitle: Text(
                          '${row['mime']} · ${bytes(row['size'] as num)}',
                        ),
                        onTap: busy
                            ? null
                            : () => directory
                                  ? Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            SafPage(uri: row['uri'] as String),
                                      ),
                                    )
                                  : action('safOpen', row),
                        trailing: PopupMenuButton<String>(
                          onSelected: (m) => action(m, row),
                          enabled: !busy,
                          itemBuilder: (_) => [
                            for (final entry in [
                              ('safShare', 'Share'),
                              if (!widget.media) ...[
                                ('copy', 'Copy to folder'),
                                ('move', 'Move to folder'),
                                ('safRename', 'Rename'),
                                ('safDelete', 'Delete permanently'),
                              ],
                              if (!directory &&
                                  '${row['name']}'.toLowerCase().endsWith(
                                    '.zip',
                                  )) ...[
                                ('documentInspect', 'Inspect ZIP'),
                                ('documentExtract', 'Extract ZIP'),
                              ],
                            ])
                              PopupMenuItem(
                                value: entry.$1,
                                child: Text(entry.$2),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (indexed.isNotEmpty || groups.isNotEmpty)
                  SizedBox(
                    height: 240,
                    child: ListView(
                      children: [
                        if (indexed.isNotEmpty)
                          Text(
                            'Indexed ${indexed.length} files · ${categories.entries.map((e) => '${e.key}: ${bytes(e.value)}').join(' · ')}',
                          ),
                        for (final row in indexed.take(100))
                          ListTile(
                            title: Text('${row['name']}'),
                            subtitle: Text('${row['uri']}'),
                            trailing: Text(bytes(row['size'] as num)),
                            onTap: () => action('safOpen', row),
                          ),
                        for (final group in groups.take(100))
                          ExpansionTile(
                            title: Text(
                              '${group.length} duplicates · ${bytes((group.first['size'] as num) * (group.length - 1))} reclaimable',
                            ),
                            children: [
                              for (final row in group)
                                ListTile(
                                  title: Text('${row['name']}'),
                                  subtitle: Text('${row['uri']}'),
                                  onTap: () => action('safOpen', row),
                                  trailing: IconButton(
                                    tooltip: 'Delete this copy permanently',
                                    onPressed: () => action('safDelete', row),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
