// The paywall block model and its Flutter renderer.
//
// A paywall built in the dashboard's block builder publishes a TREE of styled
// elements on `PaywallConfig.blocks`, and that tree takes precedence over the
// classic `template` layouts. `RevnixPaywall` renders it through
// [RevnixPaywallBlockScreen] when it is present, and falls back to the classic
// layouts when it is not — so every paywall published before the block builder
// keeps rendering exactly as it did.
//
// Mirrors revnix-app's src/lib/paywall-blocks/types.ts and its reference
// renderer src/components/paywall-blocks/BlockScreen.tsx. Keep the two in
// lockstep: they are two interpreters of the SAME document, and a field only
// one side knows is a design that ships looking different from the design that
// was approved. The container layouts map onto Flutter's own primitives:
// column → Column, row → Row, stack → Stack, grid → GridView.
//
// Two rules matter more here than in the dashboard, because a shipped app
// cannot be patched from our side:
//
//   * An unknown block type, layout or style field is SKIPPED and the rest of
//     the screen still renders. Never crash, never blank.
//   * A tag with no data behind it stays visible (`{price}` renders as
//     `{price}`) rather than resolving to something wrong — a customer must
//     never be shown a price the store will not charge.

import 'package:flutter/material.dart';

import 'revnix_paywall.dart' show RevnixPaywallPackage;

/// The device screen `canvas` designs are authored against.
const double kRevnixCanvasWidth = 393;
const double kRevnixCanvasHeight = 852;

// ——— dimensions ———

/// A length the design may write either as a number of logical pixels or as a
/// CSS string ("50%", "auto", "16/9").
///
/// Kept as both so a percentage survives parsing instead of being dropped for
/// not being a number — a rail sized at 78% of its parent is a real design,
/// and silently discarding it would collapse the box.
@immutable
class BlockDimension {
  const BlockDimension({this.px, this.text});

  final double? px;
  final String? text;

  /// The value as a fraction of the parent, when written as a percentage.
  double? get fraction {
    final raw = text;
    if (raw == null || !raw.endsWith('%')) return null;
    return double.tryParse(raw.substring(0, raw.length - 1))?.let((v) => v / 100);
  }

  bool get isAuto => text == 'auto';

