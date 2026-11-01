import 'package:az_utility/app/az_utility_app.dart';
import 'package:az_utility/app/controller.dart';
import 'package:az_utility/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offline startup, navigation and persisted appearance', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.set('light', true);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    await tester.runAsync(() => container.read(controllerProvider).ready);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AzUtilityApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your system. In focus.'), findsOneWidget);
    await tester.tap(find.text('Network').last);
    await tester.pumpAndSettle();
    expect(find.text('Network Analyzer'), findsOneWidget);
    await tester.tap(find.text('Files').last);
    await tester.pumpAndSettle();
    expect(find.text('Smart File Manager'), findsOneWidget);
    await tester.tap(find.text('Device').last);
    await tester.pumpAndSettle();
    expect(find.text('Device Doctor'), findsOneWidget);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Light theme'), findsOneWidget);
    final context = tester.element(find.text('Light theme'));
    expect(Theme.of(context).brightness, Brightness.light);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await database.close();
  });
}
