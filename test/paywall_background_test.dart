import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/src/ui/paywall_background.dart';
import 'package:revnix_flutter/src/ui/paywall_blocks.dart';

/// The screen background: the wire contract, the layer stack and the CSS
/// gradient parser.
///
/// `paywall-background-wire.json` is a byte-identical copy of the fixture the
/// other five renderers decode in their own suites — a real document the
/// dashboard published from its background library. It is the closest thing
/// this SDK has to a cross-repo contract test, and it exists because the six
/// renderers previously disagreed about the ground's key with nothing to catch
/// it.
void main() {
  const goldenGround =
      'radial-gradient(120% 85% at 50% 0%, #D6FF3F38 0%, #D6FF3F00 58%), '
      'linear-gradient(180deg, #111820 0%, #07090C 100%)';

  Object? golden() =>
      jsonDecode(File('test/paywall-background-wire.json').readAsStringSync());

  List<Gradient> parse(String css) =>
      revnixParseCssGradients(css, revnixParseColor);

  group('the wire contract', () {
    test('a real published document resolves to its gradient ground, not black', () {
      final doc = PaywallBlockDoc.parse(golden())!;
      expect(doc.background, goldenGround);
      expect(doc.background, isNot('#000000'));
    });

    test('the ground key is color', () {
      expect(revnixBackgroundGround({'color': '#0B0D10'}), '#0B0D10');
    });

    test('the legacy ground key is still accepted', () {
      expect(revnixBackgroundGround({'ground': '#0B0D10'}), '#0B0D10');
    });

    test('a plain string is the legacy ground', () {
      expect(revnixBackgroundGround('#0B0D10'), '#0B0D10');
    });

    test('an empty or absent ground is null rather than an empty paint', () {
      expect(revnixBackgroundGround({'color': ''}), isNull);
      expect(revnixBackgroundGround(<String, Object?>{}), isNull);
      expect(revnixBackgroundGround(null), isNull);
    });
  });

  group('the layer stack', () {
    test('a legacy string resolves to exactly one ground layer', () {
      final layers = revnixBackgroundLayers('#0A0B0D');
      expect(layers.ground, '#0A0B0D');
      expect(layers.image, isNull);
      expect(layers.overlay, isNull);
      expect(layers.isGroundOnly, isTrue);
    });

    test('a photo carries its fit, focal point, opacity and blur', () {
      final layers = revnixBackgroundLayers({
        'color': '#000',
        'image': {
          'url': 'https://x/y.jpg',
          'fit': 'contain',
          'focalX': 20,
          'focalY': 35,
          'opacity': 70,
          'blur': 8,
        },
      });
      final image = layers.image!;
      expect(image.url, 'https://x/y.jpg');
      expect(image.fit, RevnixBackgroundFit.contain);
      expect(image.focalX, 20);
      expect(image.focalY, 35);
      expect(image.opacity, closeTo(0.7, 0.0001));
      expect(image.blur, 8);
      expect(layers.isGroundOnly, isFalse);
    });

    test('photo defaults are cover, centred, opaque and unblurred', () {
      final image = revnixBackgroundLayers({
        'image': {'url': 'https://x/y.jpg'},
      }).image!;
      expect(image.fit, RevnixBackgroundFit.cover);
      expect(image.focalX, 50);
      expect(image.focalY, 50);
      expect(image.opacity, 1);
      expect(image.blur, isNull);
    });

    test('a centred focal point is the centre alignment, and a corner is the corner', () {
      expect(
        const RevnixBackgroundImage(url: 'x').alignment,
        Alignment.center,
      );
      expect(
        const RevnixBackgroundImage(url: 'x', focalX: 0, focalY: 0).alignment,
        Alignment.topLeft,
      );
      expect(
        const RevnixBackgroundImage(url: 'x', focalX: 100, focalY: 100).alignment,
        Alignment.bottomRight,
      );
    });

    test('layers that would draw nothing are dropped rather than emitted', () {
      // A zero-opacity photo and a urlless one are both no-ops; emitting them
      // would cost a widget that paints nothing.
      expect(revnixBackgroundLayers({'image': {'fit': 'cover'}}).image, isNull);
      expect(
        revnixBackgroundLayers({
          'image': {'url': 'https://x/y.jpg', 'opacity': 0},
        }).image,
        isNull,
      );
      expect(
        revnixBackgroundLayers({
          'overlay': {'fill': '#000', 'opacity': 0},
        }).overlay,
        isNull,
      );
    });

    test('focal point and opacity are clamped to their ranges', () {
      final image = revnixBackgroundLayers({
        'image': {
          'url': 'https://x/y.jpg',
          'focalX': -40,
          'focalY': 900,
          'opacity': 400,
        },
      }).image!;
      expect(image.focalX, 0);
      expect(image.focalY, 100);
      expect(image.opacity, 1);
    });

    test('a scrim carries its fill and opacity', () {
      final overlay = revnixBackgroundLayers({
        'overlay': {'fill': '#000000', 'opacity': 40},
      }).overlay!;
      expect(overlay.fill, '#000000');
      expect(overlay.opacity, closeTo(0.4, 0.0001));
    });
  });

  group('@bg base colour', () {
    test('a stacked gradient answers with the BOTTOM layer, not the glow on top', () {
      // In CSS the first-listed layer paints on top. The fixture stacks a
      // translucent lime glow over a near-black base; answering with the glow
      // would tint every @bg fill lime.
      expect(revnixBackgroundBaseColor(goldenGround), '#111820');
    });

    test('a single gradient answers with its first stop', () {
      expect(
        revnixBackgroundBaseColor('linear-gradient(180deg, #111820, #07090C)'),
        '#111820',
      );
      expect(
        revnixBackgroundBaseColor(
          'linear-gradient(180deg, rgba(0, 0, 0, 0.5), rgba(0, 0, 0, 1))',
        ),
        'rgba(0, 0, 0, 0.5)',
      );
    });

    test('a fully transparent stop is skipped, since it says nothing about the ground', () {
      expect(
        revnixBackgroundBaseColor('linear-gradient(180deg, #D6FF3F00 0%, #111820 100%)'),
        '#111820',
      );
    });

    test('a flat colour answers with itself, and nothing answers black', () {
      expect(revnixBackgroundBaseColor('#0A0B0D'), '#0A0B0D');
      expect(revnixBackgroundBaseColor(null), '#000000');
      expect(revnixBackgroundBaseColor('   '), '#000000');
    });
  });

  group('the CSS gradient parser', () {
    test('a flat colour is not a gradient', () {
      expect(parse('#0A0B0D'), isEmpty);
    });

    test("180deg runs straight down, the library's most common recipe", () {
      final gradients = parse('linear-gradient(180deg, #111820 0%, #07090C 100%)');
      expect(gradients, hasLength(1));
      final linear = gradients[0] as LinearGradient;
      expect(linear.begin, const Alignment(0, -1));
      expect(linear.end, const Alignment(0, 1));
      expect(linear.stops, [0.0, 1.0]);
    });

    test('135deg runs corner to corner', () {
      final linear = parse('linear-gradient(135deg, #000 0%, #fff 100%)')[0]
          as LinearGradient;
      // A diagonal lands a float-noise hair off exactly 1, so the corners are
      // asserted with a tolerance rather than by identity.
      final begin = linear.begin as Alignment;
      final end = linear.end as Alignment;
      expect(begin.x, closeTo(-1, 0.0001));
      expect(begin.y, closeTo(-1, 0.0001));
      expect(end.x, closeTo(1, 0.0001));
      expect(end.y, closeTo(1, 0.0001));
    });

    test('a radial gradient keeps its centre and extent', () {
      final radial = parse(
        'radial-gradient(120% 85% at 50% 0%, #D6FF3F38 0%, #D6FF3F00 58%)',
      )[0] as RadialGradient;
      expect(radial.center, Alignment.topCenter);
      // CSS gives an ellipse; Flutter's RadialGradient is circular, so the
      // larger extent is used deliberately.
      expect(radial.radius, closeTo(1.2, 0.0001));
      expect(radial.stops![1], closeTo(0.58, 0.0001));
    });

    test("a stacked gradient comes back bottom first, reversing CSS's own order", () {
      // In CSS the FIRST layer paints on top. The Stack draws in sequence, so
      // the list is reversed on the way out — getting this backwards would bury
      // the glow under its own base.
      final gradients = parse(goldenGround);
      expect(gradients, hasLength(2));
      expect(gradients[0], isA<LinearGradient>());
      expect(gradients[1], isA<RadialGradient>());
    });

    test('commas inside rgba do not tear a stop in half', () {
      final linear = parse(
        'linear-gradient(180deg, rgba(0, 0, 0, 0.5) 0%, rgba(255, 255, 255, 1) 100%)',
      )[0] as LinearGradient;
      expect(linear.colors, hasLength(2));
    });

    test('stops with no position are interpolated the way CSS spaces them', () {
      final linear =
          parse('linear-gradient(180deg, #000, #888, #fff)')[0] as LinearGradient;
      expect(linear.stops, [0.0, 0.5, 1.0]);
    });

    test('a keyword direction is understood as well as an angle', () {
      final linear =
          parse('linear-gradient(to bottom, #000, #fff)')[0] as LinearGradient;
      expect(linear.end, const Alignment(0, 1));
    });

    test('a one-stop or unparseable gradient is dropped rather than half-drawn', () {
      expect(parse('linear-gradient(180deg, #000)'), isEmpty);
      expect(parse('conic-gradient(#000, #fff)'), isEmpty);
      expect(parse('linear-gradient(180deg, notacolour, alsonot)'), isEmpty);
    });
  });
}
