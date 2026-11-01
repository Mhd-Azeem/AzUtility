import 'dart:convert';
import 'dart:io';

import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;

class ReportService {
  String csv(List<Map<String, dynamic>> records) {
    String quote(Object? value) {
      var text = value?.toString() ?? '';
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(text)) {
        text = "'$text";
      }
      return '"${text.replaceAll('"', '""')}"';
    }

    return [
      'category,title,created,payload',
      ...records.map(
        (r) => [
          'category',
          'title',
          'created',
          'payload',
        ].map((k) => quote(k == 'payload' ? jsonEncode(r[k]) : r[k])).join(','),
      ),
    ].join('\r\n');
  }

  Future<String> export(
    String directory,
    String format,
    List<Map<String, dynamic>> records,
  ) async {
    final path = p.join(
      directory,
      'AZUtility-report-${DateTime.now().microsecondsSinceEpoch}.$format',
    );
    if (format == 'pdf') {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          maxPages: 1000,
          build: (_) => [
            pw.Header(
              level: 0,
              child: pw.Text('AZ Utility - Local diagnostic report'),
            ),
            pw.Text(
              'Generated ${DateTime.now().toIso8601String()}. Measurements reflect only the tests performed.',
            ),
            for (final record in records) ...[
              pw.Header(
                level: 1,
                child: pw.Text('${record['category']} - ${record['title']}'),
              ),
              pw.Text('${record['created']}'),
              for (final line in _pdfLines(record['payload'])) pw.Text(line),
            ],
          ],
        ),
      );
      await File(path).writeAsBytes(await document.save(), flush: true);
    } else {
      await File(path).writeAsString(
        format == 'csv'
            ? csv(records)
            : const JsonEncoder.withIndent('  ').convert(records),
        flush: true,
      );
    }
    return path;
  }

  List<String> _pdfLines(dynamic payload) {
    dynamic summary = payload;
    if (payload is Map && payload['samples'] is List) {
      final samples = payload['samples'] as List;
      final times = samples
          .whereType<Map>()
          .map((s) => s['tcpMs'])
          .whereType<num>()
          .toList();
      summary = {
        ...payload,
        'samples': {
          'count': samples.length,
          'tcpSuccesses': times.length,
          'meanTcpMs': times.isEmpty
              ? null
              : times.reduce((a, b) => a + b) / times.length,
          'details': 'Export JSON or CSV for individual measurements.',
        },
      };
    }
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(summary).replaceAll(RegExp(r'[^\x20-\x7E\n]'), '?');
    // Keep every widget small enough to fit on a page, even for long paths.
    return text
        .split('\n')
        .expand(
          (line) => [
            if (line.isEmpty) ' ',
            for (int i = 0; i < line.length; i += 90)
              line.substring(i, (i + 90).clamp(0, line.length)),
          ],
        )
        .toList();
  }
}
