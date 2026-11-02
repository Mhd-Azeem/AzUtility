import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:az_utility/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native startup and authorized document-provider round trip', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.text('Your system. In focus.'), findsOneWidget);
    const channel = MethodChannel('com.az.utility/native');
    final metrics = await channel.invokeListMethod<dynamic>('snapshot');
    expect(metrics, isNotEmpty);
    if (!Platform.isAndroid) return;
    const root = 'content://com.az.utility.integration/tree/root';
    final rows = await channel.invokeListMethod<dynamic>('listSaf', {
      'uri': root,
    });
    expect(rows!.where((dynamic r) => r['name'] == 'a.txt'), hasLength(1));
    final files = await channel.invokeListMethod<dynamic>('documentScan', {
      'uri': root,
    });
    expect(files, hasLength(2));
    final duplicates = await channel.invokeListMethod<dynamic>(
      'documentDuplicates',
      {'uri': root},
    );
    expect(duplicates, hasLength(1));
    expect((duplicates!.single as List), hasLength(2));
    final a = (files!.first as Map)['uri'];
    final destination =
        (rows.firstWhere((dynamic r) => r['name'] == 'destination')
            as Map)['uri'];
    await channel.invokeMethod<dynamic>('documentCopy', {
      'uri': a,
      'destination': destination,
      'move': false,
    });
    final copied = await channel.invokeListMethod<dynamic>('listSaf', {
      'uri': destination,
    });
    expect(copied, hasLength(1));
    await expectLater(
      channel.invokeMethod<dynamic>('documentCopy', {
        'uri': a,
        'destination': destination,
      }),
      throwsA(isA<PlatformException>()),
    );
    final zip = await channel.invokeMethod<String>('documentZip', {
      'uri': root,
      'selected': [a],
      'name': 'fixture.zip',
    });
    final inspect = await channel.invokeListMethod<dynamic>('documentInspect', {
      'uri': zip,
    });
    expect(inspect, hasLength(1));
    final extracted = await channel.invokeMethod<String>('documentExtract', {
      'uri': zip,
      'destination': root,
      'name': 'extracted',
    });
    final extractedRows = await channel.invokeListMethod<dynamic>('listSaf', {
      'uri': extracted,
    });
    expect(extractedRows, hasLength(1));
    final after = await channel.invokeListMethod<dynamic>('documentScan', {
      'uri': root,
    });
    expect(after, hasLength(5));
  });
}
