import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/platform/native_bridge.dart';

class SafPage extends StatefulWidget {
  const SafPage({super.key, required this.uri});
  final String uri;
  @override
  State<SafPage> createState() => _SafPageState();
}

class _SafPageState extends State<SafPage> {
  final native = const NativeBridge();
  List<Map<dynamic, dynamic>> rows = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result =
          await native.invoke('listSaf', {'uri': widget.uri}) as List<dynamic>;
      if (mounted) {
        setState(() {
          rows = result.cast<Map<dynamic, dynamic>>();
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> action(String method, Map<dynamic, dynamic> row) async {
    try {
      if (method == 'safOpen') {
        await native.invoke(method, {'uri': row['uri'], 'mime': row['mime']});
        return;
      }
      final input = TextEditingController(
        text: method == 'safRename' ? row['name'] as String : '',
      );
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            method == 'safDelete'
                ? 'Permanently delete this document?'
                : method == 'safRename'
                ? 'Rename document'
                : 'New folder',
          ),
          content: method == 'safDelete'
              ? const Text(
                  'Recovery is not guaranteed by the document provider.',
                )
              : TextField(controller: input),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                method == 'safDelete' ? 'confirmed' : input.text,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (value == null || value.trim().isEmpty) return;
      await native.invoke(method, {'uri': row['uri'], 'name': value});
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Android document storage'),
      actions: [
        IconButton(
          tooltip: 'Create folder',
          onPressed: () => action('safCreateFolder', {'uri': widget.uri}),
          icon: const Icon(Icons.create_new_folder),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (error != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final directory =
                        row['mime'] == 'vnd.android.document/directory';
                    return ListTile(
                      leading: Icon(
                        directory ? Icons.folder : Icons.insert_drive_file,
                      ),
                      title: Text('${row['name']}'),
                      subtitle: Text(
                        '${row['mime']} · ${bytes(row['size'] as num)}',
                      ),
                      onTap: () => directory
                          ? Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    SafPage(uri: row['uri'] as String),
                              ),
                            )
                          : action('safOpen', row),
                      trailing: PopupMenuButton<String>(
                        onSelected: (method) => action(method, row),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'safRename',
                            child: Text('Rename'),
                          ),
                          if (!directory)
                            const PopupMenuItem(
                              value: 'safDelete',
                              child: Text('Delete permanently'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
  );
}
