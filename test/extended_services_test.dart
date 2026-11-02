import 'dart:io';
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
