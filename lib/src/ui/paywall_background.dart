// The paywall screen background — the Flutter half of the dashboard's model.
//
// A background is either the original CSS string (a colour or a gradient) or
// a layered spec: a ground colour/gradient, then a photo (fit, focal point,
// opacity, blur), then a scrim. [revnixBackgroundLayers] resolves either form
// to one paint list, mirroring revnix-app/src/lib/paywall-blocks/background.ts
// and the React SDK's blocks/background.ts — the same names, the same
// defaults, the same clamping — so a background cannot look different on
// device than in the builder for reasons of interpretation.
//
// Two things this file exists to get right:
//
//  1. The ground field on the wire is `color`. It is NOT `ground` — that is
//     the name of the RESOLVED layer, and decoding it off the wire is what
//     rendered every edited paywall pure black. `ground` stays accepted so a
//     document published by a build that wrote it still opens.
//
//  2. Most shipped library backgrounds are CSS gradients. A parser that only
//     understands `#rrggbb` treats them as unparseable and falls back to
//     black, so the gradient forms the dashboard actually emits are parsed
//     here into real Flutter gradients.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How a background photo fills the screen.
enum RevnixBackgroundFit { cover, contain }

/// The photo layer.
@immutable
class RevnixBackgroundImage {
  const RevnixBackgroundImage({
    required this.url,
    this.fit = RevnixBackgroundFit.cover,
    this.focalX = 50,
    this.focalY = 50,
    this.opacity = 1.0,
    this.blur,
  });

  /// An https URL the device can load.
  final String url;
  final RevnixBackgroundFit fit;

  /// Focal point in percent (0-100, 50/50 = centred): the part of the photo
  /// that must survive a cover-crop.
  final double focalX;
  final double focalY;

  /// 0-1.
  final double opacity;

  /// Blur radius in px; null when no blur was asked for.
  final double? blur;

  /// The focal point as an [Alignment], which is exactly how CSS
  /// `object-position: X% Y%` behaves for a cover fit: the X% point of the
  /// image is aligned to the X% point of the box, clamped at the edges.
  Alignment get alignment =>
      Alignment((focalX / 50) - 1, (focalY / 50) - 1);
}

/// The scrim painted over the photo.
@immutable
class RevnixBackgroundOverlay {
  const RevnixBackgroundOverlay({required this.fill, this.opacity = 1.0});

  /// Any colour or gradient string.
  final String fill;

  /// 0-1.
  final double opacity;
}

/// The resolved paint list, bottom layer first.
@immutable
class RevnixBackgroundLayers {
  const RevnixBackgroundLayers({this.ground, this.image, this.overlay});

  /// The ground fill (a colour or gradient string), or null for none.
  final String? ground;
  final RevnixBackgroundImage? image;
  final RevnixBackgroundOverlay? overlay;

  /// True when the background paints nothing but a ground — the shape every
  /// unedited paywall has, and the one that needs no extra layers at all.
  bool get isGroundOnly => image == null && overlay == null;
}

/// 0-100 (or absent) -> 0-1, clamped.
double _pct(Object? value, double fallback) {
  if (value is! num || !value.isFinite) return fallback;
  return (value / 100).clamp(0.0, 1.0);
}

/// 0-100 (or absent) -> a clamped percentage.
double _coord(Object? value) {
  if (value is! num || !value.isFinite) return 50;
  return value.toDouble().clamp(0.0, 100.0);
}