  /// An aspect ratio, from either a number or a "16/9" string.
  double? get ratio {
    if (px != null) return px! > 0 ? px : null;
    final raw = text;
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0].trim());
      final h = double.tryParse(parts[1].trim());
      if (w != null && h != null && h != 0) return w / h;
    }
    return double.tryParse(raw);
  }

  static BlockDimension? from(Object? value) {
    if (value is num) return BlockDimension(px: value.toDouble());
    if (value is String) {
      if (value.endsWith('px')) {
        final n = double.tryParse(value.substring(0, value.length - 2));
        if (n != null) return BlockDimension(px: n, text: value);
      }
      return BlockDimension(text: value);
    }
    return null;
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// ——— style ———

/// Per-block visual style. Everything optional — a block renders sensibly with
/// no style at all. Sizes are logical pixels; colors are any hex/rgb string, or
/// a palette token (`@accent`, `@text`, `@bg`, `@accentInk`, optionally with an
/// alpha percentage: `@text/12`).
@immutable
class BlockStyle {
  const BlockStyle({
    this.fill,
    this.textColor,
    this.opacity,
    this.borderColor,
    this.borderWidth,
    this.borderTop,
    this.borderRight,
    this.borderBottom,
    this.borderLeft,
    this.radius,
    this.padding,
    this.paddingX,
    this.paddingY,
    this.paddingTop,
    this.paddingRight,
    this.paddingBottom,
    this.paddingLeft,
    this.margin,
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
    this.fontSize,
    this.fontWeight,
    this.fontFamily,
    this.fontStyle,
    this.align,
    this.letterSpacing,
    this.lineHeight,
    this.textTransform,
    this.decoration,
    this.nowrap,
    this.gap,
    this.height,
    this.minHeight,
    this.width,
    this.maxWidth,
    this.aspectRatio,
    this.flex,
    this.shrink,
    this.basis,
    this.wrap,
    this.justify,
    this.items,
    this.selfAlign,
    this.shadow,
    this.blur,
    this.rotate,
    this.inset,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.zIndex,
    this.overflow,
  });

  final String? fill;
  final String? textColor;

  /// 0–100, like the dashboard's opacity inputs.
  final double? opacity;
  final String? borderColor;
  final double? borderWidth;

  /// Per-side rules, as a CSS border shorthand ("1px solid @text/12").
  final String? borderTop;
  final String? borderRight;
  final String? borderBottom;
  final String? borderLeft;
  final double? radius;
  final double? padding;
  final double? paddingX;
  final double? paddingY;
  final double? paddingTop;
  final double? paddingRight;
  final double? paddingBottom;
  final double? paddingLeft;
  final double? margin;
  final BlockDimension? marginTop;
  final BlockDimension? marginRight;
  final BlockDimension? marginBottom;
  final BlockDimension? marginLeft;
  final double? fontSize;
  final double? fontWeight;

  /// A design font family name. Renders only when the host app has that font
  /// bundled; otherwise the default face is used, so copy never vanishes.
  final String? fontFamily;
  final String? fontStyle;
  final String? align;

  /// In em, like CSS. Converted against the block's font size.
  final double? letterSpacing;

  /// Unitless multiplier, like CSS.
  final double? lineHeight;
  final String? textTransform;
  final String? decoration;
  final bool? nowrap;

  /// Gap between a container's children.
  final double? gap;
  final BlockDimension? height;
  final double? minHeight;
  final BlockDimension? width;
  final BlockDimension? maxWidth;

  /// Width-to-height ratio; "16/9" strings are parsed.
  final BlockDimension? aspectRatio;

  /// flex-grow inside a row/column container.
  final double? flex;

  /// flex-shrink; 0 stops a row item from being squashed.
  final double? shrink;

  /// flex-basis in logical pixels.
  final double? basis;
  final bool? wrap;
  final String? justify;
  final String? items;
  final String? selfAlign;
  final String? shadow;
  final double? blur;
  final double? rotate;

  /// Placement inside a `stack` container. `inset` fills the stack; the
  /// individual offsets pin an edge. Ignored outside a stack.
  final bool? inset;
  final BlockDimension? top;
  final BlockDimension? right;
  final BlockDimension? bottom;
  final BlockDimension? left;
  final double? zIndex;
  final String? overflow;

  /// Merges another style over this one, field by field — how a plan card's
  /// `selectedStyle` is applied on top of its base style.
  BlockStyle merging(BlockStyle? other) {
    if (other == null) return this;
    return BlockStyle(
      fill: other.fill ?? fill,
      textColor: other.textColor ?? textColor,
      opacity: other.opacity ?? opacity,
      borderColor: other.borderColor ?? borderColor,
      borderWidth: other.borderWidth ?? borderWidth,
      borderTop: other.borderTop ?? borderTop,
      borderRight: other.borderRight ?? borderRight,
      borderBottom: other.borderBottom ?? borderBottom,
      borderLeft: other.borderLeft ?? borderLeft,
      radius: other.radius ?? radius,
      padding: other.padding ?? padding,
      paddingX: other.paddingX ?? paddingX,
      paddingY: other.paddingY ?? paddingY,
      paddingTop: other.paddingTop ?? paddingTop,
      paddingRight: other.paddingRight ?? paddingRight,
      paddingBottom: other.paddingBottom ?? paddingBottom,
      paddingLeft: other.paddingLeft ?? paddingLeft,
      margin: other.margin ?? margin,
      marginTop: other.marginTop ?? marginTop,
      marginRight: other.marginRight ?? marginRight,
      marginBottom: other.marginBottom ?? marginBottom,
      marginLeft: other.marginLeft ?? marginLeft,
      fontSize: other.fontSize ?? fontSize,
      fontWeight: other.fontWeight ?? fontWeight,
      fontFamily: other.fontFamily ?? fontFamily,
      fontStyle: other.fontStyle ?? fontStyle,
      align: other.align ?? align,
      letterSpacing: other.letterSpacing ?? letterSpacing,
      lineHeight: other.lineHeight ?? lineHeight,
      textTransform: other.textTransform ?? textTransform,
      decoration: other.decoration ?? decoration,
      nowrap: other.nowrap ?? nowrap,
      gap: other.gap ?? gap,
      height: other.height ?? height,
      minHeight: other.minHeight ?? minHeight,
      width: other.width ?? width,
      maxWidth: other.maxWidth ?? maxWidth,
      aspectRatio: other.aspectRatio ?? aspectRatio,
      flex: other.flex ?? flex,
      shrink: other.shrink ?? shrink,
      basis: other.basis ?? basis,
      wrap: other.wrap ?? wrap,
      justify: other.justify ?? justify,
      items: other.items ?? items,
      selfAlign: other.selfAlign ?? selfAlign,
      shadow: other.shadow ?? shadow,
      blur: other.blur ?? blur,
      rotate: other.rotate ?? rotate,
      inset: other.inset ?? inset,
      top: other.top ?? top,
      right: other.right ?? right,
      bottom: other.bottom ?? bottom,
      left: other.left ?? left,
      zIndex: other.zIndex ?? zIndex,
      overflow: other.overflow ?? overflow,
    );
  }

  /// Every field is read independently and only when its type matches, which
  /// is what lets a design authored against a newer dashboard render here
  /// minus the one effect this SDK does not know, rather than failing.
  static BlockStyle? from(Object? value) {
    if (value is! Map) return null;
    // `is` rather than `as`: a field whose type a newer dashboard widened must
    // cost that one field, and a Dart cast would throw and take the whole
    // design with it.
    double? d(String key) => value[key] is num ? (value[key] as num).toDouble() : null;
    String? s(String key) => value[key] is String ? value[key] as String : null;
    bool? b(String key) => value[key] is bool ? value[key] as bool : null;
    BlockDimension? dim(String key) => BlockDimension.from(value[key]);
    return BlockStyle(
      fill: s('fill'),
      textColor: s('textColor'),
      opacity: d('opacity'),
      borderColor: s('borderColor'),
      borderWidth: d('borderWidth'),
      borderTop: s('borderTop'),
      borderRight: s('borderRight'),
      borderBottom: s('borderBottom'),
      borderLeft: s('borderLeft'),
      radius: d('radius'),
      padding: d('padding'),
      paddingX: d('paddingX'),
      paddingY: d('paddingY'),
      paddingTop: d('paddingTop'),
      paddingRight: d('paddingRight'),
      paddingBottom: d('paddingBottom'),
      paddingLeft: d('paddingLeft'),
      margin: d('margin'),
      marginTop: dim('marginTop'),
      marginRight: dim('marginRight'),
      marginBottom: dim('marginBottom'),
      marginLeft: dim('marginLeft'),
      fontSize: d('fontSize'),
      fontWeight: d('fontWeight'),
      fontFamily: s('fontFamily'),
      fontStyle: s('fontStyle'),
      align: s('align'),
      letterSpacing: d('letterSpacing'),
      lineHeight: d('lineHeight'),
      textTransform: s('textTransform'),
      decoration: s('decoration'),
      nowrap: b('nowrap'),
      gap: d('gap'),
      height: dim('height'),
      minHeight: d('minHeight'),
      width: dim('width'),
      maxWidth: dim('maxWidth'),
      aspectRatio: dim('aspectRatio'),
      flex: d('flex'),
      shrink: d('shrink'),
      basis: d('basis'),
      wrap: b('wrap'),
      justify: s('justify'),
      items: s('items'),
      selfAlign: s('selfAlign'),
      shadow: s('shadow'),
      blur: d('blur'),
      rotate: d('rotate'),
      inset: b('inset'),
      top: dim('top'),
      right: dim('right'),
      bottom: dim('bottom'),
      left: dim('left'),
      zIndex: d('zIndex'),
      overflow: s('overflow'),
    );
  }
}

// ——— blocks ———

/// One entry of a [ListBlock].
@immutable
class BlockListItem {
  const BlockListItem({this.icon, required this.title, this.description});
  final String? icon;
  final String title;
  final String? description;
}

/// One node of the tree.
///
/// [UnknownBlock] is the whole point of this hierarchy having a catch-all: a
/// block type introduced after this SDK shipped parses to it and is skipped
/// when rendering, so the screen loses that one element rather than failing.
@immutable
abstract class PaywallBlock {
  const PaywallBlock({required this.id, this.style});
  final String id;
  final BlockStyle? style;
}

class TextBlock extends PaywallBlock {
  const TextBlock({required super.id, required this.text, super.style});
  final String text;
}

class ImageBlock extends PaywallBlock {
  const ImageBlock({
    required super.id,
    this.url,
    this.shape,
    this.fit,
    this.placeholder,
    super.style,
  });

  /// Empty falls back to the config's hero image, then to a blank slot.
  final String? url;
  final String? shape;
  final String? fit;
  final String? placeholder;
}

class ListBlock extends PaywallBlock {
  const ListBlock({
    required super.id,
    this.items = const [],
    this.iconColor,
    super.style,
  });
  final List<BlockListItem> items;

  /// Icon color; defaults to the screen accent.
  final String? iconColor;
}

/// Renders the attached offering's packages as selectable cards.
class ProductsBlock extends PaywallBlock {
  const ProductsBlock({
    required super.id,
    this.direction,
    this.titleTpl,
    this.priceTpl,
    this.highlightSub,
    this.badgeText,
    this.cardStyle,
    this.highlightStyle,
    super.style,
  });
  final String? direction;
  final String? titleTpl;
  final String? priceTpl;
  final String? highlightSub;
  final String? badgeText;
  final BlockStyle? cardStyle;
  final BlockStyle? highlightStyle;
}

class ButtonBlock extends PaywallBlock {
  const ButtonBlock({required super.id, required this.label, super.style});
  final String label;
}

class LinksBlock extends PaywallBlock {
  const LinksBlock({
    required super.id,
    this.showRestore,
    this.showTerms,
    this.showPrivacy,
    this.termsUrl,
    this.privacyUrl,
    super.style,
  });
  final bool? showRestore;
  final bool? showTerms;
  final bool? showPrivacy;
  final String? termsUrl;
  final String? privacyUrl;
}

class LineBlock extends PaywallBlock {
  const LineBlock({required super.id, super.style});
}

class SpacerBlock extends PaywallBlock {
  const SpacerBlock({required super.id, this.flex, super.style});

  /// Grows to push what follows to the bottom.
  final bool? flex;
}

/// The one container block. `layout` picks how children are placed: column /
/// row are flex lines, `stack` layers them (children position with style.inset
/// or the edge offsets), and `grid` is an N-column grid.
class CardBlock extends PaywallBlock {
  const CardBlock({
    required super.id,
    this.layout,
    this.repeat,
    this.selectedStyle,
    this.packageIndex,
    this.columns,
    this.gridColumns,
    this.children = const [],
    super.style,
  });
  final String? layout;

  /// Renders this container once per package in the attached offering.
  final String? repeat;

  /// Merged over `style` on the package the customer has selected.
  final BlockStyle? selectedStyle;

  /// "This card describes package N of the offering". A card whose index the
  /// offering does not reach is hidden.
  final int? packageIndex;

  /// grid only; defaults to 2.
  final int? columns;

  /// grid only — a CSS track list ("1fr 60px 66px").
  final String? gridColumns;
  final List<PaywallBlock> children;
}

/// A block type this SDK does not know. Skipped when rendering.
class UnknownBlock extends PaywallBlock {
  const UnknownBlock({super.id = ''});
}

// ——— document ———

/// The published document: screen palette plus the block tree.
///
/// Build one with [parse], which never throws: a null result means "this is
/// not a designed paywall", and the caller falls back to the classic layouts.
@immutable
class PaywallBlockDoc {
  const PaywallBlockDoc({
    required this.version,
    this.layout,
    required this.background,
    required this.textColor,
    required this.accent,
    required this.accentInk,
    this.fontFamily,
    required this.blocks,
  });

  final int version;

  /// "canvas" designs are authored against a fixed device screen and scale as
  /// a whole; "flow" designs lay out in a scrolling column.
  final String? layout;
  final String background;
  final String textColor;
  final String accent;
  final String accentInk;
  final String? fontFamily;
  final List<PaywallBlock> blocks;

  /// Turns the raw `config.blocks` into a document, or null when it is not
  /// one. Never throws — a malformed tree costs the DESIGN, and the caller
  /// still shows the classic paywall the customer can buy from.
  static PaywallBlockDoc? parse(Object? value) {
    if (value is! Map) return null;
    final raw = value['blocks'];
    if (raw is! List || raw.isEmpty) return null;
    // `background` is a plain string in the original form and an object in the
    // layered one; both reduce to the ground colour this SDK paints.
    final background = value['background'];
    String? str(Object? v) => v is String ? v : null;
    return PaywallBlockDoc(
      version: value['version'] is num ? (value['version'] as num).toInt() : 1,
      layout: str(value['layout']),
      background: background is String
          ? background
          : (background is Map ? str(background['ground']) : null) ?? '#000000',
      textColor: str(value['textColor']) ?? '#FFFFFF',
      accent: str(value['accent']) ?? '#6478ff',
      accentInk: str(value['accentInk']) ?? '#FFFFFF',
      fontFamily: str(value['fontFamily']),
      blocks: raw.map(_parseBlock).toList(),
    );
  }

  static PaywallBlock _parseBlock(Object? value) {
    if (value is! Map) return const UnknownBlock();
    // Same rule as BlockStyle.from: read with `is`, never cast, so one
    // unexpected field type cannot throw away the block or the screen.
    String? s(String key) => value[key] is String ? value[key] as String : null;
    bool? b(String key) => value[key] is bool ? value[key] as bool : null;
    int? i(String key) => value[key] is num ? (value[key] as num).toInt() : null;
    final id = s('id') ?? '';
    final style = BlockStyle.from(value['style']);
    switch (value['type']) {
      case 'text':
        return TextBlock(id: id, text: s('text') ?? '', style: style);
      case 'image':
        return ImageBlock(
          id: id,
          url: s('url'),
          shape: s('shape'),
          fit: s('fit'),
          placeholder: s('placeholder'),
          style: style,
        );
      case 'list':
        return ListBlock(
          id: id,
          items: (value['items'] as List<Object?>? ?? const [])
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => BlockListItem(
                  icon: item['icon'] is String ? item['icon']! as String : null,
                  title: item['title'] is String ? item['title']! as String : '',
                  description:
                      item['description'] is String ? item['description']! as String : null,
                ),
              )
              .toList(),
          iconColor: s('iconColor'),
          style: style,
        );
      case 'products':
        return ProductsBlock(
          id: id,
          direction: s('direction'),
          titleTpl: s('titleTpl'),
          priceTpl: s('priceTpl'),
          highlightSub: s('highlightSub'),
          badgeText: s('badgeText'),
          cardStyle: BlockStyle.from(value['cardStyle']),
          highlightStyle: BlockStyle.from(value['highlightStyle']),
          style: style,
        );
      case 'button':
        return ButtonBlock(id: id, label: s('label') ?? '', style: style);
      case 'links':
        return LinksBlock(
          id: id,
          showRestore: b('showRestore'),
          showTerms: b('showTerms'),
          showPrivacy: b('showPrivacy'),
          termsUrl: s('termsUrl'),
          privacyUrl: s('privacyUrl'),
          style: style,
        );
      case 'line':
        return LineBlock(id: id, style: style);
      case 'spacer':
        return SpacerBlock(id: id, flex: b('flex'), style: style);
      case 'card':
        return CardBlock(
          id: id,
          layout: s('layout'),
          repeat: s('repeat'),
          selectedStyle: BlockStyle.from(value['selectedStyle']),
          packageIndex: i('packageIndex'),
          columns: i('columns'),
          gridColumns: s('gridColumns'),
          children:
              (value['children'] as List<Object?>? ?? const []).map(_parseBlock).toList(),
          style: style,
        );
      default:
        // A block type from a newer dashboard. Skipped when rendering.
        return UnknownBlock(id: id);
    }
  }
}

