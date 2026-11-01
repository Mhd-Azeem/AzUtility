import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/controller.dart';
import '../../core/reporting/report_service.dart';
import '../../core/widgets/dashboard_widgets.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String category = 'all';
  DateTime? since;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    final records = app.history
        .where(
          (r) =>
              (category == 'all' || r['category'] == category) &&
              (since == null ||
                  DateTime.parse(r['created'] as String).isAfter(since!)),
        )
        .toList();
    return PageBody(
      title: 'Reports & history',
      subtitle:
          'Local evidence, measured results and portable exports · Latest 100 records',
      children: [
        ActionWrap(
          children: [
            DropdownButton<String>(
              value: category,
              items: [
                for (final c in ['all', 'network', 'files', 'device'])
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => category = v!),
            ),
            TextButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDate: since ?? DateTime.now(),
                );
                if (date != null) setState(() => since = date);
              },
              child: Text(
                since == null
                    ? 'Filter from date'
                    : since.toString().substring(0, 10),
              ),
            ),
            if (since != null)
              TextButton(
                onPressed: () => setState(() => since = null),
                child: const Text('Clear date filter'),
              ),
            for (final format in ['json', 'csv', 'pdf'])
              OutlinedButton(
                onPressed: app.busy || records.isEmpty
                    ? null
                    : () => export(format, records),
                child: Text('Export ${format.toUpperCase()}'),
              ),
          ],
        ),
        if (records.isEmpty)
          const Panel(
            child: Text(
              'No matching sessions. Run a diagnostic, benchmark or storage scan to create a report.',
            ),
          ),
        for (final record in records)
          Panel(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${record['title']}'),
              subtitle: Text('${record['category']} · ${record['created']}'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(record['payload']),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> export(String format, List<Map<String, dynamic>> records) async {
    if (Platform.isAndroid) {
      final app = ref.read(controllerProvider);
      await app.run('Export ${format.toUpperCase()}', (token) async {
        final folder = await getTemporaryDirectory();
        final path = await ReportService().export(folder.path, format, records);
        try {
          token.check();
          final destination = await FilePicker.saveFile(
            fileName: p.basename(path),
            bytes: await File(path).readAsBytes(),
            mimeType: format == 'pdf'
                ? 'application/pdf'
                : format == 'json'
                ? 'application/json'
                : 'text/csv',
          );
          app.result = {'export': destination ?? 'Save cancelled'};
        } finally {
          await File(path).delete();
        }
      });
      return;
    }
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose export folder',
    );
    if (directory == null || !mounted) return;
    final app = ref.read(controllerProvider);
    await app.run('Export ${format.toUpperCase()}', (token) async {
      token.check();
      final path = await ReportService().export(directory, format, records);
      token.check();
      app.result = {'export': path};
      await OpenFilex.open(path);
    });
  }
}
