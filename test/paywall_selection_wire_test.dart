// Designed-paywall render contract v2 (REV-262).
//
// `paywall-selection-wire.json` is a byte-identical copy of the fixture every
// Revnix renderer walks in its own suite — the dashboard preview, React
// Native, iOS, Android, Unity, Capacitor and this one. Each case names a host
// selection and a config highlight and pins, per block id, the effective
// style, whether it is drawn, and the copy after tags. Six interpreters of
// one document agree on it or the test says which one drifted.
//
// The second half covers the parts of the contract the fixture cannot: the
// canvas filling a taller screen and scrolling on a shorter one, the pressed
// and loading states of a button, the close chip below the status bar, and
// the image downsampling rule.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  final wire = jsonDecode(File('test/paywall-selection-wire.json').readAsStringSync())
      as Map<String, Object?>;
  final doc = PaywallBlockDoc.parse(wire['doc'])!;
  final packages = [
    for (final p in wire['packages']! as List<Object?>)
      RevnixPaywallPackage(
        packageId: (p! as Map)['packageId'] as String,
        title: (p as Map)['title'] as String,
        priceLabel: p['priceLabel'] as String,
        period: p['period'] as String?,
        amountMinor: (p['amountMinor'] as num?)?.toInt(),
        currency: p['currency'] as String?,
      ),
  ];
  final cases = (wire['cases']! as List<Object?>).cast<Map<String, Object?>>();

  /// The selection a case's inputs resolve to — the host's choice, else the
  /// highlight, else the first package. No taps happen in a fixture walk.
  String? selectionOf(Map<String, Object?> c) => revnixResolveSelectedPackageId(
        packages,
        hostSelected: c['selected'] as String?,
        highlight: c['highlight'] as String?,
      );

  /// One style field by its wire name. Only the scalar fields the fixture
  /// can name; an unknown key fails loudly so a fixture that grows a new
  /// field is noticed here rather than silently passing.
  Object? styleField(BlockStyle? style, String key) => switch (key) {
        'fill' => style?.fill,
        'textColor' => style?.textColor,
        'opacity' => style?.opacity,
        'borderColor' => style?.borderColor,
        'borderWidth' => style?.borderWidth,
        'radius' => style?.radius,
        'padding' => style?.padding,
        'fontSize' => style?.fontSize,
        'fontWeight' => style?.fontWeight,
        'gap' => style?.gap,
        _ => throw ArgumentError('the fixture names a style field this test does not read: $key'),
      };

  Object? wireValue(Object? v) => v is num ? v.toDouble() : v;

  Widget host(
    PaywallBlockDoc doc, {
    List<RevnixPaywallPackage>? packages,
    String? selectedPackageId,
    bool loading = false,
    void Function(String)? onPurchase,
    VoidCallback? onClose,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: RevnixPaywallBlockScreen(
            ctx: BlockRenderContext(
              doc: doc,
              packages: packages ?? const [],
              selectedPackageId: selectedPackageId,
              loading: loading,
              onPurchase: onPurchase ?? (_) {},
              onSelect: (_) {},
              onClose: onClose,
            ),
          ),
        ),
      );

  group('the shared selection fixture', () {
    test('is byte-identical to the dashboard copy when that checkout is present', () {
      final upstream = File(
        '../revnix-app/tests/fixtures/paywall-selection-wire.json',
      );
      if (!upstream.existsSync()) return;
      expect(
        File('test/paywall-selection-wire.json').readAsBytesSync(),
        upstream.readAsBytesSync(),
      );
    });

    test('parses selectedStyle and visibility on non-card blocks', () {
      final resolved = revnixResolveBlocks(doc, packages: packages);
      expect(resolved['c0-on']!.block.visibility, BlockVisibility.selected);
      expect(resolved['c0-off']!.block.visibility, BlockVisibility.unselected);
      expect(resolved['c0-ring']!.block.selectedStyle?.borderColor, '@accent');
      expect(resolved['c0-dot']!.block.visibility, BlockVisibility.selected);
    });

    for (final c in cases) {
      final name = c['name'] as String;
      test('$name: resolves every pinned style, visibility and text', () {
        final resolved = revnixResolveBlocks(
          doc,
          packages: packages,
          selectedPackageId: selectionOf(c),
        );

        final styles = (c['styles'] as Map<String, Object?>? ?? const {});
        for (final entry in styles.entries) {
          final block = resolved[entry.key];
          expect(block, isNotNull, reason: '${entry.key} is missing from the walk');
          for (final field in (entry.value! as Map<String, Object?>).entries) {
            expect(
              wireValue(styleField(block!.style, field.key)),
              wireValue(field.value),
              reason: '${entry.key}.${field.key}',
            );
          }
        }

        for (final id in (c['visible'] as List<Object?>? ?? const []).cast<String>()) {
          expect(resolved[id]?.visible, isTrue, reason: '$id should be drawn');
        }
        for (final id in (c['hidden'] as List<Object?>? ?? const []).cast<String>()) {
          expect(resolved[id], isNotNull, reason: '$id is missing from the walk');
          expect(resolved[id]!.visible, isFalse, reason: '$id should be hidden');
        }

        final texts = (c['texts'] as Map<String, Object?>? ?? const {});
        for (final entry in texts.entries) {
          expect(resolved[entry.key]?.text, entry.value, reason: entry.key);
        }
      });

      testWidgets('$name: the screen draws what the walk resolved', (tester) async {
        final selected = selectionOf(c);
        final resolved = revnixResolveBlocks(
          doc,
          packages: packages,
          selectedPackageId: selected,
        );
        await tester.pumpWidget(host(doc, packages: packages, selectedPackageId: selected));

        // Every resolved text that is drawn is on screen exactly once; every
        // hidden one is absent. "Selected" and "Tap to select" each exist in
        // both cards, so this is the visibility rule as the customer sees it.
        for (final block in resolved.values) {
          final text = block.text;
          if (text == null) continue;
          final visible = resolved.values
              .where((b) => b.text == text)
              .where((b) => b.visible)
              .length;
          expect(find.text(text), findsNWidgets(visible), reason: text);
        }

        // The selected card carries the selected fill and border; the other
        // does not. Read off the decoration the way a customer sees it.
        for (final id in ['c0', 'c1']) {
          final style = resolved[id]!.style!;
          final title = resolved['$id-title']!.text!;
          final box = tester
              .widgetList<Container>(
                find.ancestor(of: find.text(title), matching: find.byType(Container)),
              )
              .map((w) => w.decoration)
              .whereType<BoxDecoration>()
              .firstWhere((d) => d.border != null);
          expect(box.color, revnixBlockColor(style.fill, doc), reason: '$id fill');
          expect(
            box.border!.top.color,
            revnixBlockColor(style.borderColor, doc),
            reason: '$id border',
          );
        }
      });
    }
  });

  group('selection rule', () {
    const a = RevnixPaywallPackage(packageId: 'a', title: 'A', priceLabel: r'$1');
    const b = RevnixPaywallPackage(packageId: 'b', title: 'B', priceLabel: r'$2');

    test('host, then tap, then highlight, then first — each only when offered', () {
      expect(revnixResolveSelectedPackageId([a, b], hostSelected: 'b'), 'b');
      expect(revnixResolveSelectedPackageId([a, b], hostSelected: 'zz', internalSelected: 'b'), 'b');
      expect(revnixResolveSelectedPackageId([a, b], internalSelected: 'zz', highlight: 'b'), 'b');
      expect(revnixResolveSelectedPackageId([a, b], highlight: 'zz'), 'a');
      expect(revnixResolveSelectedPackageId(const []), isNull);
    });

    test('a pinned card with a negative or unreachable index has no package', () {
      expect(revnixPinnedPackage(const CardBlock(id: 'c', packageIndex: -1), [a, b]), isNull);
      expect(revnixPinnedPackage(const CardBlock(id: 'c', packageIndex: 2), [a, b]), isNull);
      expect(revnixPinnedPackage(const CardBlock(id: 'c', packageIndex: 1), [a, b]), b);
      expect(revnixPinnedPackage(const CardBlock(id: 'c'), [a, b]), isNull);
    });

    test('selectedStyle and visibility are inert outside any package card', () {
      const block = TextBlock(
        id: 't',
        text: 'x',
        style: BlockStyle(fill: '#111111'),
        selectedStyle: BlockStyle(fill: '#222222'),
        visibility: BlockVisibility.selected,
      );
      const root = RevnixBlockScope.root(null);
      expect(revnixBlockVisible(block, root), isTrue);
      expect(revnixEffectiveStyle(block, root)?.fill, '#111111');
      final inSelected = root.enter(a, a);
      expect(revnixBlockVisible(block, inSelected), isTrue);
      expect(revnixEffectiveStyle(block, inSelected)?.fill, '#222222');
      final inOther = root.enter(b, a);
      expect(revnixBlockVisible(block, inOther), isFalse);
      expect(revnixEffectiveStyle(block, inOther)?.fill, '#111111');
    });

    test('a close on a conditional block does not count as a certain close', () {
      expect(
        revnixHasCloseAction(const [
          ButtonBlock(id: 'x', label: 'Not now', action: BlockAction.close, visibility: BlockVisibility.selected),
        ]),
        isFalse,
      );
      expect(
        revnixHasCloseAction(const [
          ButtonBlock(id: 'x', label: 'Not now', action: BlockAction.close),
        ]),
        isTrue,
      );
    });
  });

  group('rendering the contract', () {
    const palette = {
      'version': 1,
      'background': '#101014',
      'textColor': '#F5F7FA',
      'accent': '#6478ff',
      'accentInk': '#0B0D10',
    };
    PaywallBlockDoc docWith(List<Object?> blocks, [Map<String, Object?> extra = const {}]) =>
        PaywallBlockDoc.parse({...palette, ...extra, 'blocks': blocks})!;

    Future<void> surface(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('a root-level tag resolves against the selected package', (tester) async {
      final doc = docWith([
        {'id': 'f', 'type': 'text', 'text': '7 days free, then {price}/{period_short}.'},
      ]);
      await tester.pumpWidget(host(doc, packages: packages, selectedPackageId: 'yearly'));
      expect(find.text(r'7 days free, then $59.99/yr.'), findsOneWidget);
      await tester.pumpWidget(host(doc, packages: packages, selectedPackageId: 'monthly'));
      expect(find.text(r'7 days free, then $9.99/mo.'), findsOneWidget);
    });

    testWidgets('a root-level tag with nothing offered stays visible', (tester) async {
      final doc = docWith([
        {'id': 'f', 'type': 'text', 'text': 'then {price}'},
      ]);
      await tester.pumpWidget(host(doc));
      expect(find.text('then {price}'), findsOneWidget);
    });

    testWidgets('a negative packageIndex drops the card instead of throwing', (tester) async {
      final doc = docWith([
        {
          'id': 'c',
          'type': 'card',
          'packageIndex': -1,
          'children': [
            {'id': 't', 'type': 'text', 'text': 'never'},
          ],
        },
        {'id': 'k', 'type': 'text', 'text': 'kept'},
      ]);
      await tester.pumpWidget(host(doc, packages: packages));
      expect(tester.takeException(), isNull);
      expect(find.text('never'), findsNothing);
      expect(find.text('kept'), findsOneWidget);
    });

    testWidgets('a button dims to 80% while pressed and recovers on release', (tester) async {
      final doc = docWith([
        {'id': 'b', 'type': 'button', 'label': 'Go'},
      ]);
      await tester.pumpWidget(host(doc, packages: packages));
      Iterable<double> opacities() => tester
          .widgetList<Opacity>(find.ancestor(of: find.text('Go'), matching: find.byType(Opacity)))
          .map((o) => o.opacity);
      expect(opacities(), isNot(contains(RevnixBlockButton.pressedOpacity)));

      final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacities(), contains(RevnixBlockButton.pressedOpacity));

      await gesture.up();
      await tester.pump();
      expect(opacities(), isNot(contains(RevnixBlockButton.pressedOpacity)));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a button is announced as a button', (tester) async {
      final doc = docWith([
        {'id': 'b', 'type': 'button', 'label': 'Go'},
      ]);
      await tester.pumpWidget(host(doc, packages: packages));
      final semantics = tester.widgetList<Semantics>(
        find.ancestor(of: find.text('Go'), matching: find.byType(Semantics)),
      );
      expect(semantics.any((s) => s.properties.button == true), isTrue);
    });

    testWidgets('while loading a purchase button ignores taps and shows a spinner', (tester) async {
      var bought = 0;
      final doc = docWith([
        {'id': 'b', 'type': 'button', 'label': 'Go'},
      ]);
      await tester.pumpWidget(host(doc, packages: packages, loading: true, onPurchase: (_) => bought++));
      // The label is hidden but keeps its box, and the spinner is in the ink.
      final label = tester.widget<Opacity>(
        find.ancestor(of: find.text('Go'), matching: find.byType(Opacity)).first,
      );
      expect(label.opacity, 0);
      final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(spinner.color, revnixParseColor('#0B0D10'));
      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      await tester.pump();
      expect(bought, 0);
      // Disabled for assistive tech too.
      final semantics = tester.widgetList<Semantics>(
        find.ancestor(of: find.text('Go'), matching: find.byType(Semantics)),
      );
      expect(semantics.any((s) => s.properties.button == true && s.properties.enabled == false), isTrue);
    });

    testWidgets('loading leaves a close button working, with no spinner', (tester) async {
      var closed = 0;
      final doc = docWith([
        {'id': 'b', 'type': 'button', 'label': 'Not now', 'action': 'close'},
      ]);
      await tester.pumpWidget(host(doc, packages: packages, loading: true, onClose: () => closed++));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Not now'));
      expect(closed, 1);
    });

    testWidgets('the host passes loading through to a designed paywall', (tester) async {
      var bought = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RevnixPaywall(
            config: PaywallConfig(
              template: 'classic',
              headline: 'Go Pro',
              ctaLabel: 'Continue',
              blocks: {
                ...palette,
                'blocks': [
                  {'id': 'b', 'type': 'button', 'label': 'Continue'},
                ],
              },
            ),
            packages: packages,
            loading: true,
            disableViewTracking: true,
            onPurchase: (_) => bought++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      expect(bought, 0);
    });

    testWidgets('a canvas fills a taller viewport and does not scroll', (tester) async {
      await surface(tester, const Size(393, 1000));
      final doc = docWith([
        {'id': 't', 'type': 'text', 'text': 'Designed'},
      ], {'layout': 'canvas'});
      await tester.pumpWidget(host(doc));
      final box = tester.widget<SizedBox>(
        find.descendant(of: find.byType(Transform), matching: find.byType(SizedBox)).first,
      );
      expect(box.width, kRevnixCanvasWidth);
      // Layout height grows to the viewport in design units: no band.
      expect(box.height, 1000);
      final scroller = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scroller.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('a canvas scrolls on a shorter viewport, without an indicator', (tester) async {
      await surface(tester, const Size(393, 600));
      final doc = docWith([
        {'id': 't', 'type': 'text', 'text': 'Designed'},
      ], {'layout': 'canvas'});
      await tester.pumpWidget(host(doc));
      final box = tester.widget<SizedBox>(
        find.descendant(of: find.byType(Transform), matching: find.byType(SizedBox)).first,
      );
      expect(box.height, kRevnixCanvasHeight);
      final scroller = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scroller.physics, isA<RevnixPaywallScrollPhysics>());
      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, closeTo(kRevnixCanvasHeight - 600, 0.01));
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
    });

    testWidgets('a wide viewport caps the scale at 480 and centres the design', (tester) async {
      await surface(tester, const Size(800, 1200));
      final doc = docWith([
        {'id': 't', 'type': 'text', 'text': 'Designed'},
      ], {'layout': 'canvas'});
      await tester.pumpWidget(host(doc));
      final transform = tester.widget<Transform>(find.byType(Transform).first);
      final scale = kRevnixCanvasMaxWidth / kRevnixCanvasWidth;
      expect(transform.transform.getMaxScaleOnAxis(), closeTo(scale, 1e-9));
      final placed = tester.widget<Positioned>(
        find.ancestor(of: find.byType(Transform).first, matching: find.byType(Positioned)).first,
      );
      expect(placed.left, closeTo((800 - kRevnixCanvasMaxWidth) / 2, 1e-9));
      expect(placed.width, closeTo(kRevnixCanvasMaxWidth, 1e-9));
      // The design itself is laid out at 393 by (1200 / scale) design units.
      final box = tester.widget<SizedBox>(
        find.descendant(of: find.byType(Transform), matching: find.byType(SizedBox)).first,
      );
      expect(box.width, kRevnixCanvasWidth);
      expect(box.height, closeTo(1200 / scale, 1e-9));
    });

    test('the canvas arithmetic', () {
      expect(revnixCanvasScale(320), 320 / 393);
      expect(revnixCanvasScale(393), 1);
      expect(revnixCanvasScale(1024), 480 / 393);
      expect(revnixCanvasScale(double.infinity), 1);
      expect(revnixCanvasDesignHeight(1000, 1), 1000);
      expect(revnixCanvasDesignHeight(600, 1), 852);
      expect(revnixCanvasDesignHeight(1200, 480 / 393), closeTo(1200 * 393 / 480, 1e-9));
      expect(revnixCanvasDesignHeight(double.infinity, 1), 852);
    });

    test('the paywall physics take no drag when the content fits', () {
      const physics = RevnixPaywallScrollPhysics();
      FixedScrollMetrics metrics(double max) => FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: max,
            pixels: 0,
            viewportDimension: 600,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          );
      expect(physics.shouldAcceptUserOffset(metrics(0)), isFalse);
      expect(physics.shouldAcceptUserOffset(metrics(252)), isTrue);
      // Layered over a bouncing parent it still refuses the drag that fits.
      final layered = physics.applyTo(const BouncingScrollPhysics());
      expect(layered.shouldAcceptUserOffset(metrics(0)), isFalse);
      expect(layered.shouldAcceptUserOffset(metrics(252)), isTrue);
    });

    testWidgets('the fallback close chip sits below the status bar', (tester) async {
      final doc = docWith([
        {'id': 't', 'type': 'text', 'text': 'Go Pro'},
      ], {'layout': 'canvas'});
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(viewPadding: EdgeInsets.only(top: 47)),
            child: RevnixPaywallBlockScreen(
              ctx: BlockRenderContext(
                doc: doc,
                packages: const [],
                onPurchase: (_) {},
                onSelect: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      final chip = tester.widget<Positioned>(
        find.ancestor(of: find.text('×'), matching: find.byType(Positioned)).first,
      );
      expect(chip.top, 14 + 47);
      expect(chip.right, 14);
    });

    testWidgets('an inset image fills its stack on both axes', (tester) async {
      final doc = docWith([
        {
          'id': 's',
          'type': 'card',
          'layout': 'stack',
          'style': {'width': 200, 'height': 300},
          'children': [
            {
              'id': 'i',
              'type': 'image',
              'url': 'https://example.invalid/hero.jpg',
              'style': {'inset': true},
            },
          ],
        },
      ]);
      await tester.pumpWidget(host(doc));
      // The image is the size of the stack it sits in, both axes. (The root
      // column stretches the card across the screen, so the stack is wider
      // than its authored 200 — the image follows whatever the stack is.)
      final stack = tester.getSize(
        find.ancestor(of: find.byType(ClipRRect), matching: find.byType(Stack)).first,
      );
      expect(stack.height, 300);
      expect(tester.getSize(find.byType(ClipRRect)), stack);
      // Decoded at twice the drawn box's physical pixels, never at full size.
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect(
        (provider as ResizeImage).width,
        revnixImageCacheWidth(stack.width, tester.view.devicePixelRatio),
      );
    });

    test('the decode width is twice the box in physical pixels, or unknown', () {
      expect(revnixImageCacheWidth(393, 3), 2358);
      expect(revnixImageCacheWidth(200, 2), 800);
      expect(revnixImageCacheWidth(double.infinity, 3), isNull);
      expect(revnixImageCacheWidth(0, 3), isNull);
    });
  });
}
