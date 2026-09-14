import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  test('the preview placement key matches the native contract', () {
    expect(revnixPreviewPlacementKey, 'revnix_preview');
  });

  group('PlacementResolution.preview', () {
    test('parses true only when the wire map says so', () {
      final withPreview = PlacementResolution.fromMap(const {
        'status': 'ok',
        'placementKey': 'revnix_preview',
        'preview': true,
      });
      expect(withPreview.preview, isTrue);
      expect(withPreview.revision, 0);
      expect(withPreview.offering.packages, isEmpty);

      final withoutPreview = PlacementResolution.fromMap(const {
        'status': 'ok',
        'placementKey': 'onboarding',
      });
      expect(withoutPreview.preview, isFalse);
    });
  });

  final packages = [
    const RevnixPaywallPackage(
      packageId: 'monthly',
      title: 'Monthly',
      priceLabel: r'$9.99',
    ),
  ];

  group('RevnixPaywall disables purchasing in preview', () {
    testWidgets('a classic-layout CTA tap does not call onPurchase', (tester) async {
      var bought = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RevnixPaywall(
            config: const PaywallConfig(
              template: 'focus',
              headline: 'Go Pro',
              ctaLabel: 'Continue',
            ),
            packages: packages,
            placementKey: revnixPreviewPlacementKey,
            disableViewTracking: true,
            onPurchase: (_) => bought++,
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(bought, 0);
      expect(find.text('Purchases are disabled in preview.'), findsOneWidget);
    });

    testWidgets('a designed-paywall button tap does not call onPurchase',
        (tester) async {
      var bought = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RevnixPaywall(
            config: PaywallConfig(
              template: 'classic',
              headline: 'Go Pro',
              ctaLabel: 'Continue',
              blocks: const {
                'blocks': [
                  {'id': 'b', 'type': 'button', 'label': 'Continue'},
                ],
              },
            ),
            packages: packages,
            placementKey: revnixPreviewPlacementKey,
            disableViewTracking: true,
            onPurchase: (_) => bought++,
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(bought, 0);
      expect(find.text('Purchases are disabled in preview.'), findsOneWidget);
    });

    testWidgets('an ordinary placementKey purchases normally', (tester) async {
      var bought = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RevnixPaywall(
            config: const PaywallConfig(
              template: 'focus',
              headline: 'Go Pro',
              ctaLabel: 'Continue',
            ),
            packages: packages,
            placementKey: 'onboarding',
            disableViewTracking: true,
            onPurchase: (_) => bought++,
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(bought, 1);
    });
  });
}
