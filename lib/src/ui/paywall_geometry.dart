// Geometry paint strings — the block style fields whose value is a small piece
// of CSS geometry rather than a number.
//
// `translate`, `clipPath`, `fillSize`, `textWrap` and `filter` were named by no
// property on this SDK's `BlockStyle`, so `fromJson` dropped them and the
// renderer never saw them. `translate` was the one that showed: 5 of the 25
// shipped template categories pin a badge with `left: 50%` plus
// `translate: "-50% 0"`, and without the second half the chip sat half its own
// width off centre — only on Flutter, never in the dashboard preview the design
// was approved in.
//
// Parsing here is total and pure, so it is testable without a widget host: an
// unreadable value yields null and the block renders unmoved, never wrong and
// never crashed.

/// A CSS `<length-percentage>`, kept as both halves so one type covers every
/// form the designs use: `16px` is points alone, `50%` is a fraction alone, and
/// `calc(100% - 16px)` is the two together.
class RevnixLength {
  const RevnixLength({this.fraction = 0, this.points = 0});

  /// Fraction of the reference box on this axis: `50%` → 0.5.
  final double fraction;

  /// Fixed logical pixels added after the fraction: `calc(100% - 16px)` → -16.
  final double points;

  /// True when the value needs no measuring — a pure-points length can be
  /// applied without knowing the block's size.
  bool get isAbsolute => fraction == 0;

  @override
  bool operator ==(Object other) =>
      other is RevnixLength &&
      other.fraction == fraction &&
      other.points == points;

  @override
  int get hashCode => Object.hash(fraction, points);

  @override
  String toString() => 'RevnixLength(fraction: $fraction, points: $points)';
}

final RegExp _calc = RegExp(r'^calc\(\s*(.+?)\s*([+-])\s*(.+?)\s*\)$');

/// One `<length-percentage>` token: `50%`, `-8px`, a bare `0`, or the
/// `calc(<pct> ± <px>)` form. Returns null for anything else — a `var()`, an
/// unsupported unit — so the caller can decline the whole value rather than
/// move a block by a number it guessed.
RevnixLength? revnixParseLength(String token) {
  final raw = token.trim();
  if (raw.isEmpty) return null;

  // calc(100% - 16px) / calc(50% + 4px). Only the single-operator form the
  // designs actually write; nested arithmetic is declined, not approximated.
  final calc = _calc.firstMatch(raw);
  if (calc != null) {
    final left = revnixParseLength(calc.group(1)!);
    final right = revnixParseLength(calc.group(3)!);
    if (left == null || right == null) return null;
    final sign = calc.group(2) == '-' ? -1.0 : 1.0;
    return RevnixLength(
      fraction: left.fraction + sign * right.fraction,
      points: left.points + sign * right.points,
    );
  }

  if (raw.endsWith('%')) {
    final n = double.tryParse(raw.substring(0, raw.length - 1));
    return n == null ? null : RevnixLength(fraction: n / 100);
  }
  if (raw.endsWith('px')) {
    final n = double.tryParse(raw.substring(0, raw.length - 2));
    return n == null ? null : RevnixLength(points: n);
  }
  // A bare number is CSS-invalid except for zero, which the designs do write.
  final n = double.tryParse(raw);
  return n == null ? null : RevnixLength(points: n);
}

/// A parsed CSS `translate`: an x and a y, each of which may be a percentage of
/// the block's OWN size. That is what lets the designs centre a pinned badge
/// with `left: 50%` plus `translate: "-50% 0"` — the first pins the edge to the
/// middle, the second pulls the block back by half its own width.
class RevnixTranslate {
  const RevnixTranslate({required this.x, required this.y});

  final RevnixLength x;
  final RevnixLength y;

  /// True when neither axis needs the block's size to resolve.
  bool get isAbsolute => x.isAbsolute && y.isAbsolute;

  @override
  bool operator ==(Object other) =>
      other is RevnixTranslate && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'RevnixTranslate(x: $x, y: $y)';
}

/// Parses a CSS `translate` value. One token means "x only, y is zero", which
/// is how CSS reads it. Returns null when either half is unreadable, so a
/// half-understood value never moves a block halfway.
RevnixTranslate? revnixParseTranslate(String? css) {
  if (css == null) return null;
  final tokens = css.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isEmpty || tokens.length > 2) return null;
  final x = revnixParseLength(tokens.first);
  if (x == null) return null;
  if (tokens.length == 1) return RevnixTranslate(x: x, y: const RevnixLength());
  final y = revnixParseLength(tokens.last);
  if (y == null) return null;
  return RevnixTranslate(x: x, y: y);
}

/// Whether a `fillSize` asks for the fill to be TILED rather than stretched.
/// `cover` / `contain` / `100% 100%` size one copy; anything else — the `24px
/// 24px` the grid and hatch washes use — is a repeating texture this renderer
/// cannot paint, and is reported instead of being silently ignored.
bool revnixFillSizeTiles(String? css) {
  if (css == null) return false;
  final raw = css.trim().toLowerCase();
  if (raw.isEmpty) return false;
  if (raw == 'cover' || raw == 'contain' || raw == 'auto') return false;
  if (raw == '100% 100%' || raw == '100%') return false;
  return true;
}
