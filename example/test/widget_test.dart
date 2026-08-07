import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter_example/main.dart';

void main() {
  testWidgets('the example renders a gate state', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    // Without a configured backend the gate stays closed — fail-closed is the
    // correct default for a paid feature.
    expect(find.text('Locked'), findsOneWidget);
  });
}