// ——— tag variables ———

/// Renewal cycles, in months. Lifetime and one-time products have no cycle.
const Map<String, double> _months = {
  'weekly': 1 / 4.345,
  'monthly': 1,
  'two_months': 2,
  'three_months': 3,
  'six_months': 6,
  'annual': 12,
};

const Map<String, String> _periodWord = {
  'weekly': 'week',
  'monthly': 'month',
  'two_months': '2 months',
  'three_months': '3 months',
  'six_months': '6 months',
  'annual': 'year',
  'lifetime': 'lifetime',
};

const Map<String, String> _periodShort = {
  'weekly': 'wk',
  'monthly': 'mo',
  'two_months': '2mo',
  'three_months': '3mo',
  'six_months': '6mo',
  'annual': 'yr',
  'lifetime': 'once',
};

/// Currencies whose smallest unit IS the major unit — no minor unit at all.
const Set<String> _zeroDecimal = {
  'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG',
  'RWF', 'UGX', 'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
};

/// Currencies with three decimal places rather than two.
const Set<String> _threeDecimal = {'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'};

/// Minor units per major unit.
///
/// Not every currency is a hundredth: JPY and KRW have no minor unit at all, so
/// dividing by 100 would understate a price by 100×, and the Gulf currencies
/// have three. The table is ISO 4217's exponent for the exceptions; everything
/// else is the usual hundredth.
double revnixMinorUnits(String currency) {
  final code = currency.toUpperCase();
  if (_zeroDecimal.contains(code)) return 1;
  if (_threeDecimal.contains(code)) return 1000;
  return 100;
}