String? _str(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// The ground paint of a background: `color`, or the legacy `ground`.
String? revnixBackgroundGround(Object? background) {
  if (background is String) return background.isEmpty ? null : background;
  if (background is Map) {
    return _str(background['color']) ?? _str(background['ground']);
  }
  return null;
}

/// The paint list for a background: ground, then photo, then scrim. Layers
/// that would draw nothing (no url, zero opacity) are dropped, so a legacy
/// string resolves to exactly one ground layer.
RevnixBackgroundLayers revnixBackgroundLayers(
  Object? background, {
  /// Resolves palette tokens in the ground and overlay fills.
  String Function(String)? resolve,
}) {
  final r = resolve ?? (String v) => v;
  final ground = revnixBackgroundGround(background);
  if (background is! Map) {
    return RevnixBackgroundLayers(ground: ground == null ? null : r(ground));
  }

  RevnixBackgroundImage? image;
  final rawImage = background['image'];
  if (rawImage is Map) {
    final url = _str(rawImage['url']);
    final opacity = _pct(rawImage['opacity'], 1);
    if (url != null && opacity > 0) {
      final blur = rawImage['blur'];
      image = RevnixBackgroundImage(
        url: url,
        fit: rawImage['fit'] == 'contain'
            ? RevnixBackgroundFit.contain
            : RevnixBackgroundFit.cover,
        focalX: _coord(rawImage['focalX']),
        focalY: _coord(rawImage['focalY']),
        opacity: opacity,
        blur: blur is num && blur > 0 ? blur.toDouble() : null,
      );
    }
  }

  RevnixBackgroundOverlay? overlay;
  final rawOverlay = background['overlay'];
  if (rawOverlay is Map) {
    final fill = _str(rawOverlay['fill']);
    final opacity = _pct(rawOverlay['opacity'], 1);
    if (fill != null && opacity > 0) {
      overlay = RevnixBackgroundOverlay(fill: r(fill), opacity: opacity);
    }
  }

  return RevnixBackgroundLayers(
    ground: ground == null ? null : r(ground),
    image: image,
    overlay: overlay,
  );
}

// ——— CSS gradients ———

/// Splits on top-level commas only, so the commas inside `rgba(...)` and
/// inside a nested gradient's argument list do not tear an argument in half.
List<String> _splitTopLevel(String input) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      if (depth > 0) depth--;
    } else if (c == ',' && depth == 0) {
      out.add(input.substring(start, i).trim());
      start = i + 1;
    }
  }
  final tail = input.substring(start).trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

/// A colour stop: the colour, plus its position in 0-1 when one was given.
class _Stop {
  _Stop(this.color, this.position);
  final Color color;
  final double? position;
}

/// One argument of a gradient's stop list, as the stop(s) it stands for.
///
/// The positions are the trailing `<n>%` (or a unitless `0`); everything before
/// them is the colour, which may itself contain spaces (`rgba(0, 0, 0, 0.5)`).
/// CSS allows TWO positions on one stop — `@accent 0 22%` is the same colour at
/// both, the hard edge the library's progress bars and split panels are drawn
/// with — so this answers with a list rather than a single stop.
List<_Stop> _parseStops(String raw, Color? Function(String) parseColor) {
  var body = raw.trim();
  if (body.isEmpty) return const [];
  final positions = <double>[];
  final pattern = RegExp(r'\s(-?[\d.]+%|0)\s*$');
  while (positions.length < 2) {
    final match = pattern.firstMatch(body);
    if (match == null) break;
    final text = match.group(1)!;
    final isPercent = text.endsWith('%');
    final value =
        double.tryParse(isPercent ? text.substring(0, text.length - 1) : text);
    // The token comes off `body` either way. Leaving a position this build
    // could not read attached to the colour made the colour unparseable too,
    // which dropped the whole stop — and a gradient left with one stop does not
    // parse at all. A malformed position is worth losing; the stop is not.
    body = body.substring(0, match.start).trim();
    if (value == null) break;
    positions.insert(0, (isPercent ? value / 100 : value).clamp(0.0, 1.0));
  }
  if (body.isEmpty) return const [];
  final color = parseColor(body);
  if (color == null) return const [];
  if (positions.isEmpty) return [_Stop(color, null)];
  return [for (final position in positions) _Stop(color, position)];
}

/// Fills in the positions CSS would interpolate for stops that gave none.
List<double> _stopPositions(List<_Stop> stops) {
  final out = List<double?>.generate(stops.length, (i) => stops[i].position);
  if (out.first == null) out[0] = 0;
  if (out.last == null) out[out.length - 1] = 1;
  for (var i = 1; i < out.length - 1; i++) {
    if (out[i] != null) continue;
    var next = i + 1;
    while (next < out.length && out[next] == null) {
      next++;
    }
    final from = out[i - 1]!;
    final to = out[next]!;
    final span = next - (i - 1);
    for (var k = i; k < next; k++) {
      out[k] = from + (to - from) * ((k - (i - 1)) / span);
    }
  }
  // Gradient stops must be non-decreasing or Flutter asserts.
  var previous = 0.0;
  return out.map((v) {
    final value = (v ?? previous).clamp(0.0, 1.0);
    final result = value < previous ? previous : value;
    previous = result;
    return result;
  }).toList();
}

