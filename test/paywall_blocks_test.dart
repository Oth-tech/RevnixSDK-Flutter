// Designed-paywall tests.
//
// The block document is authored by a dashboard that ships independently of
// this SDK and reaches the app over the network, so the emphasis here is the
// two guarantees an app cannot be patched into later: a document from a NEWER
// dashboard still parses AND still renders, and a tag with no data behind it
// never resolves to a price the store will not charge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  const palette = {
    'version': 1,
    'background': '#101014',
    'textColor': '#F5F7FA',
    'accent': '#6478ff',
    'accentInk': '#0B0D10',
  };

  Map<String, Object?> docWith(List<Object?> blocks, [Map<String, Object?> extra = const {}]) =>
      {...palette, ...extra, 'blocks': blocks};

  const annual = RevnixPaywallPackage(
    packageId: 'annual',
    title: 'Annual',
    priceLabel: r'$59.99',
    period: 'annual',
    amountMinor: 5999,
    currency: 'USD',
  );
  const monthly = RevnixPaywallPackage(
    packageId: 'monthly',
    title: 'Monthly',
    priceLabel: r'$9.99',
    period: 'monthly',
    amountMinor: 999,
    currency: 'USD',
  );
  const packages = [annual, monthly];

  Widget host(PaywallBlockDoc doc, {void Function(String)? onPurchase, VoidCallback? onRestore}) =>
      MaterialApp(
        home: Scaffold(
          body: RevnixPaywallBlockScreen(
            ctx: BlockRenderContext(
              doc: doc,
              packages: packages,
              selectedPackageId: 'annual',
              onPurchase: onPurchase ?? (_) {},
              onRestore: onRestore,
            ),
          ),
        ),
      );

  group('document parsing', () {
    test('parses all nine block types', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 't', 'type': 'text', 'text': 'Headline'},
          {'id': 'i', 'type': 'image', 'placeholder': 'hero'},
          {
            'id': 'l',
            'type': 'list',
            'items': [
              {'title': 'Offline downloads'},
            ],
          },
          {'id': 'p', 'type': 'products'},
          {'id': 'b', 'type': 'button', 'label': 'Continue'},
          {'id': 'k', 'type': 'links'},
          {'id': 'n', 'type': 'line'},
          {'id': 's', 'type': 'spacer', 'flex': true},
          {
            'id': 'c',
            'type': 'card',
            'layout': 'row',
            'children': [
              {'id': 'c1', 'type': 'text', 'text': 'in'},
            ],
          },
        ]),
      );
      expect(doc, isNotNull);
      expect(doc!.blocks, hasLength(9));
      expect(doc.blocks[0], isA<TextBlock>());
      expect(doc.blocks[1], isA<ImageBlock>());
      expect((doc.blocks[2] as ListBlock).items.first.title, 'Offline downloads');
      expect(doc.blocks[3], isA<ProductsBlock>());
      expect((doc.blocks[4] as ButtonBlock).label, 'Continue');
      expect(doc.blocks[5], isA<LinksBlock>());
      expect(doc.blocks[6], isA<LineBlock>());
      expect((doc.blocks[7] as SpacerBlock).flex, isTrue);
      expect((doc.blocks[8] as CardBlock).layout, 'row');
    });

    test('parses the four container layouts', () {
      for (final layout in ['column', 'row', 'stack', 'grid']) {
        final doc = PaywallBlockDoc.parse(
          docWith([
            {'id': 'c', 'type': 'card', 'layout': layout, 'children': <Object?>[]},
          ]),
        );
        expect((doc!.blocks.first as CardBlock).layout, layout);
      }
    });

    test('anything that is not a document returns null so the classic layout renders', () {
      expect(PaywallBlockDoc.parse(null), isNull);
      expect(PaywallBlockDoc.parse('blocks'), isNull);
      expect(PaywallBlockDoc.parse(42), isNull);
      expect(PaywallBlockDoc.parse(const <Object?>[]), isNull);
      expect(PaywallBlockDoc.parse(const <String, Object?>{}), isNull);
      expect(PaywallBlockDoc.parse(docWith(const [])), isNull,
          reason: 'a document with no blocks is not a design');
      expect(PaywallBlockDoc.parse({...palette, 'blocks': 'nope'}), isNull);
    });

    test('a document missing its palette still parses on defaults', () {
      // Losing one colour must not lose the design.
      final doc = PaywallBlockDoc.parse({
        'version': 1,
        'blocks': [
          {'id': 't', 'type': 'text', 'text': 'x'},
        ],
      });
      expect(doc, isNotNull);
      expect(doc!.background, '#000000');
      expect(doc.accent, '#6478ff');
    });

    test('a layered background reduces to its ground colour', () {
      final doc = PaywallBlockDoc.parse({
        'version': 1,
        'background': {
          'ground': '#0B0D10',
          'image': {'url': 'https://x/y.jpg'},
        },
        'textColor': '#fff',
        'accent': '#6478ff',
        'accentInk': '#000',
        'blocks': [
          {'id': 't', 'type': 'text', 'text': 'x'},
        ],
      });
      expect(doc!.background, '#0B0D10');
    });

    test('a malformed tree never costs the whole config', () {
      // The critical degradation: if `blocks` cannot be read, the app must
      // still get a classic paywall it can sell from — never nothing.
      final config = PaywallConfig.fromMap(const {
        'template': 'focus',
        'headline': 'Go Pro',
        'ctaLabel': 'Continue',
        'features': <Object?>[],
        'blocks': 'this is not a document',
      });
      expect(config.headline, 'Go Pro');
      expect(PaywallBlockDoc.parse(config.blocks), isNull);
    });

    test('a config without blocks parses unchanged', () {
      final config = PaywallConfig.fromMap(const {
        'template': 'minimal',
        'headline': 'Go Pro',
        'ctaLabel': 'Start',
        'features': <Object?>[],
      });
      expect(config.blocks, isNull);
      expect(config.template, 'minimal');
    });
  });

  group('an app cannot be patched, so nothing may break the screen', () {
    test('an unknown block type parses as UnknownBlock and keeps its siblings', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 'a', 'type': 'text', 'text': 'before'},
          {'id': 'x', 'type': 'hologram', 'spin': true},
          {'id': 'b', 'type': 'text', 'text': 'after'},
        ]),
      );
      expect(doc!.blocks, hasLength(3));
      expect(doc.blocks[1], isA<UnknownBlock>());
    });

    testWidgets('an unknown block type is skipped and its siblings still render', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 'a', 'type': 'text', 'text': 'before'},
          {'id': 'x', 'type': 'hologram'},
          {'id': 'b', 'type': 'text', 'text': 'after'},
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('before'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
    });

    testWidgets('an unknown container layout falls back to a column', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'c',
            'type': 'card',
            'layout': 'carousel',
            'children': [
              {'id': 'k', 'type': 'text', 'text': 'kept'},
            ],
          },
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('kept'), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
    });

    test('an unknown style field is ignored and the known ones survive', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 't',
            'type': 'text',
            'text': 'x',
            'style': {'fontSize': 22, 'teleport': 'yes', 'radius': 8},
          },
        ]),
      );
      final style = (doc!.blocks.first as TextBlock).style!;
      expect(style.fontSize, 22);
      expect(style.radius, 8);
    });

    test('a style field of an unexpected type costs only that field', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 't',
            'type': 'text',
            'text': 'x',
            'style': {'fontSize': 'huge', 'radius': 8},
          },
        ]),
      );
      final style = (doc!.blocks.first as TextBlock).style!;
      expect(style.fontSize, isNull);
      expect(style.radius, 8);
    });

    test('a malformed block parses as UnknownBlock rather than throwing', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          'not-a-block',
          {'id': 'a', 'type': 'text', 'text': 'survivor'},
        ]),
      );
      expect(doc!.blocks.first, isA<UnknownBlock>());
      expect((doc.blocks[1] as TextBlock).text, 'survivor');
    });

    testWidgets('a plan card whose package the offering does not reach is dropped', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'c',
            'type': 'card',
            'packageIndex': 7,
            'children': [
              {'id': 'k', 'type': 'text', 'text': '{price}'},
            ],
          },
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('{price}'), findsNothing);
    });
  });

  group('tag variables', () {
    test('price comes from the store, never from the design', () {
      expect(revnixResolveTags('{price}', annual, packages), r'$59.99');
      expect(revnixResolveTags('{title} — {price}', annual, packages), r'Annual — $59.99');
      expect(revnixResolveTags('every {period}', monthly, packages), 'every month');
      expect(revnixResolveTags('{price}/{period_short}', annual, packages), r'$59.99/yr');
    });

    test('a tag with no data behind it stays visible', () {
      // No period and no money: a guess would be a price the store will not
      // charge, so the tag must remain on screen instead.
      const bare = RevnixPaywallPackage(packageId: 'x', title: 'Pro', priceLabel: r'$1');
      expect(revnixResolveTags('{price_per_month}', bare, const [bare]), '{price_per_month}');
      expect(revnixResolveTags('{save_percent}', bare, const [bare]), '{save_percent}');
      expect(revnixResolveTags('{period}', bare, const [bare]), '{period}');
    });

    test('an unknown tag is left in place', () {
      expect(revnixResolveTags('{quantum_discount}', annual, packages), '{quantum_discount}');
    });

    test('saving is computed against the dearest plan', () {
      expect(revnixResolveTags('{save_percent}', annual, packages), '50%');
      // The dearest plan has nothing to beat, so its saving stays unresolved.
      expect(revnixResolveTags('{save_percent}', monthly, packages), '{save_percent}');
    });

    test('the per-month price borrows the format the store used', () {
      // $59.99/yr is $5.00 a month, and the substituted figure keeps the
      // store's own symbol and placement.
      expect(revnixResolveTags('{price_per_month}', annual, packages), r'$5');
    });

    test('currencies without a minor unit are not divided by a hundred', () {
      expect(revnixMinorUnits('JPY'), 1);
      expect(revnixMinorUnits('USD'), 100);
      expect(revnixMinorUnits('KWD'), 1000, reason: 'the Gulf currencies have three decimals');
      const yen = RevnixPaywallPackage(
        packageId: 'y',
        title: 'Year',
        priceLabel: '¥12,000',
        period: 'annual',
        amountMinor: 12000,
        currency: 'JPY',
      );
      // 12,000 yen a year is 1,000 a month — not 10.
      expect(revnixResolveTags('{price_per_month}', yen, const [yen]), contains('1,000'));
    });

    test('an unclosed brace is left alone rather than eating the rest of the copy', () {
      expect(revnixResolveTags('Save {price on this', annual, packages), 'Save {price on this');
    });

    test('text with no tags and a null package are untouched', () {
      expect(revnixResolveTags('Train smarter', annual, packages), 'Train smarter');
      expect(revnixResolveTags('{price}', null, packages), '{price}');
    });

    testWidgets('tags render inside a repeated plan card, one package each', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'c',
            'type': 'card',
            'repeat': 'packages',
            'children': [
              {'id': 'k', 'type': 'text', 'text': '{title} {price}'},
            ],
          },
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text(r'Annual $59.99'), findsOneWidget);
      expect(find.text(r'Monthly $9.99'), findsOneWidget);
    });
  });

  group('style values', () {
    test('proportional and auto values survive parsing', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 't',
            'type': 'text',
            'text': 'x',
            'style': {
              'height': '78%',
              'top': '50%',
              'left': 24,
              'marginTop': 'auto',
              'aspectRatio': '16/9',
              'basis': 250,
            },
          },
        ]),
      );
      final style = (doc!.blocks.first as TextBlock).style!;
      expect(style.height!.fraction, closeTo(0.78, 1e-9));
      expect(style.height!.px, isNull, reason: 'a percentage has no fixed pixel value');
      expect(style.top!.fraction, closeTo(0.5, 1e-9));
      expect(style.left!.px, 24);
      expect(style.marginTop!.isAuto, isTrue);
      expect(style.aspectRatio!.ratio, closeTo(16 / 9, 1e-9));
      expect(style.basis, 250);
    });

    test('per-side borders, flex, shrink and wrap parse', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 't',
            'type': 'text',
            'text': 'x',
            'style': {
              'borderTop': '2px solid @accent',
              'borderBottom': '1px solid @text/12',
              'flex': 1,
              'shrink': 0,
              'wrap': true,
              'selfAlign': 'start',
            },
          },
        ]),
      );
      final style = (doc!.blocks.first as TextBlock).style!;
      expect(style.borderTop, '2px solid @accent');
      expect(style.borderBottom, '1px solid @text/12');
      expect(style.flex, 1);
      expect(style.shrink, 0);
      expect(style.wrap, isTrue);
      expect(style.selfAlign, 'start');
    });

    test('selected style merges over the base style', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'c',
            'type': 'card',
            'repeat': 'packages',
            'style': {'radius': 16, 'fill': '#111'},
            'selectedStyle': {'fill': '@accent/12'},
            'children': <Object?>[],
          },
        ]),
      );
      final card = doc!.blocks.first as CardBlock;
      final merged = (card.style ?? const BlockStyle()).merging(card.selectedStyle);
      expect(merged.fill, '@accent/12', reason: 'the selected style wins where it sets a field');
      expect(merged.radius, 16, reason: 'and the base style survives where it does not');
    });

    test('grid track list and column count both parse', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 'g1', 'type': 'card', 'layout': 'grid', 'columns': 3, 'children': <Object?>[]},
          {
            'id': 'g2',
            'type': 'card',
            'layout': 'grid',
            'gridColumns': '1fr 60px',
            'children': <Object?>[],
          },
        ]),
      );
      expect((doc!.blocks[0] as CardBlock).columns, 3);
      expect((doc.blocks[1] as CardBlock).gridColumns, '1fr 60px');
    });
  });

  group('palette tokens', () {
    test('tokens resolve against the screen palette', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 't', 'type': 'text', 'text': 'x'},
        ]),
      )!;
      expect(revnixBlockColor('@accent', doc), const Color(0xFF6478FF));
      expect(revnixBlockColor('@text', doc), const Color(0xFFF5F7FA));
      expect(revnixBlockColor('#ff0000', doc), const Color(0xFFFF0000));
      // A gradient has no single colour; the caller keeps its own default.
      expect(revnixBlockColor('linear-gradient(180deg,#000,#fff)', doc), isNull);
      expect(revnixBlockColor('@nonsense', doc), isNull);
      expect(revnixBlockColor(null, doc), isNull);
    });

    test('css rgba hex is reordered to flutter argb', () {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 't', 'type': 'text', 'text': 'x'},
        ]),
      )!;
      // #RRGGBBAA in CSS, 0xAARRGGBB in Flutter — getting this backwards
      // paints the alpha as red.
      expect(revnixBlockColor('#ff000080', doc), const Color(0x80FF0000));
    });
  });

  group('rendering', () {
    testWidgets('a flow document renders its blocks in order', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 't', 'type': 'text', 'text': 'Go Pro'},
          {'id': 'b', 'type': 'button', 'label': 'Continue'},
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('Go Pro'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('a canvas document lays out at the design size', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 't', 'type': 'text', 'text': 'Designed'},
        ], {'layout': 'canvas'}),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('Designed'), findsOneWidget);
      final box = tester.widget<SizedBox>(
        find.descendant(of: find.byType(Transform), matching: find.byType(SizedBox)).first,
      );
      expect(box.width, kRevnixCanvasWidth);
      expect(box.height, kRevnixCanvasHeight);
    });

    testWidgets('the purchase button reports the selected package', (tester) async {
      String? bought;
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 'b', 'type': 'button', 'label': 'Go'},
        ]),
      );
      await tester.pumpWidget(host(doc!, onPurchase: (id) => bought = id));
      await tester.tap(find.text('Go'));
      expect(bought, 'annual');
    });

    testWidgets('a links block calls the host handler', (tester) async {
      var restored = 0;
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 'k', 'type': 'links'},
        ]),
      );
      await tester.pumpWidget(host(doc!, onRestore: () => restored += 1));
      await tester.tap(find.text('Restore'));
      expect(restored, 1);
    });

    testWidgets('a links block with everything switched off renders nothing', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'k',
            'type': 'links',
            'showRestore': false,
            'showTerms': false,
            'showPrivacy': false,
          },
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('Restore'), findsNothing);
      expect(find.text('Terms'), findsNothing);
    });

    testWidgets('a products block renders one card per package', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {'id': 'p', 'type': 'products'},
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('Annual'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text(r'$59.99'), findsOneWidget);
    });

    testWidgets('a list block renders its items with icons', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'l',
            'type': 'list',
            'items': [
              {'title': 'Offline downloads', 'description': 'Take it with you'},
              {'icon': '★', 'title': 'Priority support'},
            ],
          },
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('Offline downloads'), findsOneWidget);
      expect(find.text('Take it with you'), findsOneWidget);
      expect(find.text('★'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
    });

    testWidgets('a deeply nested tree renders to full depth', (tester) async {
      final doc = PaywallBlockDoc.parse(
        docWith([
          {
            'id': 'a',
            'type': 'card',
            'children': [
              {
                'id': 'b',
                'type': 'card',
                'layout': 'row',
                'children': [
                  {
                    'id': 'c',
                    'type': 'card',
                    'layout': 'stack',
                    'children': [
                      {'id': 'd', 'type': 'text', 'text': 'deep'},
                    ],
                  },
                ],
              },
            ],
          },
        ]),
      );
      await tester.pumpWidget(host(doc!));
      expect(find.text('deep'), findsOneWidget);
    });
  });
}
