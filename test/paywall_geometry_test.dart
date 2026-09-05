import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';
import 'package:revnix_flutter/src/ui/paywall_geometry.dart';

void main() {
  group('revnixParseLength', () {
    test('reads a percentage as a fraction', () {
      expect(revnixParseLength('50%'), const RevnixLength(fraction: 0.5));
      expect(revnixParseLength('-50%'), const RevnixLength(fraction: -0.5));
    });

    test('reads px and a bare zero as points', () {
      expect(revnixParseLength('16px'), const RevnixLength(points: 16));
      expect(revnixParseLength('-8px'), const RevnixLength(points: -8));
      expect(revnixParseLength('0'), const RevnixLength());
    });

    test('reads the single-operator calc form as both halves', () {
      expect(
        revnixParseLength('calc(100% - 16px)'),
        const RevnixLength(fraction: 1, points: -16),
      );
      expect(
        revnixParseLength('calc(50% + 4px)'),
        const RevnixLength(fraction: 0.5, points: 4),
      );
    });

    test('declines what it cannot read rather than guessing a number', () {
      expect(revnixParseLength('var(--pad)'), isNull);
      expect(revnixParseLength('3rem'), isNull);
      expect(revnixParseLength(''), isNull);
      expect(revnixParseLength('calc(100% - var(--x))'), isNull);
    });
  });

  group('revnixParseTranslate', () {
    test('reads the pinned-badge idiom the templates write', () {
      final t = revnixParseTranslate('-50% 0');
      expect(t, isNotNull);
      expect(t!.x, const RevnixLength(fraction: -0.5));
      expect(t.y, const RevnixLength());
      expect(t.isAbsolute, isFalse);
    });

    test('a single token means x only, as CSS reads it', () {
      final t = revnixParseTranslate('-50%');
      expect(t!.x, const RevnixLength(fraction: -0.5));
      expect(t.y, const RevnixLength());
    });

    test('reads a points-only translate as absolute', () {
      final t = revnixParseTranslate('0 -8px');
      expect(t!.y, const RevnixLength(points: -8));
      expect(t.isAbsolute, isTrue);
    });

    test('declines a half-readable value rather than moving a block halfway',
        () {
      expect(revnixParseTranslate('-50% var(--y)'), isNull);
      expect(revnixParseTranslate('1px 2px 3px'), isNull);
      expect(revnixParseTranslate(null), isNull);
      expect(revnixParseTranslate(''), isNull);
    });
  });

  group('revnixFillSizeTiles', () {
    test('a sized copy is not a tile', () {
      expect(revnixFillSizeTiles('cover'), isFalse);
      expect(revnixFillSizeTiles('contain'), isFalse);
      expect(revnixFillSizeTiles('100% 100%'), isFalse);
      expect(revnixFillSizeTiles(null), isFalse);
      expect(revnixFillSizeTiles(''), isFalse);
    });

    test('a fixed size is the repeating wash this renderer cannot paint', () {
      expect(revnixFillSizeTiles('24px 24px'), isTrue);
      expect(revnixFillSizeTiles('8px 8px'), isTrue);
    });
  });

  group('rendering', () {
    final diagnostics = <String>[];

    Widget host(Map<String, Object?> style) {
      diagnostics.clear();
      final doc = PaywallBlockDoc.parse({
        'version': 1,
        'background': '#101014',
        'textColor': '#F5F7FA',
        'accent': '#6478ff',
        'accentInk': '#0B0D10',
        'blocks': [
          {'id': 'b1', 'type': 'text', 'text': 'SAVE 60%', 'style': style},
        ],
      });
      return MaterialApp(
        home: Scaffold(
          body: RevnixPaywallBlockScreen(
            ctx: BlockRenderContext(
              doc: doc!,
              packages: const [],
              onPurchase: (_) {},
              onSelect: (_) {},
              onDiagnostic: diagnostics.add,
            ),
          ),
        ),
      );
    }

    testWidgets('a percentage translate pulls the block back by its own size',
        (tester) async {
      // The pinned-badge idiom: `left: 50%` puts the chip's LEFT EDGE at the
      // middle, and this is the half that re-centres it. Without it the badge
      // sat half its own width to the right — on Flutter only.
      await tester.pumpWidget(host({
        'top': -9,
        'left': '50%',
        'translate': '-50% 0',
        'fill': '@accent',
        'fontSize': 10.0,
      }));
      final t = tester.widgetList<FractionalTranslation>(
        find.byType(FractionalTranslation),
      );
      expect(t.map((w) => w.translation), contains(const Offset(-0.5, 0)));
      expect(diagnostics, isEmpty);
    });

    testWidgets('a points translate moves the block without measuring it',
        (tester) async {
      await tester.pumpWidget(host({'translate': '0 -8px', 'fontSize': 10.0}));
      final t = tester.widgetList<Transform>(find.byType(Transform));
      expect(
        t.any((w) => w.transform.getTranslation().y == -8),
        isTrue,
        reason: 'expected a Transform carrying the -8px y offset',
      );
    });

    testWidgets('what this renderer cannot draw is reported, not swallowed',
        (tester) async {
      await tester.pumpWidget(host({
        'clipPath': 'polygon(50% 0, 100% 100%, 0 100%)',
        'fill': 'repeating-linear-gradient(45deg, #fff 0 2px, #000 2px 4px)',
        'fillSize': '24px 24px',
        'filter': 'blur(12px)',
        'textWrap': 'balance',
        'fontSize': 10.0,
      }));
      expect(diagnostics, contains(startsWith('clipPath not drawn:')));
      expect(diagnostics, contains(startsWith('fillSize not tiled:')));
      expect(diagnostics, contains(startsWith('filter not drawn:')));
      // textWrap is decoded but deliberately not reported — it moves a line
      // break, not the design, and half the gallery sets it.
      expect(
        diagnostics.any((d) => d.contains('textWrap')),
        isFalse,
        reason: 'textWrap must not add noise to the diagnostics stream',
      );
    });

    testWidgets('an unreadable translate leaves the block put and says so',
        (tester) async {
      await tester.pumpWidget(host({'translate': 'var(--x)', 'fontSize': 10.0}));
      expect(diagnostics, contains(startsWith('translate not applied:')));
    });
  });
}