/// CSS angle -> the begin/end alignments of a Flutter [LinearGradient].
///
/// CSS measures clockwise from "to top", so the gradient runs along
/// `(sin a, -cos a)` in screen coordinates. Scaling that unit vector so its
/// largest component reaches the box edge is what makes 135deg run corner to
/// corner the way CSS draws it.
(Alignment, Alignment) _linearAlignments(double degrees) {
  final radians = degrees * math.pi / 180;
  var dx = math.sin(radians);
  var dy = -math.cos(radians);
  final longest = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
  if (longest > 0.0001) {
    dx /= longest;
    dy /= longest;
  }
  // sin(pi) is 1.2e-16, not 0, so an axis-aligned gradient carries a hair of
  // the other axis that only PRINTS as -0.0. Harmless on screen, but it makes
  // the alignment compare unequal to the constant it should be, so it is
  // snapped.
  double z(double v) => v.abs() < 1e-9 ? 0.0 : v;
  return (
    Alignment(z(-dx), z(-dy)),
    Alignment(z(dx), z(dy)),
  );
}

/// Parses the gradient forms the dashboard emits — `linear-gradient(Ndeg,
/// ...)` and `radial-gradient(RX% RY% at X% Y%, ...)` — plus the
/// comma-separated stacks of them the library's Spotlight and Corner halo
/// presets use.
///
/// Returns the layers BOTTOM FIRST, which is the reverse of CSS's own order
/// (in CSS the first-listed layer paints on top), so the result can be
/// dropped straight into a [Stack].
List<Gradient> revnixParseCssGradients(
  String css,
  Color? Function(String) parseColor,
) {
  final layers = <Gradient>[];
  for (final part in _splitTopLevel(css)) {
    final gradient = _parseOneGradient(part, parseColor);
    if (gradient != null) layers.add(gradient);
  }
  return layers.reversed.toList();
}

Gradient? _parseOneGradient(String raw, Color? Function(String) parseColor) {
  final s = raw.trim();
  final open = s.indexOf('(');
  if (open < 0 || !s.endsWith(')')) return null;
  final name = s.substring(0, open).trim().toLowerCase();
  final args = _splitTopLevel(s.substring(open + 1, s.length - 1));
  if (args.isEmpty) return null;

  if (name == 'linear-gradient') {
    var angle = 180.0;
    var first = 0;
    final head = args.first.trim().toLowerCase();
    final deg = RegExp(r'^(-?[\d.]+)deg$').firstMatch(head);
    if (deg != null) {
      angle = double.tryParse(deg.group(1)!) ?? 180;
      first = 1;
    } else if (head.startsWith('to ')) {
      angle = _angleForKeyword(head.substring(3).trim()) ?? 180;
      first = 1;
    }
    final stops = <_Stop>[];
    for (var i = first; i < args.length; i++) {
      stops.addAll(_parseStops(args[i], parseColor));
    }
    if (stops.length < 2) return null;
    final (begin, end) = _linearAlignments(angle);
    return LinearGradient(
      begin: begin,
      end: end,
      colors: stops.map((s) => s.color).toList(),
      stops: _stopPositions(stops),
    );
  }

  if (name == 'radial-gradient') {
    var centre = Alignment.center;
    // Flutter's radius is a fraction of the SHORTEST side and always circular,
    // where CSS gives an ellipse with independent x/y extents. Taking the
    // larger extent keeps a glow from stopping short of the edge it was drawn
    // to reach; the shape is an approximation, deliberately.
    var radius = 0.5;
    var first = 0;
    final head = args.first.trim();
    final shape = RegExp(
      r'^([\d.]+)%\s+([\d.]+)%(?:\s+at\s+([\d.]+)%\s+([\d.]+)%)?$',
      caseSensitive: false,
    ).firstMatch(head);
    final atOnly = RegExp(
      r'^at\s+([\d.]+)%\s+([\d.]+)%$',
      caseSensitive: false,
    ).firstMatch(head);
    if (shape != null) {
      final rx = double.tryParse(shape.group(1)!) ?? 50;
      final ry = double.tryParse(shape.group(2)!) ?? 50;
      radius = ((rx > ry ? rx : ry) / 100).clamp(0.05, 4.0);
      final cx = double.tryParse(shape.group(3) ?? '50') ?? 50;
      final cy = double.tryParse(shape.group(4) ?? '50') ?? 50;
      centre = Alignment((cx / 50) - 1, (cy / 50) - 1);
      first = 1;
    } else if (atOnly != null) {
      final cx = double.tryParse(atOnly.group(1)!) ?? 50;
      final cy = double.tryParse(atOnly.group(2)!) ?? 50;
      centre = Alignment((cx / 50) - 1, (cy / 50) - 1);
      first = 1;
    }
    final stops = <_Stop>[];
    for (var i = first; i < args.length; i++) {
      stops.addAll(_parseStops(args[i], parseColor));
    }
    if (stops.length < 2) return null;
    return RadialGradient(
      center: centre,
      radius: radius,
      colors: stops.map((s) => s.color).toList(),
      stops: _stopPositions(stops),
    );
  }

  return null;
}

