import 'package:flutter_test/flutter_test.dart';
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
  });
}
