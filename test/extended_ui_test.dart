import 'package:az_utility/app/controller.dart';
import 'package:az_utility/core/database/app_database.dart';
import 'package:az_utility/features/device_doctor/device_page.dart';
import 'package:az_utility/features/smart_file_manager/large_files_page.dart';
import 'package:az_utility/core/models.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 1360.0]) {
    testWidgets('metric detail and file review remain usable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.az.utility/native'),
            (call) async => call.method == 'snapshot'
                ? [
                    {
                      'label': 'System RAM used',
                      'value': '4 / 8 GiB',
                      'ratio': .5,
                      'status': 'available',
                    },
                  ]
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.az.utility/native'),
              null,
            ),
      );
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await tester.runAsync(() => container.read(controllerProvider).ready);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: DevicePage())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('System RAM used').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Current native observation and local history'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            key: UniqueKey(),
            home: LargeFilesPage(
              files: [
                IndexedFile(
                  '/accessible/large.txt',
                  20 * 1024 * 1024,
                  DateTime(2026),
                  'Documents',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('large.txt'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('Remove 1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await db.close();
    });
  }
}
