import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

// Runs on a real device/simulator, where the native SDKs are actually present.
// The resilience policy itself is proven in revnix-swift and revnix-kotlin;
// what this checks is that the plugin is registered and the channel answers.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('configure mints a persistent anonymous customer id',
      (WidgetTester tester) async {
    final revnix = await RevnixClient.configure(
      apiKey: 'rvx_pk_test_abc',
      baseUrl: 'https://your-deployment.convex.site',
    );

    final id = await revnix.customerId();
    expect(id, startsWith('rvx_anon_'));

    // Stable across calls — the id is persisted natively, not regenerated.
    expect(await revnix.customerId(), id);
  });

  testWidgets('a gate fails closed when nothing is entitled',
      (WidgetTester tester) async {
    final revnix = await RevnixClient.configure(
      apiKey: 'rvx_pk_test_abc',
      baseUrl: 'https://your-deployment.convex.site',
    );
    expect(await revnix.isEntitled('definitely-not-granted'), isFalse);
  });
}
