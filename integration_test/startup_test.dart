import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:integration_test/integration_test.dart';
import 'package:az_utility/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device startup opens integrated dashboard', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.text('Your system. In focus.'), findsOneWidget);
    expect(find.text('AZ Network Analyzer'), findsOneWidget);
    expect(find.text('AZ Smart File Manager'), findsOneWidget);
    expect(find.text('AZ Device Doctor'), findsOneWidget);
    final metrics = await const MethodChannel(
      'com.az.utility/native',
    ).invokeListMethod<dynamic>('snapshot');
    expect(metrics, isNotEmpty);
    if (Platform.isWindows) {
      expect(
        metrics!.where((dynamic m) => m['label'] == 'System RAM used'),
        hasLength(1),
      );
      expect(
        metrics
            .where((dynamic m) => m['label'] == 'Architecture')
            .first['value'],
        'x64',
      );
    }
    await tester.ensureVisible(find.text('AZ Device Doctor'));
    await tester.tap(find.text('AZ Device Doctor'));
    await tester.pumpAndSettle();
    expect(find.text('Full hardware inventory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