final RegExp _numberRun = RegExp(r'\d[\d.,\u00a0 ]*\d|\d');

/// Formats a computed amount the way the STORE formatted this package's own
/// price.
///
/// The store already localized `priceLabel` — symbol, placement, separators
/// and all — so the per-month figure is produced by substituting the number
/// inside that label rather than by reformatting from scratch. That keeps
/// "\u00a51,000" next to "\u00a512,000" instead of pairing it with a differently
/// built string, and needs no localization dependency.
String _money(double amountMinor, String currency, String? priceLabel) {
  final per = revnixMinorUnits(currency);
  final major = amountMinor / per;
  final decimals = per == 1 ? 0 : (per == 1000 ? 3 : 2);
  // A whole amount reads better without its ".00"; a fractional one keeps it.
  final whole = amountMinor % per == 0;
  final digits = whole ? 0 : decimals;

  final label = priceLabel;
  if (label != null) {
    final match = _numberRun.firstMatch(label);
    if (match != null) {
      final grouped = _group(major, digits, _separatorIn(match.group(0)!));
      return label.replaceRange(match.start, match.end, grouped);
    }
  }
  return '${major.toStringAsFixed(digits)} $currency';
}

/// The thousands separator the store used, so the substituted number groups
/// the same way.
String _separatorIn(String sample) {
  if (sample.contains(',') && sample.lastIndexOf(',') < sample.lastIndexOf('.')) return ',';
  if (sample.contains('.') && sample.lastIndexOf('.') < sample.lastIndexOf(',')) return '.';
  return sample.contains(',') ? ',' : (sample.contains(' ') ? ' ' : ',');
}

String _group(double value, int digits, String separator) {
  final fixed = value.toStringAsFixed(digits);
  final dot = fixed.indexOf('.');
  final intPart = dot < 0 ? fixed : fixed.substring(0, dot);
  final rest = dot < 0 ? '' : fixed.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(separator);
    buffer.write(intPart[i]);
  }
  return '$buffer$rest';
}

double? _perMonthMinor(RevnixPaywallPackage pkg) {
  final period = pkg.period;
  final amount = pkg.amountMinor;
  if (period == null || amount == null) return null;
  final months = _months[period];
  if (months == null || months <= 0) return null;
  return amount / months;
}

final RegExp _tagPattern = RegExp(r'\{(\w+)\}');