double? _angleForKeyword(String keyword) {
  switch (keyword.replaceAll(RegExp(r'\s+'), ' ')) {
    case 'top':
      return 0;
    case 'right':
      return 90;
    case 'bottom':
      return 180;
    case 'left':
      return 270;
    case 'top right':
    case 'right top':
      return 45;
    case 'bottom right':
    case 'right bottom':
      return 135;
    case 'bottom left':
    case 'left bottom':
      return 225;
    case 'top left':
    case 'left top':
      return 315;
    default:
      return null;
  }
}

/// The flat colour a gradient ground stands in for — what paints UNDER the
/// gradient, so a form this parser does not understand still shows a colour
/// from the design rather than black.
///
/// It reads the LAST comma-separated layer, because in CSS the first-listed
/// layer paints on TOP: taking the first colour would answer with the
/// translucent accent glow the library's Spotlight and Corner halo presets
/// stack over their base, not with the base itself. Fully transparent stops
/// are skipped for the same reason.
///
/// This is ALSO what `@bg` resolves to: the dashboard feeds that token into
/// `color-mix()`, which cannot take a gradient, so it collapses a gradient ground
/// to one colour exactly as this does.
String revnixBackgroundBaseColor(String? ground) {
  final s = ground?.trim() ?? '';
  if (s.isEmpty) return '#000000';
  final bottom = _splitTopLevel(s).isEmpty ? s : _splitTopLevel(s).last;
  final colors = RegExp(r'#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)', caseSensitive: false)
      .allMatches(bottom)
      .map((m) => m.group(0)!)
      .toList();
  if (colors.isEmpty) return s;
  for (final color in colors) {
    if (!_isFullyTransparent(color)) return color;
  }
  return colors.first;
}

/// Whether a colour literal is fully transparent, without pulling in the block
/// colour parser (which lives above this file and would close a cycle). Only
/// the two forms the dashboard emits are recognised; anything else counts as
/// opaque, which is the safe answer for picking a ground.
/// Whether a paint string's BOTTOM layer is a repeating pattern.
///
/// A `repeating-*` gradient is a TEXTURE, and the colours inside it are stripe
/// colours rather than the surface's. When a build cannot draw one, painting a
/// colour lifted out of its arguments across the whole box is a WRONG answer
/// rather than a degraded one — the library's `repeating-linear-gradient(180deg,
/// #0E1B21 0 1px, @bg 1px 26px)` is a hairline every 26px, and its first colour
/// as a solid fill is a slab. Such a fill paints nothing instead.
///
/// The bottom layer is the one that decides, so a pattern stacked over a real
/// ground (`repeating-…(…), #FBF3E4`) still falls back to that ground.
bool revnixIsRepeatingPattern(String? css) {
  final s = css?.trim() ?? '';
  if (s.isEmpty) return false;
  final layers = _splitTopLevel(s);
  final bottom = layers.isEmpty ? s : layers.last;
  return bottom.toLowerCase().startsWith('repeating-');
}

bool _isFullyTransparent(String color) {
  if (color.trim().toLowerCase() == 'transparent') return true;
  final s = color.trim();
  if (s.startsWith('#')) {
    final hex = s.substring(1);
    if (hex.length == 8) return int.tryParse(hex.substring(6), radix: 16) == 0;
    if (hex.length == 4) return int.tryParse(hex.substring(3), radix: 16) == 0;
    return false;
  }
  final open = s.indexOf('(');
  final close = s.indexOf(')');
  if (open < 0 || close < 0) return false;
  final parts = s
      .substring(open + 1, close)
      .split(RegExp(r'[,/\s]+'))
      .where((p) => p.trim().isNotEmpty)
      .toList();
  if (parts.length < 4) return false;
  return double.tryParse(parts[3]) == 0;
}
