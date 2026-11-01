import 'dart:io';

import 'package:az_utility/core/database/app_database.dart';
import 'package:az_utility/core/models.dart';
import 'package:az_utility/core/reporting/report_service.dart';
import 'package:az_utility/features/network_analyzer/network_service.dart';
import 'package:az_utility/features/smart_file_manager/file_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:az_utility/features/device_doctor/device_service.dart';
import 'package:az_utility/core/platform/native_bridge.dart';

void main() {
  test('v1 database upgrades preserve settings and history', () async {
    final root = await Directory.systemTemp.createTemp('az-migration-');
    addTearDown(() => root.delete(recursive: true));
    final path = p.join(root.path, 'old.sqlite');
    final old = sql.sqlite3.open(path);
    old.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    old.execute(
      'CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL, title TEXT NOT NULL, created TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    old.execute("INSERT INTO settings VALUES ('light','true')");
    old.execute('PRAGMA user_version=1');
    old.close();
    final db = AppDatabase(NativeDatabase(File(path)));
    expect((await db.settings())['light'], true);
    await db.saveIndex([
      IndexedFile('test.txt', 4, DateTime(2026), 'Documents'),
    ]);
    expect((await db.loadIndex()).single.size, 4);
    await db.close();
  });
  test('malicious ZIP cannot escape its new destination', () async {
    final root = await Directory.systemTemp.createTemp('az-malicious-');
    addTearDown(() => root.delete(recursive: true));
    final archive = Archive()
      ..addFile(ArchiveFile('../escaped.txt', 3, [1, 2, 3]));
    final path = p.join(root.path, 'bad.zip');
    await File(path).writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      FileService().extractZip(path, p.join(root.path, 'out'), Cancellation()),
      throwsFormatException,
    );
    expect(await File(p.join(root.path, 'escaped.txt')).exists(), isFalse);
  });
  test(
    'memory benchmark has explicit conservative bounds and CPU cancels',
    () async {
      const service = DeviceService(NativeBridge());
      final memory = await service.benchmark('Memory', Cancellation()).toList();
      expect(memory.last['peakChunkMiB'], 8);
      expect(memory.last['allocatedMiB'], 64);
      final token = Cancellation();
      await expectLater(
        service.benchmark('CPU', token).map((event) {
          token.cancel();
          return event;
        }).toList(),
        throwsA(isA<Cancelled>()),
      );
    },
  );
  test(
    'network statistics use TCP successes and attempt failure denominator',
    () {
      final stats = NetworkStats([
        NetworkSample(DateTime(2026), tcpMs: 10),
        NetworkSample(DateTime(2026), tcpMs: 30),
        NetworkSample(DateTime(2026), error: 'Timeout'),
      ]);
      expect(stats.mean, 20);
      expect(stats.jitter, 20);
      expect(stats.failurePercent, closeTo(100 / 3, 0.001));
      expect(NetworkStats([]).mean, isNull);
    },
  );
  test('endpoints require HTTPS and reject embedded credentials', () {
    final service = NetworkService();
    expect(() => service.endpoint('http://example.com'), throwsFormatException);
    expect(
      () => service.endpoint('https://user:secret@example.com'),
      throwsFormatException,
    );
    expect(service.endpoint('https://example.com').host, 'example.com');
  });
  test(
    'offline socket failure is retained as evidence without fake latency',
    () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = listener.port;
      await listener.close();
      final sample = await NetworkService().measure(
        Uri.parse('https://127.0.0.1:$port'),
        Cancellation(),
        timeout: const Duration(milliseconds: 100),
      );
      expect(sample.tcpMs, isNull);
      expect(sample.error, isNotNull);
    },
  );
  test(
    'throughput rejects excessive transfers before accessing network',
    () async {
      await expectLater(
        NetworkService()
            .throughput(
              Uri.parse('https://example.invalid'),
              upload: false,
              limit: 65 * 1024 * 1024,
              cancel: Cancellation(),
            )
            .toList(),
        throwsArgumentError,
      );
    },
  );
  test('cancelled network test never produces a successful sample', () async {
    await expectLater(
      NetworkService().measure(
        Uri.parse('https://example.invalid'),
        Cancellation()..cancel(),
      ),
      throwsA(isA<Cancelled>()),
    );
  });
  test('file categories are case insensitive', () {
    expect(classify('PHOTO.JPG'), 'Images');
    expect(classify('report.xlsx'), 'Documents');
    expect(classify('unknown.bin'), 'Other');
  });
  test(
    'private address validation excludes public, loopback and malformed IPs',
    () {
      for (final ip in ['10.1.2.3', '172.16.0.1', '192.168.1.2']) {
        expect(privateV4(ip), isTrue);
      }
      for (final ip in [
        '8.8.8.8',
        '127.0.0.1',
        '172.32.0.1',
        '10.999.1.1',
        '10.1.1',
      ]) {
        expect(privateV4(ip), isFalse);
      }
    },
  );
  test('archive traversal and invalid names rejected', () {
    final root = p.absolute('sandbox');
    for (final name in [
      '../escape',
      'a/../../escape',
      '/absolute',
      'C:/escape',
      r'a\..\escape',
    ]) {
      expect(() => archiveDestination(root, name), throwsFormatException);
    }
    for (final name in ['../escape', 'a/b', r'a\b', '']) {
      expect(() => safeChild(root, name), throwsArgumentError);
    }
    expect(
      archiveDestination(root, 'folder/file.txt'),
      p.join(root, 'folder', 'file.txt'),
    );
  });
  test(
    'scanner, duplicate hashing, copy conflicts, cancellation and rename',
    () async {
      final root = await Directory.systemTemp.createTemp('az-test-');
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'a.txt')).writeAsString('same content');
      await File(p.join(root.path, 'b.txt')).writeAsString('same content');
      await File(p.join(root.path, 'c.txt')).writeAsString('different');
      final service = FileService();
      final updates = await service.scan(root.path, Cancellation()).toList();
      expect(updates.last.files, 3);
      expect(updates.last.done, isTrue);
      final groups = await service.duplicates(Cancellation(), (_, _) {});
      expect(groups.length, 1);
      expect(groups.single.length, 2);
      await expectLater(
        service.copy(
          p.join(root.path, 'a.txt'),
          p.join(root.path, 'b.txt'),
          Cancellation(),
        ),
        throwsA(isA<FileSystemException>()),
      );
      await service.copy(
        p.join(root.path, 'a.txt'),
        p.join(root.path, 'd.txt'),
        Cancellation(),
      );
      expect(
        await File(p.join(root.path, 'd.txt')).readAsString(),
        'same content',
      );
      await service.rename(p.join(root.path, 'd.txt'), 'renamed.txt');
      expect(await File(p.join(root.path, 'renamed.txt')).exists(), isTrue);
      final cancelled = Cancellation()..cancel();
      await expectLater(
        service.scan(root.path, cancelled).toList(),
        throwsA(isA<Cancelled>()),
      );
    },
  );
  test(
    'ZIP round trip and extraction refuses an existing destination',
    () async {
      final root = await Directory.systemTemp.createTemp('az-zip-');
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'hello.txt'));
      await file.writeAsString('hello');
      final zip = p.join(root.path, 'archive.zip');
      final destination = p.join(root.path, 'out');
      final service = FileService();
      await service.createZip([file.path], zip, Cancellation());
      await service.extractZip(zip, destination, Cancellation());
      expect(
        await File(p.join(destination, 'hello.txt')).readAsString(),
        'hello',
      );
      await expectLater(
        service.extractZip(zip, destination, Cancellation()),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  test(
    'database creates schema, persists settings, isolates history categories',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.set('light', true);
      expect((await db.settings())['light'], true);
      await db.save('network', 'test', {'tcpMs': 12});
      await db.save('device', 'inventory', {});
      expect((await db.history()).length, 2);
      await db.clear('network');
      expect((await db.history()).single['category'], 'device');
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, 2);
    },
  );
  test('reports escape CSV cells and produce local JSON and PDF', () async {
    final root = await Directory.systemTemp.createTemp('az-report-');
    addTearDown(() => root.delete(recursive: true));
    final reports = ReportService();
    final rows = [
      {
        'category': 'network',
        'title': 'quoted "value"',
        'created': '2026-11-02',
        'payload': {'tcpMs': 10},
      },
    ];
    expect(reports.csv(rows), contains('"quoted ""value"""'));
    final json = await reports.export(root.path, 'json', rows);
    expect(await File(json).readAsString(), contains('tcpMs'));
    final pdf = await reports.export(root.path, 'pdf', rows);
    expect((await File(pdf).readAsBytes()).take(4), [37, 80, 68, 70]);
  });
  test('capability flags survive native map decoding', () {
    final metric = Metric.fromMap({
      'label': 'CPU',
      'value': 'Unavailable',
      'status': 'unsupported',
    });
    expect(metric.status, CapabilityStatus.unsupported);
    expect(metric.ratio, isNull);
  });
}
