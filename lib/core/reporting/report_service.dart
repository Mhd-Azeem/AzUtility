import 'dart:convert';
import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;

class ReportService {
  String csv(List<Map<String,dynamic>> records) {
    String quote(Object? value) => '"${value.toString().replaceAll('"','""')}"';
    return ['category,title,created,payload',...records.map((r)=>['category','title','created','payload'].map((k)=>quote(k=='payload'?jsonEncode(r[k]):r[k])).join(','))].join('\r\n');
  }
  Future<String> export(String directory,String format,List<Map<String,dynamic>> records) async {
    final path=p.join(directory,'AZUtility-report-${DateTime.now().microsecondsSinceEpoch}.$format');
    if(format=='pdf') {
      final document=pw.Document();
      document.addPage(pw.MultiPage(build:(_)=>[
        pw.Header(level:0,child:pw.Text('AZ Utility - Local diagnostic report')),
        pw.Text('Generated ${DateTime.now().toIso8601String()}. Measurements reflect only the tests performed.'),
        for(final record in records) ...[
          pw.Header(level:1,child:pw.Text('${record['category']} - ${record['title']}')),
          pw.Text('${record['created']}'),
          pw.Text(const JsonEncoder.withIndent('  ').convert(record['payload']).replaceAll(RegExp(r'[^\x20-\x7E\n]'),'?')),
        ],
      ]));
      await File(path).writeAsBytes(await document.save(),flush:true);
    } else { await File(path).writeAsString(format=='csv'?csv(records):const JsonEncoder.withIndent('  ').convert(records),flush:true); }
    return path;
  }
}