/// Fills a copy template from one package. [all] is the rest of the offering,
/// which `{save_percent}` needs to have something to compare against.
///
/// A tag this cannot answer from real package data is left in place, VISIBLE.
/// That is deliberate: a design that says `{price}` and renders a stale sample
/// is worse than one that visibly did not resolve.
String revnixResolveTags(
  String text,
  RevnixPaywallPackage? pkg, [
  List<RevnixPaywallPackage> all = const [],
]) {
  if (pkg == null || !text.contains('{')) return text;
  return text.replaceAllMapped(_tagPattern, (match) {
    final name = match.group(1);
    final raw = match.group(0)!;
    switch (name) {
      case 'title':
        return pkg.title;
      case 'price':
        return pkg.priceLabel;
      case 'period':
        return pkg.period == null ? raw : (_periodWord[pkg.period!] ?? raw);
      case 'period_short':
        return pkg.period == null ? raw : (_periodShort[pkg.period!] ?? raw);
      case 'price_per_month':
        final per = _perMonthMinor(pkg);
        final currency = pkg.currency;
        if (per == null || currency == null) return raw;
        return _money(per.roundToDouble(), currency, pkg.priceLabel);
      case 'save_percent':
        final mine = _perMonthMinor(pkg);
        if (mine == null || mine <= 0) return raw;
        var dearest = 0.0;
        for (final p in all) {
          final v = _perMonthMinor(p);
          if (v != null && v > dearest) dearest = v;
        }
        if (dearest <= mine) return raw;
        return '${((1 - mine / dearest) * 100).round()}%';
      default:
        // Unknown tag: leave it visible rather than guess.
        return raw;
    }
  });
}

// ——— colors ———

/// Expands a palette token (`@accent`, `@text/12`) and parses the result.
/// Returns null for anything it cannot parse — a gradient, a named colour — so
/// the caller keeps its own default rather than painting a wrong one.
Color? revnixBlockColor(String? value, PaywallBlockDoc doc) {
  var raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  var alpha = 1.0;
  if (raw.startsWith('@')) {
    final body = raw.substring(1);
    final slash = body.indexOf('/');
    final name = slash >= 0 ? body.substring(0, slash) : body;
    if (slash >= 0) {
      final pct = double.tryParse(body.substring(slash + 1));
      if (pct != null) alpha = pct.clamp(0, 100) / 100;
    }
    switch (name) {
      case 'accent':
        raw = doc.accent;
      case 'accentInk':
        raw = doc.accentInk;
      case 'bg':
        raw = doc.background;
      case 'text':
        raw = doc.textColor;
      default:
        return null;
    }
  }
  final base = revnixParseColor(raw);
  if (base == null) return null;
  if (alpha == 1.0) return base;
  return base.withValues(alpha: (base.a * alpha).clamp(0.0, 1.0));
}

/// Parses "#rgb", "#rrggbb", "#rrggbbaa", "rgb()" and "rgba()".
Color? revnixParseColor(String value) {
  final s = value.trim();
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3 || hex.length == 4) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6 && hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    if (hex.length == 6) return Color(0xFF000000 | v);
    // CSS is #rrggbbaa; Flutter wants 0xAARRGGBB.
    final rgb = (v >> 8) & 0xFFFFFF;
    final a = v & 0xFF;
    return Color((a << 24) | rgb);
  }
  if (!s.toLowerCase().startsWith('rgb')) return null;
  final open = s.indexOf('(');
  final close = s.indexOf(')');
  if (open < 0 || close < 0) return null;
  final parts = s
      .substring(open + 1, close)
      .split(RegExp(r'[,/\s]+'))
      .where((p) => p.trim().isNotEmpty)
      .map((p) => double.tryParse(p.trim()))
      .toList();
  if (parts.length < 3 || parts.take(3).any((p) => p == null)) return null;
  final a = parts.length > 3 && parts[3] != null ? parts[3]! : 1.0;
  return Color.fromRGBO(
    parts[0]!.round().clamp(0, 255),
    parts[1]!.round().clamp(0, 255),
    parts[2]!.round().clamp(0, 255),
    a.clamp(0.0, 1.0),
  );
}

// ——— rendering ———

/// Everything the tree needs that is not in the document itself.
@immutable
class BlockRenderContext {
  const BlockRenderContext({
    required this.doc,
    required this.packages,
    this.selectedPackageId,
    this.heroImageUrl,
    this.footerTermsUrl,
    this.footerPrivacyUrl,
    required this.onPurchase,
    this.onRestore,
    this.onTerms,
    this.onPrivacy,
  });

  final PaywallBlockDoc doc;
  final List<RevnixPaywallPackage> packages;

  /// The package a plan card visually emphasizes, and the one whose tags a
  /// subtree resolves against outside a `repeat`.
  final String? selectedPackageId;

  /// Fills an image block that publishes no URL of its own.
  final String? heroImageUrl;

  /// Paywall-level Terms/Privacy, used when a links block sets none.
  final String? footerTermsUrl;
  final String? footerPrivacyUrl;
  final void Function(String packageId) onPurchase;
  final VoidCallback? onRestore;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;
}

/// Renders a whole block document.
///
/// A `canvas` document is authored against a fixed 393×852 device screen and is
/// scaled as a whole, so absolute placement inside `stack` containers stays
/// true at any width; a `flow` document lays out as an ordinary column.
class RevnixPaywallBlockScreen extends StatelessWidget {
  const RevnixPaywallBlockScreen({super.key, required this.ctx});

  final BlockRenderContext ctx;

  @override
  Widget build(BuildContext context) {
    final doc = ctx.doc;
    final background = revnixBlockColor(doc.background, doc) ?? const Color(0xFF000000);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _renderList(doc.blocks, null),
    );

