// Block fills: the half of a paint string that is NOT a plain colour.
//
// A `fill` is handed straight to CSS `background` by the dashboard, so it may
// be a colour, a gradient, or a stack of them. This SDK parsed only the first
// form and painted nothing for the others — 113 of the 250 shipped gallery
// presets use a gradient somewhere, so "nothing" was the common case.
//
// Three separate defects are pinned here, because each of them alone was
// enough to lose a gradient:
//
//   1. the fill was never routed through the gradient parser at all;
//   2. `@bg` resolved to the RAW ground, so a `@bg` stop inside a gradient
//      failed to parse and was dropped — and a gradient left with one stop
//      does not parse either, taking the whole fill with it;
//   3. a stop may carry TWO positions (`@accent 0 22%`), and reading only the
//      last one turned every hard edge in the library into a smooth fade.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/src/ui/paywall_background.dart';
import 'package:revnix_flutter/src/ui/paywall_blocks.dart';

void main() {
  PaywallBlockDoc doc({String background = '#101014'}) => PaywallBlockDoc.parse({
        'version': 1,
        'background': background,
        'textColor': '#F5F7FA',
        'accent': '#6478ff',
        'accentInk': '#0B0D10',
        'blocks': [
          {'id': 't', 'type': 'text', 'text': 'Hello'},
        ],
      })!;

  List<Gradient> parse(String css, PaywallBlockDoc d) =>
      revnixParseCssGradients(css, (v) => revnixBlockColor(v, d));

  group('resolving a fill', () {
    test('a plain colour fill stays a plain colour', () {
      final fill = revnixBlockFill('#FF0000', doc());
      expect(fill.color, const Color(0xFFFF0000));
      expect(fill.gradients, isEmpty);
    });

    test('an absent fill paints nothing', () {
      expect(revnixBlockFill(null, doc()).isNone, isTrue);
      expect(revnixBlockFill('   ', doc()).isNone, isTrue);
    });

    test('a gradient fill resolves to its layers and nothing under them', () {
      final fill =
          revnixBlockFill('linear-gradient(135deg, #112233 0%, #445566 100%)', doc());
      expect(fill.gradients, hasLength(1));
      expect(fill.color, isNull);
    });

    test('a translucent scrim is not backed by an opaque box', () {
      // 83 of the library's 139 gradient fills fade through a translucent stop:
      // they are drawn OVER the screen's photo so it shows through. A flat base
      // under them would make every one of those a solid block.
      final fill = revnixBlockFill(
        'linear-gradient(180deg, rgba(15,16,19,0.72) 0%, rgba(15,16,19,0.1) 32%, #0F1013 100%)',
        doc(),
      );
      expect(fill.gradients, hasLength(1));
      expect(fill.color, isNull);
    });

    test('a unitless position is read rather than swallowing the stop', () {
      // CSS allows a unitless zero. The old parser required a `%`, so the whole
      // "#112233 0" argument was taken as the COLOUR, failed to parse, and the
      // stop was dropped — and a gradient left with one stop does not parse at
      // all, so the fill was lost outright.
      final layers = parse('linear-gradient(180deg, #112233 0, #445566 100%)', doc());
      expect(layers, hasLength(1));
      final gradient = layers.single as LinearGradient;
      expect(gradient.colors, hasLength(2));
      expect(gradient.stops!.first, 0.0);
    });

    test('a malformed position costs the position, not the stop', () {
      final layers = parse('linear-gradient(180deg, #112233 1.2.3%, #445566 100%)', doc());
      expect(layers, hasLength(1));
      expect((layers.single as LinearGradient).colors, hasLength(2));
    });

    test('a repeating pattern paints nothing rather than a stripe colour', () {
      // The colours inside a pattern are STRIPE colours. The library's hairline
      // grid is `#0E1B21` once every 26px; as a solid fill it is a slab, which
      // is a wrong answer rather than a degraded one.
      final reported = <String>[];
      final fill = revnixBlockFill(
        'repeating-linear-gradient(180deg, #0E1B21 0 1px, @bg 1px 26px)',
        doc(),
        onDiagnostic: reported.add,
      );
      expect(fill.isNone, isTrue);
      expect(reported, hasLength(1));
    });

    test('a pattern stacked over a ground still falls back to that ground', () {
      // The BOTTOM layer decides: here it is a plain colour, and a plain colour
      // is exactly the surface colour the box should take.
      final fill = revnixBlockFill(
        'repeating-linear-gradient(180deg, transparent 0 33px, #E2D2B6 33px 34px), #FBF3E4',
        doc(),
      );
      expect(fill.color, const Color(0xFFFBF3E4));
    });

    test('a token stop with zero alpha is not chosen as the base', () {
      // `@accent/0` is transparent, but only once resolved — judging the source
      // text alone called it opaque and answered a border with an invisible
      // colour.
      expect(
        revnixBlockStrokeColor(
          'linear-gradient(180deg, @accent/0 0%, @accent/22 50%, @accent/0 100%)',
          doc(),
        ),
        revnixBlockColor('@accent/22', doc()),
      );
    });

    test('a stacked gradient keeps every layer, bottom first', () {
      const css =
          'radial-gradient(120% 90% at 86% 4%, #FF3D7F 0%, rgba(255,61,127,0) 48%),'
          'linear-gradient(180deg, #1C1046 0%, #0E0722 100%)';
      final fill = revnixBlockFill(css, doc());
      expect(fill.gradients, hasLength(2));
      // CSS paints the FIRST-listed layer on top, so the list is reversed: the
      // linear base comes first, ready to be stacked under the glow.
      expect(fill.gradients.first, isA<LinearGradient>());
      expect(fill.gradients.last, isA<RadialGradient>());
    });

    test('the flat base is still what a colour-only field collapses to', () {
      // The base colour did not go away — it moved to the only places it is
      // correct: a field that can hold one colour, and the parse-failure
      // fallback. Both read the BOTTOM layer's first opaque stop.
      const css =
          'radial-gradient(120% 90% at 86% 4%, #FF3D7F 0%, rgba(255,61,127,0) 48%),'
          'linear-gradient(180deg, #1C1046 0%, #0E0722 100%)';
      expect(revnixBlockStrokeColor(css, doc()), const Color(0xFF1C1046));
    });

    test('an unreadable fill falls back to a design colour and reports', () {
      final reported = <String>[];
      final fill = revnixBlockFill(
        'repeating-linear-gradient(180deg, transparent 0 33px, #E2D2B6 33px 34px), #FBF3E4',
        doc(),
        onDiagnostic: reported.add,
      );
      expect(fill.color, const Color(0xFFFBF3E4));
      expect(fill.gradients, isEmpty);
      expect(reported, hasLength(1));
      expect(reported.single, contains('unreadable fill'));
    });

    test('a black screen is never the fallback', () {
      // The regression this whole ticket exists for: an unreadable fill used
      // to leave the box unpainted over a #000000 screen.
      final fill = revnixBlockFill('conic-gradient(#123456, #654321)', doc());
      expect(fill.color, const Color(0xFF123456));
      expect(fill.color, isNot(const Color(0xFF000000)));
    });
  });

  group('colour-only fields', () {
    test('a gradient collapses rather than disappearing', () {
      final reported = <String>[];
      final colour = revnixBlockStrokeColor(
        'linear-gradient(90deg, #00FF00 0%, #0000FF 100%)',
        doc(),
        onDiagnostic: reported.add,
      );
      expect(colour, const Color(0xFF00FF00));
      expect(reported.single, contains('flattened'));
    });

    test('a plain colour reports nothing', () {
      final reported = <String>[];
      expect(
        revnixBlockStrokeColor('@accent', doc(), onDiagnostic: reported.add),
        const Color(0xFF6478FF),
      );
      expect(reported, isEmpty);
    });
  });

  group('@bg over a gradient ground', () {
    test('resolves to the ground flat base, not the raw gradient', () {
      // The dashboard answers `@bg` with `backgroundBaseColor(...)` because it
      // feeds the token into color-mix(), which cannot take a gradient.
      final d = doc(background: 'linear-gradient(180deg, #231646 0%, #0C0C13 100%)');
      expect(revnixBlockColor('@bg', d), const Color(0xFF231646));
      expect(revnixBlockColor('@bg/50', d), isNotNull);
    });

    test('a @bg stop no longer takes the whole fill with it', () {
      // Before the fix `@bg` returned null, the stop was dropped, and a
      // gradient left under two stops does not parse — so a fill the design
      // wrote as three stops painted nothing at all.
      final d = doc(background: 'linear-gradient(180deg, #231646 0%, #0C0C13 100%)');
      final layers = parse('linear-gradient(180deg, rgba(12,16,19,0.5) 0%, @bg 100%)', d);
      expect(layers, hasLength(1));
      expect(layers.single.colors, hasLength(2));
    });
  });

  group('stop syntax the library actually ships', () {
    test('a stop may carry two positions, which is a hard edge', () {
      // "@accent 0 22%" is the accent at BOTH 0 and 22%, then the next colour
      // starts at 22% — the progress-bar idiom, and a hard edge rather than the
      // smooth fade that reading one position produced.
      final layers = parse('linear-gradient(90deg, @accent 0 22%, #16203C 22%)', doc());
      expect(layers, hasLength(1));
      final gradient = layers.single as LinearGradient;
      expect(gradient.colors, hasLength(3));
      expect(gradient.stops, [0.0, 0.22, 0.22]);
      expect(gradient.colors[0], const Color(0xFF6478FF));
      expect(gradient.colors[1], const Color(0xFF6478FF));
      expect(gradient.colors[2], const Color(0xFF16203C));
    });

    test('transparent is a colour the designs use', () {
      expect(revnixParseColor('transparent'), const Color(0x00000000));
      final layers = parse('linear-gradient(90deg, @accent 0 60%, transparent 60%)', doc());
      expect(layers, hasLength(1));
      expect((layers.single as LinearGradient).colors, hasLength(3));
    });

    test('a colour with spaces inside it is not torn apart', () {
      final layers = parse('linear-gradient(180deg, rgba(0, 0, 0, 0.5) 0%, #FFFFFF 100%)', doc());
      expect(layers, hasLength(1));
      expect((layers.single as LinearGradient).colors.first.a, closeTo(0.5, 0.01));
    });
  });

  group('a gradient fill on a real screen', () {
    const palette = {
      'version': 1,
      'layout': 'flow',
      'background': '#101014',
      'textColor': '#F5F7FA',
      'accent': '#6478ff',
      'accentInk': '#0B0D10',
    };

    Map<String, Object?> docWith(List<Object?> blocks) =>
        {...palette, 'blocks': blocks};

    Widget host(PaywallBlockDoc doc) => MaterialApp(
          home: Scaffold(
            body: RevnixPaywallBlockScreen(
              ctx: BlockRenderContext(
                doc: doc,
                packages: const [],
                onPurchase: (_) {},
                onSelect: (_) {},
              ),
            ),
          ),
        );

    testWidgets('a gradient-filled card paints a gradient, not a flat box',
        (tester) async {
      final doc = PaywallBlockDoc.parse(docWith([
        {
          'id': 'c',
          'type': 'card',
          'style': {
            'fill': 'linear-gradient(135deg, #112233 0%, #445566 100%)',
            'radius': 16,
            'padding': 12,
          },
          'children': [
            {'id': 'k', 'type': 'text', 'text': 'inside'},
          ],
        },
      ]))!;
      await tester.pumpWidget(host(doc));
      expect(find.text('inside'), findsOneWidget);
      // The layers are real widgets here, not a decoration, so their presence
      // is the assertion: before the fix the card had no paint at all.
      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((b) => (b.decoration as BoxDecoration).gradient is LinearGradient);
      expect(gradients, isNotEmpty);
    });

    testWidgets('the content still sits above the fill it was given',
        (tester) async {
      // A gradient is painted as siblings BEHIND the content. Getting the
      // sibling order wrong hides the text under its own background.
      final doc = PaywallBlockDoc.parse(docWith([
        {
          'id': 'c',
          'type': 'card',
          'style': {'fill': 'linear-gradient(180deg, #000000 0%, #FFFFFF 100%)'},
          'children': [
            {'id': 'k', 'type': 'text', 'text': 'on top'},
          ],
        },
      ]))!;
      await tester.pumpWidget(host(doc));
      final stack = tester.widget<Stack>(
        find.ancestor(of: find.text('on top'), matching: find.byType(Stack)).first,
      );
      expect(stack.children.last, isNot(isA<Positioned>()));
    });

    testWidgets('a gradient rule inside a row does not blow up the layout',
        (tester) async {
      // A `line` has no intrinsic width; painting its fill as a stacked layer
      // rather than a colour is where an unbounded-width crash would show.
      final doc = PaywallBlockDoc.parse(docWith([
        {
          'id': 'r',
          'type': 'card',
          'layout': 'row',
          'children': [
            {'id': 't', 'type': 'text', 'text': 'label'},
            {
              'id': 'l',
              'type': 'line',
              'style': {
                'flex': 1,
                'height': 2,
                'fill': 'linear-gradient(90deg, #6478ff 0%, #00000000 100%)',
              },
            },
          ],
        },
      ]))!;
      await tester.pumpWidget(host(doc));
      expect(tester.takeException(), isNull);
      expect(find.text('label'), findsOneWidget);
    });

    testWidgets('an unreadable fill leaves a colour from the design, never black',
        (tester) async {
      final doc = PaywallBlockDoc.parse(docWith([
        {
          'id': 'c',
          'type': 'card',
          'style': {'fill': 'conic-gradient(#123456, #654321)'},
          'children': [
            {'id': 'k', 'type': 'text', 'text': 'still here'},
          ],
        },
      ]))!;
      await tester.pumpWidget(host(doc));
      expect(tester.takeException(), isNull);
      expect(find.text('still here'), findsOneWidget);
    });
  });
}