    if (doc.layout == 'canvas') {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : kRevnixCanvasWidth;
          final scale = width / kRevnixCanvasWidth;
          return Container(
            // The colour goes on the decoration rather than `color:` —
            // Container asserts a decoration exists whenever it clips, and a
            // canvas screen must clip to stay inside its scaled box.
            decoration: BoxDecoration(color: background),
            width: width,
            height: kRevnixCanvasHeight * scale,
            clipBehavior: Clip.hardEdge,
            child: Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: kRevnixCanvasWidth,
                  height: kRevnixCanvasHeight,
                  child: body,
                ),
              ),
            ),
          );
        },
      );
    }

    return Container(
      color: background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: body,
      ),
    );
  }

  List<Widget> _renderList(List<PaywallBlock> blocks, RevnixPaywallPackage? pkg) =>
      [for (final pair in _renderPairs(blocks, pkg)) pair.$2];

  /// Renders each child ONCE and keeps it beside the block it came from, so a
  /// container can read that block's flex/basis without rendering it twice —
  /// and so the widget list and the block list never fall out of step when a
  /// block contributes nothing.
  List<(PaywallBlock, Widget)> _renderPairs(
    List<PaywallBlock> blocks,
    RevnixPaywallPackage? pkg,
  ) {
    final out = <(PaywallBlock, Widget)>[];
    for (final block in blocks) {
      final widget = _render(block, pkg);
      if (widget != null) out.add((block, widget));
    }
    return out;
  }

  /// One block, or null when it contributes nothing.
  Widget? _render(PaywallBlock block, RevnixPaywallPackage? pkg) {
    final doc = ctx.doc;
    if (block is TextBlock) {
      return _styled(
        block.style,
        Text(
          revnixResolveTags(block.text, pkg, ctx.packages),
          textAlign: _textAlign(block.style?.align),
          maxLines: block.style?.nowrap == true ? 1 : null,
          overflow: block.style?.nowrap == true ? TextOverflow.clip : null,
          style: _textStyle(block.style),
        ),
      );
    }
    if (block is ImageBlock) return _image(block);
    if (block is ListBlock) return _list(block);
    if (block is ProductsBlock) return _products(block);
    if (block is ButtonBlock) return _button(block, pkg);
    if (block is LinksBlock) return _links(block);
    if (block is LineBlock) {
      return _styled(
        block.style,
        Container(
          height: block.style?.height?.px ?? 1,
          color: revnixBlockColor(block.style?.fill, doc) ??
              (revnixBlockColor(doc.textColor, doc) ?? const Color(0xFFFFFFFF))
                  .withValues(alpha: 0.16),
        ),
        skipDecoration: true,
      );
    }
    if (block is SpacerBlock) {
      // `flex` grows to push what follows to the bottom.
      if (block.flex == true) return const Spacer();
      return SizedBox(height: block.style?.height?.px ?? 16);
    }
    if (block is CardBlock) return _card(block, pkg);
    // An unknown block type from a newer dashboard: skip it, keep the screen.
    return null;
  }

  // ——— leaves ———

  TextStyle _textStyle(BlockStyle? style, {double defaultSize = 15, FontWeight? defaultWeight}) {
    final doc = ctx.doc;
    final size = style?.fontSize ?? defaultSize;
    return TextStyle(
      color: revnixBlockColor(style?.textColor, doc) ??
          revnixBlockColor(doc.textColor, doc) ??
          const Color(0xFFFFFFFF),
      fontSize: size,
      fontWeight: _weight(style?.fontWeight) ?? defaultWeight,
      fontStyle: style?.fontStyle == 'italic' ? FontStyle.italic : null,
      // The design's own face, when the host app bundles it. An unbundled
      // family falls back to the default face rather than rendering nothing.
      fontFamily: style?.fontFamily ?? doc.fontFamily,
      // CSS letter-spacing is em; Flutter wants logical pixels.
      letterSpacing: style?.letterSpacing == null ? null : style!.letterSpacing! * size,
      height: style?.lineHeight,
      decoration: switch (style?.decoration) {
        'underline' => TextDecoration.underline,
        'line-through' => TextDecoration.lineThrough,
        _ => null,
      },
    );
  }

  FontWeight? _weight(double? value) => switch (value) {
        null => null,
        >= 900 => FontWeight.w900,
        >= 800 => FontWeight.w800,
        >= 700 => FontWeight.w700,
        >= 600 => FontWeight.w600,
        >= 500 => FontWeight.w500,
        _ => FontWeight.w400,
      };

  TextAlign? _textAlign(String? value) => switch (value) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'left' => TextAlign.left,
        _ => null,
      };

  Widget _image(ImageBlock block) {
    final style = block.style;
    // A converted design sizes its own slot; the 160px default is only for a
    // slot dropped into a flow column, and must not fight it.
    final sized = style != null &&
        (style.inset == true ||
            style.height != null ||
            style.aspectRatio != null ||
            style.flex != null);
    final radius = block.shape == 'circle'
        ? BorderRadius.circular(9999)
        : BorderRadius.circular(sized ? 0 : 16);
    final url = (block.url != null && block.url!.isNotEmpty) ? block.url : ctx.heroImageUrl;

    Widget child = ClipRRect(
      borderRadius: radius,
      child: url == null
          ? _imageSlot(block)
          : Image.network(
              url,
              fit: block.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              // A customer asset that fails to load must not blank the screen.
              errorBuilder: (_, _, _) => _imageSlot(block),
            ),
    );
    if (!sized) child = SizedBox(height: 160, width: double.infinity, child: child);
    return _styled(style, child, skipDecoration: true);
  }

  Widget _imageSlot(ImageBlock block) {
    final label = block.placeholder;
    return Container(
      color: const Color(0x387D879B),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: label == null || label.isEmpty
          ? null
          : Opacity(
              opacity: 0.62,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: _textStyle(null, defaultSize: 10.5),
              ),
            ),
    );
  }

  Widget _list(ListBlock block) {
    final doc = ctx.doc;
    final gap = block.style?.gap ?? 8;
    final iconColor = revnixBlockColor(block.iconColor, doc) ??
        revnixBlockColor(doc.accent, doc) ??
        const Color(0xFFFFFFFF);
    final rows = <Widget>[];
    for (var i = 0; i < block.items.length; i++) {
      final item = block.items[i];
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.icon ?? '✓',
              style: _textStyle(null).copyWith(color: iconColor, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: _textStyle(null).copyWith(
                      fontWeight: item.description == null ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  if (item.description != null)
                    Opacity(
                      opacity: 0.7,
                      child: Text(item.description!, style: _textStyle(null, defaultSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _styled(
      block.style,
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  Widget _button(ButtonBlock block, RevnixPaywallPackage? pkg) {
    final doc = ctx.doc;
    final style = block.style;
    final accent = revnixBlockColor(style?.fill, doc) ?? revnixBlockColor(doc.accent, doc) ?? const Color(0xFF6478FF);
    final ink = revnixBlockColor(style?.textColor, doc) ?? revnixBlockColor(doc.accentInk, doc) ?? const Color(0xFFFFFFFF);
    final sized = style?.height?.px != null;
    return _styled(
      style,
      GestureDetector(
        onTap: () {
          final id = ctx.selectedPackageId ??
              (ctx.packages.isEmpty ? null : ctx.packages.first.packageId);
          if (id != null) ctx.onPurchase(id);
        },
        child: Container(
          height: style?.height?.px,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: sized ? 0 : 15),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(style?.radius ?? 12),
          ),
          child: Text(
            revnixResolveTags(block.label, pkg, ctx.packages),
            textAlign: TextAlign.center,
            style: _textStyle(style, defaultWeight: FontWeight.w800).copyWith(color: ink),
          ),
        ),
      ),
      skipDecoration: true,
    );
  }

  Widget? _links(LinksBlock block) {
    // An explicit host handler wins over the config URL — the app knows best
    // how to open its own legal pages; the URL is the no-handler fallback.
    final entries = <(String, VoidCallback?)>[];
    if (block.showRestore != false) entries.add(('Restore', ctx.onRestore));
    if (block.showTerms != false) entries.add(('Terms', ctx.onTerms));
    if (block.showPrivacy != false) entries.add(('Privacy', ctx.onPrivacy));
    if (entries.isEmpty) return null;
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 20));
      final (label, action) = entries[i];
      children.add(
        GestureDetector(
          onTap: action,
          child: Opacity(
            opacity: 0.65,
            child: Text(label, style: _textStyle(block.style, defaultSize: 12)),
          ),
        ),
      );
    }
    return _styled(
      block.style,
      Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
      skipDecoration: true,
    );
  }

  Widget _products(ProductsBlock block) {
    final doc = ctx.doc;
    final shown = ctx.packages;
    final highlightId = shown.any((p) => p.packageId == ctx.selectedPackageId)
        ? ctx.selectedPackageId
        : (shown.isEmpty ? null : shown.first.packageId);
    final row = block.direction == 'row';
    final gap = block.style?.gap ?? 8;
    final accent = revnixBlockColor(doc.accent, doc) ?? const Color(0xFF6478FF);

    final cards = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final pkg = shown[i];
      final hl = pkg.packageId == highlightId;
      if (i > 0) cards.add(row ? SizedBox(width: gap) : SizedBox(height: gap));
      Widget card = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hl ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: hl ? accent : const Color(0x59808080), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: row ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _withFallback(block.titleTpl ?? '{title}', pkg, pkg.title),
              style: _textStyle(null, defaultSize: 14).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              _withFallback(block.priceTpl ?? '{price}', pkg, pkg.priceLabel),
              style: _textStyle(null, defaultSize: 13),
            ),
            if (hl && block.highlightSub != null)
              Opacity(
                opacity: 0.75,
                child: Text(block.highlightSub!, style: _textStyle(null, defaultSize: 11.5)),
              ),
          ],
        ),
      );
      if (hl && block.badgeText != null) {
        card = Stack(
          clipBehavior: Clip.none,
          children: [
            card,
            Positioned(
              top: -9,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(99)),
                child: Text(
                  block.badgeText!,
                  style: _textStyle(null, defaultSize: 10).copyWith(
                    fontWeight: FontWeight.w800,
                    color: revnixBlockColor(doc.accentInk, doc) ?? const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      final styled = _styled(hl ? block.highlightStyle : block.cardStyle, card, skipDecoration: true);
      cards.add(row ? Expanded(child: styled) : styled);
    }

    return _styled(
      block.style,
      row
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: cards)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: cards),
      skipDecoration: true,
    );
  }

  /// A template that resolves to nothing useful falls back to the plain value —
  /// a card must show a title and a price even if its template names a tag this
  /// SDK does not know.
  String _withFallback(String tpl, RevnixPaywallPackage pkg, String fallback) {
    final out = revnixResolveTags(tpl, pkg, ctx.packages);
    return out.trim().isEmpty ? fallback : out;
  }

  // ——— containers ———

  /// The container. `layout` maps onto Flutter's own primitives: column →
  /// Column, row → Row, stack → Stack, grid → GridView. Any value this SDK does
  /// not know falls back to a column rather than rendering nothing.
  Widget? _card(CardBlock block, RevnixPaywallPackage? pkg) {
    if (block.repeat == 'packages') {
      // One designed card, rendered per package. With nothing attached a single
      // instance still renders, so the design stays visible.
      final list = ctx.packages.isEmpty ? <RevnixPaywallPackage?>[null] : ctx.packages;
      final selected = ctx.selectedPackageId ??
          (ctx.packages.isEmpty ? null : ctx.packages.first.packageId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final each in list)
            _container(
              block,
              each,
              each != null && each.packageId == selected
                  ? (block.style ?? const BlockStyle()).merging(block.selectedStyle)
                  : block.style,
            ),
        ],
      );
    }

    // A card that names a package the offering does not reach is dropped rather
    // than rendered with unresolved tags.
    final index = block.packageIndex;
    if (index != null && index >= ctx.packages.length) return null;
    final ctxPackage = index != null ? ctx.packages[index] : pkg;
    return _container(block, ctxPackage, block.style);
  }

  Widget _container(CardBlock block, RevnixPaywallPackage? pkg, BlockStyle? style) {
    final gap = block.style?.gap ?? 10;
    final pairs = _renderPairs(block.children, pkg);
    final children = [for (final pair in pairs) pair.$2];

    Widget body;
    switch (block.layout) {
      case 'stack':
        body = Stack(
          clipBehavior: Clip.none,
          children: [
            for (final pair in pairs) _stackChild(pair.$1.style, pair.$2),
          ],
        );
      case 'grid':
        final columns = _gridColumnCount(block);
        body = GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: 2.4,
          children: children,
        );
      case 'row':
        body = Row(
          mainAxisAlignment: _mainAxis(block.style?.justify),
          crossAxisAlignment: _crossAxis(block.style?.items),
          children: _withGaps(pairs, gap, horizontal: true),
        );
      default:
        // column, and anything unrecognized.
        body = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: _mainAxis(block.style?.justify),
          crossAxisAlignment: _crossAxis(block.style?.items, column: true),
          children: _withGaps(pairs, gap, horizontal: false),
        );
    }
    return _styled(style, body);
  }

  /// Inserts the gap and honours each child's flex/basis — a carousel card
  /// sized by basis collapses to nothing without it.
  List<Widget> _withGaps(
    List<(PaywallBlock, Widget)> pairs,
    double gap, {
    required bool horizontal,
  }) {
    final out = <Widget>[];
    for (var i = 0; i < pairs.length; i++) {
      if (i > 0) out.add(horizontal ? SizedBox(width: gap) : SizedBox(height: gap));
      final style = pairs[i].$1.style;
      final grow = style?.flex;
      final basis = style?.basis;
      var child = pairs[i].$2;
      if (basis != null && horizontal) child = SizedBox(width: basis, child: child);
      if (grow != null && grow > 0) {
        child = Expanded(flex: grow.round().clamp(1, 1000), child: child);
      } else if (style?.shrink == 0 && horizontal) {
        // shrink 0 stops a row item from being squashed.
        child = Flexible(flex: 0, fit: FlexFit.loose, child: child);
      }
      out.add(child);
    }
    return out;
  }

  /// Stack placement — `inset` fills the parent, the offsets pin an edge.
  Widget _stackChild(BlockStyle? style, Widget child) {
    if (style?.inset == true) return Positioned.fill(child: child);
    final top = style?.top?.px;
    final right = style?.right?.px;
    final bottom = style?.bottom?.px;
    final left = style?.left?.px;
    if (top == null && right == null && bottom == null && left == null) return child;
    return Positioned(top: top, right: right, bottom: bottom, left: left, child: child);
  }

  int _gridColumnCount(CardBlock block) {
    // The design's own track list wins; `columns` is the simple form.
    final tracks = block.gridColumns;
    if (tracks != null && tracks.trim().isNotEmpty) {
      return tracks.trim().split(RegExp(r'\s+')).length;
    }
    final columns = block.columns ?? 2;
    return columns < 1 ? 1 : columns;
  }

  MainAxisAlignment _mainAxis(String? value) => switch (value) {
        'center' => MainAxisAlignment.center,
        'end' => MainAxisAlignment.end,
        'between' => MainAxisAlignment.spaceBetween,
        _ => MainAxisAlignment.start,
      };

  CrossAxisAlignment _crossAxis(String? value, {bool column = false}) => switch (value) {
        'center' => CrossAxisAlignment.center,
        'end' => CrossAxisAlignment.end,
        'baseline' => CrossAxisAlignment.start,
        'stretch' => CrossAxisAlignment.stretch,
        'start' => CrossAxisAlignment.start,
        _ => column ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      };

  // ——— style ———

  /// Wraps a widget in the box half of its style.
  ///
  /// Every field is read independently and only when present, which is what
  /// lets a design authored against a newer dashboard render here minus the one
  /// effect this SDK does not know, rather than failing.
  Widget _styled(BlockStyle? style, Widget child, {bool skipDecoration = false}) {
    if (style == null) return child;
    final doc = ctx.doc;
    var out = child;

    final ratio = style.aspectRatio?.ratio;
    if (ratio != null) out = AspectRatio(aspectRatio: ratio, child: out);

    final padding = EdgeInsets.only(
      top: style.paddingTop ?? style.paddingY ?? style.padding ?? 0,
      bottom: style.paddingBottom ?? style.paddingY ?? style.padding ?? 0,
      left: style.paddingLeft ?? style.paddingX ?? style.padding ?? 0,
      right: style.paddingRight ?? style.paddingX ?? style.padding ?? 0,
    );

    final fill = skipDecoration ? null : revnixBlockColor(style.fill, doc);
    final borderColor = skipDecoration ? null : revnixBlockColor(style.borderColor, doc);
    final hasBorder = borderColor != null || (!skipDecoration && style.borderWidth != null);
    final decoration = (fill != null || hasBorder || (!skipDecoration && style.radius != null))
        ? BoxDecoration(
            color: fill,
            borderRadius: style.radius == null ? null : BorderRadius.circular(style.radius!),
            border: hasBorder
                ? Border.all(
                    color: borderColor ?? revnixBlockColor(doc.textColor, doc) ?? const Color(0xFFFFFFFF),
                    width: style.borderWidth ?? 1,
                  )
                : _sideBorder(style, doc),
          )
        : (_sideBorder(style, doc) != null
            ? BoxDecoration(border: _sideBorder(style, doc))
            : null);

    out = Container(
      padding: padding == EdgeInsets.zero ? null : padding,
      width: style.width?.px,
      height: style.height?.px,
      constraints: style.minHeight == null && style.maxWidth?.px == null
          ? null
          : BoxConstraints(
              minHeight: style.minHeight ?? 0,
              maxWidth: style.maxWidth?.px ?? double.infinity,
            ),
      decoration: decoration,
      clipBehavior: decoration?.borderRadius != null ? Clip.antiAlias : Clip.none,
      child: out,
    );

    final margin = EdgeInsets.only(
      top: style.marginTop?.px ?? style.margin ?? 0,
      bottom: style.marginBottom?.px ?? style.margin ?? 0,
      left: style.marginLeft?.px ?? style.margin ?? 0,
      right: style.marginRight?.px ?? style.margin ?? 0,
    );
    if (margin != EdgeInsets.zero) out = Padding(padding: margin, child: out);

    if (style.rotate != null) {
      out = Transform.rotate(angle: style.rotate! * 3.1415926535897932 / 180, child: out);
    }
    if (style.opacity != null) {
      out = Opacity(opacity: (style.opacity! / 100).clamp(0.0, 1.0), child: out);
    }
    return out;
  }

  /// Per-side rules — table rows and editorial hairlines, which a single
  /// border cannot express. "1.5px solid @text/12" is the shape.
  Border? _sideBorder(BlockStyle style, PaywallBlockDoc doc) {
    BorderSide? side(String? spec) {
      if (spec == null) return null;
      final parts = spec.trim().split(RegExp(r'\s+'));
      if (parts.length < 3) return null;
      final color = revnixBlockColor(parts.sublist(2).join(' '), doc);
      if (color == null) return null;
      final width = double.tryParse(parts[0].replaceAll('px', '')) ?? 1;
      return BorderSide(color: color, width: width);
    }

    final top = side(style.borderTop);
    final right = side(style.borderRight);
    final bottom = side(style.borderBottom);
    final left = side(style.borderLeft);
    if (top == null && right == null && bottom == null && left == null) return null;
    return Border(
      top: top ?? BorderSide.none,
      right: right ?? BorderSide.none,
      bottom: bottom ?? BorderSide.none,
      left: left ?? BorderSide.none,
    );
  }
}
