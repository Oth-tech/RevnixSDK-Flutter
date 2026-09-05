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

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'paywall_background.dart';
import 'paywall_geometry.dart';
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
    this.translate,
    this.clipPath,
    this.fillSize,
    this.textWrap,
    this.filter,
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

  /// CSS `translate` ("-50% 0"), resolved against the block's OWN size — how
  /// the designs centre a badge pinned with `left: 50%`. Drawn.
  final String? translate;

  /// The four below are DECODED so the renderer can say what it cannot draw.
  /// Being decoded is what makes each a known limitation instead of a silent
  /// one: the block keeps its place and its colour, and [onDiagnostic] carries
  /// the value that went unpainted.

  /// CSS `clip-path` — starbursts and ticket notches. Reported, not drawn.
  final String? clipPath;

  /// `background-size` for a repeating gradient wash. A tiled fill needs a
  /// shader this renderer does not build, so the fill paints once. Reported.
  final String? fillSize;

  /// `text-wrap: balance | pretty`. Flutter exposes no wrapping strategy, so
  /// the line breaks fall where the engine puts them. Reported.
  final String? textWrap;

  /// Raw CSS `filter` (soft glows). Reported, not drawn.
  final String? filter;

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
      translate: other.translate ?? translate,
      clipPath: other.clipPath ?? clipPath,
      fillSize: other.fillSize ?? fillSize,
      textWrap: other.textWrap ?? textWrap,
      filter: other.filter ?? filter,
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
      translate: s('translate'),
      clipPath: s('clipPath'),
      fillSize: s('fillSize'),
      textWrap: s('textWrap'),
      filter: s('filter'),
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
/// What tapping a block does. Null means the block is decoration.
///
/// A FIELD on the existing block types rather than a new block type: an SDK
/// older than this one drops the field and still renders the element exactly
/// as it does today, so a design carrying a close chip degrades to inert. A
/// new block type would have parsed to [UnknownBlock] and vanished from the
/// screen instead — worse than the bug this fixes.
enum BlockAction {
  close;

  /// An action this SDK does not know leaves the element inert.
  static BlockAction? parse(String? value) =>
      value == 'close' ? BlockAction.close : null;
}

/// When a block is drawn, relative to the selected context it sits in
/// (REV-262 §1). Absent means always.
enum BlockVisibility {
  /// Drawn only while the block is in selected context.
  selected,

  /// Drawn only while it is NOT.
  unselected;

  /// A value this SDK does not know leaves the block always drawn — hiding
  /// an element on a guess is the worse failure.
  static BlockVisibility? parse(String? value) => switch (value) {
        'selected' => BlockVisibility.selected,
        'unselected' => BlockVisibility.unselected,
        _ => null,
      };
}

@immutable
abstract class PaywallBlock {
  const PaywallBlock({
    required this.id,
    this.style,
    this.selectedStyle,
    this.visibility,
  });
  final String id;
  final BlockStyle? style;

  /// Merged over [style], field by field, while the block is in SELECTED
  /// CONTEXT — inside the plan card of the selected package (REV-262 §1).
  /// Valid on every block type: a tick mark, a ring, a caption can all answer
  /// the selection, not only the card around them.
  final BlockStyle? selectedStyle;

  /// Draw only in / only outside selected context. Ignored at the root and in
  /// any subtree that no package card encloses — a root block is never hidden.
  final BlockVisibility? visibility;
}

class TextBlock extends PaywallBlock {
  const TextBlock({
    required super.id,
    required this.text,
    super.style,
    super.selectedStyle,
    super.visibility,
    this.action,
  });
  final String text;

  /// Tapping this block dismisses the paywall. See [BlockAction].
  final BlockAction? action;
}

class ImageBlock extends PaywallBlock {
  const ImageBlock({
    required super.id,
    this.url,
    this.shape,
    this.fit,
    this.placeholder,
    super.style,
    super.selectedStyle,
    super.visibility,
    this.action,
  });

  /// Empty falls back to the config's hero image, then to a blank slot.
  final String? url;
  final String? shape;
  final String? fit;
  final String? placeholder;

  /// Tapping this block dismisses the paywall. See [BlockAction].
  final BlockAction? action;
}

class ListBlock extends PaywallBlock {
  const ListBlock({
    required super.id,
    this.items = const [],
    this.iconColor,
    super.style,
    super.selectedStyle,
    super.visibility,
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
    super.selectedStyle,
    super.visibility,
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
  const ButtonBlock({
    required super.id,
    required this.label,
    super.style,
    super.selectedStyle,
    super.visibility,
    this.action,
  });
  final String label;

  /// [BlockAction.close] turns this button into a dismiss ("Not now") instead
  /// of the purchase CTA, which is what a button means by default.
  final BlockAction? action;
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
    super.selectedStyle,
    super.visibility,
  });
  final bool? showRestore;
  final bool? showTerms;
  final bool? showPrivacy;
  final String? termsUrl;
  final String? privacyUrl;
}

class LineBlock extends PaywallBlock {
  const LineBlock({
    required super.id,
    super.style,
    super.selectedStyle,
    super.visibility,
  });
}

class SpacerBlock extends PaywallBlock {
  const SpacerBlock({
    required super.id,
    this.flex,
    super.style,
    super.selectedStyle,
    super.visibility,
  });

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
    this.packageIndex,
    this.columns,
    this.gridColumns,
    this.children = const [],
    super.style,
    super.selectedStyle,
    super.visibility,
  });
  final String? layout;

  /// Renders this container once per package in the attached offering.
  final String? repeat;

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
    this.backgroundSpec,
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

  /// The ground paint — a colour or a CSS gradient string. Kept flat because
  /// it is what `@bg` resolves against and what every unedited paywall has.
  final String background;

  /// The background exactly as published, so the photo and scrim layers can
  /// be resolved. Null for a document whose background is a plain string.
  final Object? backgroundSpec;
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
    // layered one. The object's ground field is `color` — `ground` is the
    // name of the RESOLVED layer, and reading that off the wire is what used
    // to paint every edited paywall black; it stays accepted for safety.
    final background = value['background'];
    String? str(Object? v) => v is String ? v : null;
    return PaywallBlockDoc(
      version: value['version'] is num ? (value['version'] as num).toInt() : 1,
      layout: str(value['layout']),
      backgroundSpec: background,
      background: revnixBackgroundGround(background) ?? '#000000',
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
    // Every type carries these two (REV-262 §1), so they are read once here
    // rather than per case — a type that forgot them would silently ignore a
    // selection answer the design authored.
    final selectedStyle = BlockStyle.from(value['selectedStyle']);
    final visibility = BlockVisibility.parse(s('visibility'));
    final action = BlockAction.parse(s('action'));
    switch (value['type']) {
      case 'text':
        return TextBlock(
          id: id,
          text: s('text') ?? '',
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
          action: action,
        );
      case 'image':
        return ImageBlock(
          id: id,
          url: s('url'),
          shape: s('shape'),
          fit: s('fit'),
          placeholder: s('placeholder'),
          action: action,
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
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
          selectedStyle: selectedStyle,
          visibility: visibility,
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
          selectedStyle: selectedStyle,
          visibility: visibility,
        );
      case 'button':
        return ButtonBlock(
          id: id,
          label: s('label') ?? '',
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
          action: action,
        );
      case 'links':
        return LinksBlock(
          id: id,
          showRestore: b('showRestore'),
          showTerms: b('showTerms'),
          showPrivacy: b('showPrivacy'),
          termsUrl: s('termsUrl'),
          privacyUrl: s('privacyUrl'),
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
        );
      case 'line':
        return LineBlock(
          id: id,
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
        );
      case 'spacer':
        return SpacerBlock(
          id: id,
          flex: b('flex'),
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
        );
      case 'card':
        return CardBlock(
          id: id,
          layout: s('layout'),
          repeat: s('repeat'),
          packageIndex: i('packageIndex'),
          columns: i('columns'),
          gridColumns: s('gridColumns'),
          children:
              (value['children'] as List<Object?>? ?? const []).map(_parseBlock).toList(),
          style: style,
          selectedStyle: selectedStyle,
          visibility: visibility,
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

// ——— selection and selected context (REV-262 §1–2) ———

/// The package the screen treats as selected, by the rule every renderer
/// shares: the host's choice if it names an OFFERED package, else the
/// renderer's own selection after a tap, else the config's highlight, else
/// the first package. Null only when nothing is offered.
///
/// The host's id is checked against the offering rather than trusted: a host
/// that pins a package the offering no longer carries would otherwise leave
/// every plan card unselected and the CTA buying nothing.
String? revnixResolveSelectedPackageId(
  List<RevnixPaywallPackage> packages, {
  String? hostSelected,
  String? internalSelected,
  String? highlight,
}) {
  bool offered(String? id) => id != null && packages.any((p) => p.packageId == id);
  if (offered(hostSelected)) return hostSelected;
  if (offered(internalSelected)) return internalSelected;
  if (offered(highlight)) return highlight;
  return packages.isEmpty ? null : packages.first.packageId;
}

/// [selectedPackageId] as a package when the offering carries it, else the
/// first package — what root-level tags resolve against and what the CTA
/// buys.
RevnixPaywallPackage? revnixSelectedPackage(
  List<RevnixPaywallPackage> packages,
  String? selectedPackageId,
) {
  for (final p in packages) {
    if (p.packageId == selectedPackageId) return p;
  }
  return packages.isEmpty ? null : packages.first;
}

/// Where in the tree a block is being resolved: the package its tags read,
/// and whether it sits inside the SELECTED package's card.
///
/// [selected] is null outside any package card. There `selectedStyle` and
/// `visibility` are inert — a root-level block is never hidden, whatever it
/// asks for — and tags resolve against the selected package.
@immutable
class RevnixBlockScope {
  const RevnixBlockScope({this.package, this.selected});

  /// The document root: tags read the selected package, no selected context.
  const RevnixBlockScope.root(RevnixPaywallPackage? selectedPackage)
      : this(package: selectedPackage);

  final RevnixPaywallPackage? package;

  /// Null outside any package card; otherwise whether the enclosing package
  /// card's package is the selected one.
  final bool? selected;

  bool get inSelectedContext => selected == true;

  /// The scope of a package card's subtree — a pinned card, or one instance
  /// of a `repeat: "packages"` card. The nearest package-bearing ancestor
  /// wins, so entering from any depth replaces the context outright.
  RevnixBlockScope enter(
    RevnixPaywallPackage? package,
    RevnixPaywallPackage? selectedPackage,
  ) =>
      RevnixBlockScope(
        package: package,
        selected: package != null &&
            selectedPackage != null &&
            package.packageId == selectedPackage.packageId,
      );
}

/// The package a pinned card describes, or null when the card is not pinned
/// or the offering does not reach its index. A negative index counts as
/// unreachable — indexing the list with it used to throw and take the screen.
RevnixPaywallPackage? revnixPinnedPackage(
  CardBlock card,
  List<RevnixPaywallPackage> packages,
) {
  final index = card.packageIndex;
  if (index == null || index < 0 || index >= packages.length) return null;
  return packages[index];
}

/// The scope a block's OWN style and visibility resolve against.
///
/// A pinned card decides its own context — its package against the selected
/// one — which is also what its children inherit. Every other block (a
/// `repeat` card included; its instances are scoped one by one where they
/// render) resolves against the scope it was given.
RevnixBlockScope revnixOwnScope(
  PaywallBlock block,
  RevnixBlockScope parent,
  List<RevnixPaywallPackage> packages,
  RevnixPaywallPackage? selectedPackage,
) {
  if (block is CardBlock && block.packageIndex != null) {
    final pinned = revnixPinnedPackage(block, packages);
    if (pinned != null) return parent.enter(pinned, selectedPackage);
  }
  return parent;
}

/// The style a block draws with in [scope]: `selectedStyle` merged over
/// `style` while in selected context, the base style otherwise.
BlockStyle? revnixEffectiveStyle(PaywallBlock block, RevnixBlockScope scope) {
  final selectedStyle = block.selectedStyle;
  if (selectedStyle == null || !scope.inSelectedContext) return block.style;
  return (block.style ?? const BlockStyle()).merging(selectedStyle);
}

/// Whether a block is drawn in [scope]. Outside any package card the answer
/// is always yes.
bool revnixBlockVisible(PaywallBlock block, RevnixBlockScope scope) {
  final selected = scope.selected;
  if (selected == null) return true;
  return switch (block.visibility) {
    null => true,
    BlockVisibility.selected => selected,
    BlockVisibility.unselected => !selected,
  };
}

/// One block after the selection rules: what [RevnixPaywallBlockScreen]
/// draws it with, without the widgets.
@immutable
class RevnixResolvedBlock {
  const RevnixResolvedBlock({
    required this.block,
    required this.scope,
    required this.style,
    required this.visible,
    this.text,
  });

  final PaywallBlock block;
  final RevnixBlockScope scope;

  /// The effective style — after `selectedStyle`.
  final BlockStyle? style;

  /// Drawn: its own rule AND every ancestor's.
  final bool visible;

  /// The copy after tags, for text and button blocks.
  final String? text;
}

/// Walks a document the way the renderer does and returns every block's
/// resolved state by id — the pure half of the render contract, which the
/// shared `paywall-selection-wire.json` fixture is asserted against.
///
/// Inside a `repeat: "packages"` card each instance and its descendants are
/// keyed `<id>@<packageId>`, so the instances do not overwrite each other. A
/// pinned card whose index the offering does not reach is absent, as it is
/// from the screen.
Map<String, RevnixResolvedBlock> revnixResolveBlocks(
  PaywallBlockDoc doc, {
  required List<RevnixPaywallPackage> packages,
  String? selectedPackageId,
}) {
  final selected = revnixSelectedPackage(packages, selectedPackageId);
  final out = <String, RevnixResolvedBlock>{};

  void walk(
    List<PaywallBlock> blocks,
    RevnixBlockScope parent,
    bool parentVisible,
    String suffix,
  ) {
    for (final block in blocks) {
      if (block is CardBlock && block.repeat == 'packages') {
        final list = packages.isEmpty ? <RevnixPaywallPackage?>[null] : packages;
        final visible = parentVisible && revnixBlockVisible(block, parent);
        for (final each in list) {
          final scope = parent.enter(each, selected);
          final key = '$suffix@${each?.packageId ?? ''}';
          out['${block.id}$key'] = RevnixResolvedBlock(
            block: block,
            scope: scope,
            style: revnixEffectiveStyle(block, scope),
            visible: visible,
          );
          walk(block.children, scope, visible, key);
        }
        continue;
      }
      if (block is CardBlock &&
          block.packageIndex != null &&
          revnixPinnedPackage(block, packages) == null) {
        continue;
      }
      final scope = revnixOwnScope(block, parent, packages, selected);
      final visible = parentVisible && revnixBlockVisible(block, scope);
      out['${block.id}$suffix'] = RevnixResolvedBlock(
        block: block,
        scope: scope,
        style: revnixEffectiveStyle(block, scope),
        visible: visible,
        text: switch (block) {
          TextBlock(:final text) => revnixResolveTags(text, scope.package, packages),
          ButtonBlock(:final label) => revnixResolveTags(label, scope.package, packages),
          _ => null,
        },
      );
      if (block is CardBlock) walk(block.children, scope, visible, suffix);
    }
  }

  walk(doc.blocks, RevnixBlockScope.root(selected), true, '');
  return out;
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
        // The ground's FLAT base colour, which is what the dashboard answers
        // `@bg` with: it feeds the token into `color-mix()`, which cannot take
        // a gradient, so it collapses a gradient ground to one colour first.
        // Handing the raw gradient here instead made every `@bg` stop inside a
        // gradient drop out — and a gradient left with one stop does not parse
        // at all, so the whole fill was lost.
        raw = revnixBackgroundBaseColor(doc.background);
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

/// A resolved paint: EITHER a flat colour, OR gradient layers, BOTTOM FIRST.
///
/// The dashboard hands `fill` straight to CSS `background`, which takes a
/// colour *or* a gradient *or* a stack of them. Flutter has no single type for
/// that union, so it is carried as two fields and painted by
/// [revnixFillLayers].
///
/// The two are never both set. The flat colour a gradient collapses to belongs
/// only to the case where the gradient cannot be drawn: painting it underneath
/// one that CAN be drawn makes the box opaque, and 83 of the library's 139
/// gradient fills are scrims that fade through a translucent stop — they are
/// drawn over the screen's photo precisely so it shows through.
class RevnixFill {
  const RevnixFill({this.color, this.gradients = const []})
      : assert(color == null || gradients.length == 0,
            'a painted gradient takes no flat backing');

  final Color? color;
  final List<Gradient> gradients;

  bool get isNone => color == null && gradients.isEmpty;
}

/// Resolves a paint string the way the dashboard's CSS `background` does.
///
/// A plain colour is tried first (the common case, and the cheap one), then
/// the gradient forms, and only then the fallback. Nothing fails silently: a
/// `fill` the design set but this build cannot read collapses to the first
/// colour literal in the string — a colour FROM THE DESIGN, never black — and
/// reports through [onDiagnostic].
RevnixFill revnixBlockFill(
  String? value,
  PaywallBlockDoc doc, {
  void Function(String)? onDiagnostic,
}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return const RevnixFill();

  final flat = revnixBlockColor(raw, doc);
  if (flat != null) return RevnixFill(color: flat);

  final gradients = revnixParseCssGradients(raw, (v) => revnixBlockColor(v, doc));
  if (gradients.isNotEmpty) return RevnixFill(gradients: gradients);

  onDiagnostic?.call('unreadable fill $raw');
  // A pattern paints nothing rather than a stripe colour spread over the box.
  if (revnixIsRepeatingPattern(raw)) return const RevnixFill();
  return RevnixFill(color: revnixBlockColor(revnixBackgroundBaseColor(raw), doc));
}

/// The flat colour a parsed gradient stack stands in for: the first stop of the
/// BOTTOM layer that is not fully transparent. It is what shows through a
/// translucent stop, and what stays on screen if a layer fails to paint.
Color? revnixGradientBaseColor(List<Gradient> gradients) {
  if (gradients.isEmpty) return null;
  final colors = gradients.first.colors;
  if (colors.isEmpty) return null;
  for (final c in colors) {
    if (c.a > 0) return c;
  }
  return colors.first;
  // NB: the alpha is read off the RESOLVED colour, so a token stop written
  // `@accent/0` counts as transparent exactly as `#6478ff00` does.
}

/// A field that can only ever be ONE colour — a border, text, an icon.
///
/// A gradient there has no native form (nor a CSS one: `border-color` takes no
/// gradient, so the dashboard drops the declaration outright). Collapsing it to
/// the colour it stands for keeps the stroke or the glyph visible, which is
/// nearer the design's intent than losing it.
Color? revnixBlockStrokeColor(
  String? value,
  PaywallBlockDoc doc, {
  void Function(String)? onDiagnostic,
}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final flat = revnixBlockColor(raw, doc);
  if (flat != null) return flat;
  final base = revnixGradientBaseColor(
    revnixParseCssGradients(raw, (v) => revnixBlockColor(v, doc)),
  );
  if (base != null) {
    onDiagnostic?.call('gradient flattened in a colour-only field: $raw');
    return base;
  }
  onDiagnostic?.call('unreadable colour $raw');
  return revnixBlockColor(revnixBackgroundBaseColor(raw), doc);
}

/// A fill's gradient layers as widgets that fill their Stack, bottom first.
List<Widget> revnixFillLayers(RevnixFill fill) => [
      for (final gradient in fill.gradients)
        Positioned.fill(child: _GradientBox(gradient: gradient)),
    ];

/// Parses "#rgb", "#rrggbb", "#rrggbbaa", "rgb()", "rgba()" and `transparent`.
Color? revnixParseColor(String value) {
  final s = value.trim();
  // `transparent` appears in the shipped designs' gradient stops. Rejecting it
  // dropped the stop, and a gradient left with one stop does not parse at all.
  if (s.toLowerCase() == 'transparent') return const Color(0x00000000);
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

/// Paints a resolved fill behind [child], clipped to [radius].
///
/// The flat-colour case stays a plain [DecoratedBox] — the shape every paywall
/// had before gradients rendered — and only a gradient takes the layered path.
class RevnixFillBox extends StatelessWidget {
  const RevnixFillBox({super.key, required this.fill, this.radius, this.child});

  final RevnixFill fill;
  final BorderRadius? radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // A null child takes the shape Container gives one: a LimitedBox that
    // collapses under UNBOUNDED constraints and expands under bounded ones.
    // A bare SizedBox.expand() throws instead — which a `line` block inside a
    // `row` card would have done on the plain-colour path.
    final content = child ??
        const LimitedBox(maxWidth: 0, maxHeight: 0, child: SizedBox.expand());
    if (fill.gradients.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: fill.color, borderRadius: radius),
        child: content,
      );
    }
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          ...revnixFillLayers(fill),
          content,
        ],
      ),
    );
  }
}

// ——— rendering ———

/// Everything the tree needs that is not in the document itself.
@immutable
class BlockRenderContext {
  const BlockRenderContext({
    required this.doc,
    required this.packages,
    this.selectedPackageId,
    this.loading = false,
    this.heroImageUrl,
    this.footerTermsUrl,
    this.footerPrivacyUrl,
    required this.onPurchase,
    required this.onSelect,
    this.onRestore,
    this.onTerms,
    this.onPrivacy,
    this.onClose,
    this.onDiagnostic,
  });

  final PaywallBlockDoc doc;
  final List<RevnixPaywallPackage> packages;

  /// The package a plan card visually emphasizes, and the one whose tags a
  /// subtree resolves against outside a `repeat`. See [selectedPackage] for
  /// the rule when it names nothing on offer.
  final String? selectedPackageId;

  /// The host is mid-purchase (REV-262 §4). Purchase buttons ignore taps and
  /// show a spinner where their label was; close buttons are unaffected.
  /// Carried here rather than gated silently by the host, because a tap that
  /// does nothing with no visible reason reads as a broken button.
  final bool loading;

  /// Fills an image block that publishes no URL of its own.
  final String? heroImageUrl;

  /// Paywall-level Terms/Privacy, used when a links block sets none.
  final String? footerTermsUrl;
  final String? footerPrivacyUrl;
  final void Function(String packageId) onPurchase;

  /// Reports a plan card tap. Selection is the paywall's own state, so a
  /// design's plan cards work without the host wiring anything.
  final void Function(String packageId) onSelect;
  final VoidCallback? onRestore;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;

  /// Dismissal (REV-252). Null means the host wired none, and no close is
  /// drawn at all — a dead close button is worse than none.
  final VoidCallback? onClose;

  /// Where the renderer reports a paint string it could not read. Local only —
  /// it never leaves the device. The screen still draws (a fill falls back to a
  /// colour from the design), so this is the only way a host learns that a
  /// paywall is rendering approximately.
  final void Function(String message)? onDiagnostic;

  /// The package the screen treats as selected: [selectedPackageId] when the
  /// offering carries it, else the first package (REV-262 §1). Root-level
  /// tags resolve against it, plan cards compare against it, the CTA buys it.
  RevnixPaywallPackage? get selectedPackage =>
      revnixSelectedPackage(packages, selectedPackageId);
}

/// The widest a phone-authored canvas scales to (REV-262 §3). Past this a
/// tablet or landscape viewport centres the design and the document
/// background fills the rest, rather than blowing the design up 2.6×.
const double kRevnixCanvasMaxWidth = 480;

/// Uniform scale for a canvas design at [viewportWidth] logical pixels.
double revnixCanvasScale(double viewportWidth) {
  final width = viewportWidth.isFinite ? viewportWidth : kRevnixCanvasWidth;
  final capped = width < kRevnixCanvasMaxWidth ? width : kRevnixCanvasMaxWidth;
  return capped / kRevnixCanvasWidth;
}

/// The canvas's layout height in DESIGN units for a viewport of
/// [viewportHeight] logical pixels at [scale]: never less than the authored
/// 852, and enough to fill a taller screen so bottom-anchored groups and
/// `height: "100%"` cards follow the viewport instead of leaving a band.
double revnixCanvasDesignHeight(double viewportHeight, double scale) {
  if (!viewportHeight.isFinite || scale <= 0) return kRevnixCanvasHeight;
  final needed = viewportHeight / scale;
  return needed > kRevnixCanvasHeight ? needed : kRevnixCanvasHeight;
}

/// The decode width for a photo drawn into a box [boxWidth] logical pixels
/// wide (REV-262 §5): twice the box's physical pixels, so a `cover` crop and
/// a retina upgrade both stay sharp without decoding a 4000px original for a
/// 393pt slot. Null when the box is not yet known — the image then decodes
/// at its own size, as it always did. Flutter's resize never upscales, so a
/// small original is left alone.
int? revnixImageCacheWidth(double boxWidth, double devicePixelRatio) {
  if (!boxWidth.isFinite || boxWidth <= 0 || devicePixelRatio <= 0) return null;
  return (boxWidth * devicePixelRatio * 2).ceil();
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
    final layers = revnixBackgroundLayers(
      doc.backgroundSpec ?? doc.background,
      resolve: (v) => v,
    );
    final background = _groundColor(layers.ground, doc);
    final art = _backgroundArt(layers, doc);
    // Root-level tags resolve against the selected package (REV-262 §2): the
    // renewal line every template carries — "then {price}/{period_short}" —
    // sits outside any plan card and must name what the CTA will charge.
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _renderList(doc.blocks, RevnixBlockScope.root(ctx.selectedPackage)),
    );
    final close = _fallbackClose(context);

    if (doc.layout == 'canvas') {
      return LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : kRevnixCanvasWidth;
          final scale = revnixCanvasScale(viewportWidth);
          final designHeight = revnixCanvasDesignHeight(constraints.maxHeight, scale);
          final scaledWidth = kRevnixCanvasWidth * scale;
          final scaledHeight = designHeight * scale;
          final viewportHeight =
              constraints.maxHeight.isFinite ? constraints.maxHeight : scaledHeight;
          // Within half a pixel counts as fitting: float noise from the
          // division above must not turn a design that fills its screen into
          // one that scrolls a hairline.
          final fits = scaledHeight <= viewportHeight + 0.5;

          // The design's box: centred when the width cap leaves a margin,
          // clipped so a stack child hanging off the canvas edge stays inside
          // it, and as tall as the scaled design — which is what the scroll
          // view measures when the viewport is shorter.
          final canvas = SizedBox(
            width: viewportWidth,
            height: scaledHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: (viewportWidth - scaledWidth) / 2,
                  top: 0,
                  width: scaledWidth,
                  height: scaledHeight,
                  // OverflowBox lets the design lay out at its authored
                  // width even when that is wider than the scaled box (a
                  // 320pt phone), which a plain SizedBox would be clamped to.
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: kRevnixCanvasWidth,
                    maxWidth: kRevnixCanvasWidth,
                    minHeight: designHeight,
                    maxHeight: designHeight,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: kRevnixCanvasWidth,
                        height: designHeight,
                        child: body,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          return Container(
            // The colour goes on the decoration rather than `color:` —
            // Container asserts a decoration exists whenever it clips.
            decoration: BoxDecoration(color: background),
            width: viewportWidth,
            height: viewportHeight,
            clipBehavior: Clip.hardEdge,
            // The ground and art fill the whole viewport — around a centred
            // design on a tablet, and behind a scrolling one — and the close
            // chip sits outside the scale transform, in unscaled points.
            child: Stack(
              fit: StackFit.expand,
              children: [
                ...art,
                _scroller(context, canvas, fits: fits),
                ...close,
              ],
            ),
          );
        },
      );
    }

    final scroller = _scroller(
      context,
      body,
      padding: const EdgeInsets.all(20),
    );
    if (art.isEmpty && close.isEmpty) {
      return Container(color: background, child: scroller);
    }
    // The art layers fill the screen and the content scrolls over them, which
    // is what the dashboard's absolutely-positioned art boxes do too.
    return Container(
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [...art, scroller, ...close],
      ),
    );
  }

  /// The paywall's scroll view (REV-262 §3): no scrollbar, no overscroll
  /// glow, and no bounce while the content fits. [fits] is passed when the
  /// caller already knows the answer (the canvas), and scrolling is then
  /// switched off outright; otherwise [RevnixPaywallScrollPhysics] decides
  /// from the measured extent.
  Widget _scroller(
    BuildContext context,
    Widget child, {
    bool? fits,
    EdgeInsetsGeometry? padding,
  }) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        overscroll: false,
      ),
      child: SingleChildScrollView(
        physics: fits == true
            ? const NeverScrollableScrollPhysics()
            : const RevnixPaywallScrollPhysics(),
        padding: padding,
        child: child,
      ),
    );
  }

  /// The dismiss affordance the renderer supplies itself (REV-252), or an
  /// empty list when it should not draw one.
  ///
  /// Drawn only when the design authors no close of its own AND the host wired
  /// an `onClose` — which is what makes every paywall published before close
  /// existed dismissible without being re-authored, while a design that DOES
  /// carry a close chip never ends up showing two.
  ///
  /// Deliberately plain: it is a safety net, not a design element. Tinted from
  /// the screen's own ink rather than a fixed white, so it stays legible on a
  /// light design as well as a dark one. Sits below the status bar: the
  /// screen is full-bleed, so without the inset the chip lands under the
  /// clock (REV-262 §3).
  List<Widget> _fallbackClose(BuildContext context) {
    final onClose = ctx.onClose;
    if (onClose == null || revnixHasCloseAction(ctx.doc.blocks)) return const [];
    final ink = revnixBlockColor(ctx.doc.textColor, ctx.doc) ?? const Color(0xFFFFFFFF);
    final safeTop = MediaQuery.maybeViewPaddingOf(context)?.top ?? 0;
    return [
      Positioned(
        top: 14 + safeTop,
        right: 14,
        child: Semantics(
          button: true,
          label: 'Close',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ink.withValues(alpha: 0.14),
              ),
              child: Text(
                '×',
                style: TextStyle(color: ink, fontSize: 17, height: 1),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// The ground as a flat colour, for the box behind everything. A gradient
  /// ground is drawn by [_backgroundArt] instead; the flat colour under it is
  /// its base stop, so a gradient that fails to parse still shows a colour
  /// from the design rather than black.
  Color _groundColor(String? ground, PaywallBlockDoc doc) =>
      revnixBlockColor(revnixBackgroundBaseColor(ground), doc) ??
      const Color(0xFF000000);

  /// The gradient, photo and scrim layers, bottom first. Empty for an
  /// unedited paywall whose background is a flat colour, so that case renders
  /// exactly as it did before.
  List<Widget> _backgroundArt(RevnixBackgroundLayers layers, PaywallBlockDoc doc) {
    final out = <Widget>[];

    final ground = layers.ground;
    if (ground != null) {
      for (final gradient in revnixParseCssGradients(
        ground,
        (v) => revnixBlockColor(v, doc),
      )) {
        out.add(Positioned.fill(child: _GradientBox(gradient: gradient)));
      }
    }

    final image = layers.image;
    if (image != null) {
      Widget photo = _photo(
        image.url,
        fit: image.fit == RevnixBackgroundFit.contain
            ? BoxFit.contain
            : BoxFit.cover,
        alignment: image.alignment,
        // A photo that will not load must not black out the screen: the
        // ground and scrim below and above it still make a usable paywall.
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
      if (image.blur != null) {
        // A blurred layer bleeds its own transparent edge inward, which reads
        // as a bright rim over the ground. Scaling past the edges hides it —
        // the same compensation every sibling renderer applies — and the clip
        // keeps the oversized layer inside the screen.
        photo = ClipRect(
          child: Transform.scale(
            scale: 1.1,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: image.blur!, sigmaY: image.blur!),
              child: photo,
            ),
          ),
        );
      }
      out.add(Positioned.fill(
        child: Opacity(opacity: image.opacity, child: photo),
      ));
    }

    final overlay = layers.overlay;
    if (overlay != null) {
      final gradients = revnixParseCssGradients(
        overlay.fill,
        (v) => revnixBlockColor(v, doc),
      );
      final children = <Widget>[];
      if (gradients.isEmpty) {
        final solid = revnixBlockColor(overlay.fill, doc);
        if (solid != null) {
          children.add(DecoratedBox(decoration: BoxDecoration(color: solid)));
        }
      } else {
        for (final gradient in gradients) {
          children.add(_GradientBox(gradient: gradient));
        }
      }
      if (children.isNotEmpty) {
        out.add(Positioned.fill(
          child: Opacity(
            opacity: overlay.opacity,
            child: children.length == 1
                ? children.first
                : Stack(fit: StackFit.expand, children: children),
          ),
        ));
      }
    }

    return out;
  }

  /// A network photo that fills its box and decodes no larger than twice the
  /// box's physical pixels (REV-262 §5). The one loader for the screen
  /// background and for `image` blocks, so both get the same downsampling
  /// and the same failure behaviour.
  Widget _photo(
    String url, {
    required BoxFit fit,
    Alignment alignment = Alignment.center,
    required ImageErrorWidgetBuilder errorBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => Image.network(
        url,
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: revnixImageCacheWidth(
          constraints.maxWidth,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
        ),
        errorBuilder: errorBuilder,
      ),
    );
  }

  List<Widget> _renderList(List<PaywallBlock> blocks, RevnixBlockScope scope) =>
      [for (final pair in _renderPairs(blocks, scope)) pair.$2];

  /// Renders each child ONCE and keeps it beside its EFFECTIVE style — the
  /// one after `selectedStyle` — so a container reads the flex, basis and
  /// stack placement the block actually has in this context without
  /// rendering it twice, and so the widget list and the block list never fall
  /// out of step when a block contributes nothing or is hidden.
  List<(BlockStyle?, Widget)> _renderPairs(
    List<PaywallBlock> blocks,
    RevnixBlockScope scope,
  ) {
    final out = <(BlockStyle?, Widget)>[];
    for (final block in blocks) {
      // A pinned card resolves its own visibility and style against ITS
      // package; everything else against the scope it sits in.
      final own = revnixOwnScope(block, scope, ctx.packages, ctx.selectedPackage);
      if (!revnixBlockVisible(block, own)) continue;
      final style = revnixEffectiveStyle(block, own);
      final widget = _render(block, scope, style);
      if (widget != null) out.add((style, widget));
    }
    return out;
  }

  /// One block, or null when it contributes nothing. [style] is the block's
  /// effective style in [scope]; [scope] is the PARENT's — a package card
  /// derives its children's scope itself in [_card].
  Widget? _render(PaywallBlock block, RevnixBlockScope scope, BlockStyle? style) {
    final doc = ctx.doc;
    if (block is TextBlock) {
      return _closeOnTap(
        block.action,
        _styled(
          style,
          Text(
            revnixResolveTags(block.text, scope.package, ctx.packages),
            textAlign: _textAlign(style?.align),
            maxLines: style?.nowrap == true ? 1 : null,
            overflow: style?.nowrap == true ? TextOverflow.clip : null,
            style: _textStyle(style),
          ),
        ),
      );
    }
    if (block is ImageBlock) return _closeOnTap(block.action, _image(block, style));
    if (block is ListBlock) return _list(block, style);
    if (block is ProductsBlock) return _products(block, style);
    if (block is ButtonBlock) return _button(block, scope, style);
    if (block is LinksBlock) return _links(block, style);
    if (block is LineBlock) {
      var fill = revnixBlockFill(style?.fill, doc, onDiagnostic: ctx.onDiagnostic);
      if (fill.isNone) {
        fill = RevnixFill(
          color: (revnixBlockColor(doc.textColor, doc) ?? const Color(0xFFFFFFFF))
              .withValues(alpha: 0.16),
        );
      }
      return _styled(
        style,
        SizedBox(
          height: style?.height?.px ?? 1,
          child: RevnixFillBox(fill: fill),
        ),
        skipDecoration: true,
      );
    }
    if (block is SpacerBlock) {
      // `flex` grows to push what follows to the bottom.
      if (block.flex == true) return const Spacer();
      return SizedBox(height: style?.height?.px ?? 16);
    }
    if (block is CardBlock) return _card(block, scope, style);
    // An unknown block type from a newer dashboard: skip it, keep the screen.
    return null;
  }

  // ——— leaves ———

  TextStyle _textStyle(BlockStyle? style, {double defaultSize = 15, FontWeight? defaultWeight}) {
    final doc = ctx.doc;
    final size = style?.fontSize ?? defaultSize;
    return TextStyle(
      color: revnixBlockStrokeColor(style?.textColor, doc, onDiagnostic: ctx.onDiagnostic) ??
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

  Widget _image(ImageBlock block, BlockStyle? style) {
    // A converted design sizes its own slot; the 160px default is only for a
    // slot dropped into a flow column, and must not fight it. An `inset`
    // image is placed by [_stackChild] with Positioned.fill, so it takes the
    // whole stack on both axes and needs no size of its own here.
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
          : _photo(
              url,
              fit: block.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
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

  Widget _list(ListBlock block, BlockStyle? style) {
    final doc = ctx.doc;
    final gap = style?.gap ?? 8;
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
      style,
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  /// Makes an element the paywall's dismiss target when the design marks it as
  /// one (REV-252). A block with no close action is returned untouched, so it
  /// never intercepts a tap meant for what sits behind it.
  Widget _closeOnTap(BlockAction? action, Widget child) {
    final onClose = ctx.onClose;
    if (action != BlockAction.close || onClose == null) return child;
    return Semantics(
      button: true,
      label: 'Close',
      child: GestureDetector(
        // The whole box is the target, not just the glyph: a close chip is
        // mostly padding, and a bare × is well under the 48dp tap minimum.
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: child,
      ),
    );
  }

  Widget _button(ButtonBlock block, RevnixBlockScope scope, BlockStyle? style) {
    final doc = ctx.doc;
    // A button the design marks as the close dismisses instead of buying, and
    // takes no accent fill: the CTA must stay the one accented thing on the
    // screen, or a "Not now" competes with "Subscribe" for the eye.
    final closes = block.action == BlockAction.close && ctx.onClose != null;
    // `skipDecoration` hands the box back to us, so the fill is resolved here
    // rather than by `_styled` — which is why a gradient CTA used to flatten to
    // the plain accent.
    // The dashboard hands every button's `fill` to CSS `background`; the
    // close-button rule only decides what happens when there is NO fill.
    var fill = revnixBlockFill(style?.fill, doc, onDiagnostic: ctx.onDiagnostic);
    if (fill.isNone && style?.fill == null) {
      fill = RevnixFill(
        color: closes
            ? const Color(0x00000000)
            : revnixBlockColor(doc.accent, doc) ?? const Color(0xFF6478FF),
      );
    }
    final ink = revnixBlockStrokeColor(style?.textColor, doc, onDiagnostic: ctx.onDiagnostic) ??
        (closes
            ? revnixBlockColor(doc.textColor, doc) ?? const Color(0xFFFFFFFF)
            : revnixBlockColor(doc.accentInk, doc) ?? const Color(0xFFFFFFFF));
    final sized = style?.height?.px != null;
    return _styled(
      style,
      RevnixBlockButton(
        // A "Not now" keeps working mid-purchase: only the buying buttons
        // wait for the store (REV-262 §4).
        loading: ctx.loading && !closes,
        spinnerColor: ink,
        fill: fill,
        radius: BorderRadius.circular(style?.radius ?? 12),
        height: style?.height?.px,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: sized ? 0 : 15),
        onTap: () {
          if (closes) {
            ctx.onClose?.call();
            return;
          }
          final id = ctx.selectedPackage?.packageId;
          if (id != null) ctx.onPurchase(id);
        },
        label: Text(
          revnixResolveTags(block.label, scope.package, ctx.packages),
          textAlign: TextAlign.center,
          style: _textStyle(style, defaultWeight: FontWeight.w800).copyWith(color: ink),
        ),
      ),
      skipDecoration: true,
    );
  }

  Widget? _links(LinksBlock block, BlockStyle? style) {
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
            child: Text(label, style: _textStyle(style, defaultSize: 12)),
          ),
        ),
      );
    }
    return _styled(
      style,
      Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
      skipDecoration: true,
    );
  }

  Widget _products(ProductsBlock block, BlockStyle? style) {
    final doc = ctx.doc;
    final shown = ctx.packages;
    final highlightId = ctx.selectedPackage?.packageId;
    final row = block.direction == 'row';
    final gap = style?.gap ?? 8;
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
      // The whole card is the target, not just its glyphs — a plan row is
      // mostly padding, and tapping beside the price must select. Opaque so
      // the transparent padding takes the hit too. No pressed opacity: the
      // highlight treatment IS the feedback (REV-262 §4).
      final styled = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ctx.onSelect(pkg.packageId),
        child: _styled(hl ? block.highlightStyle : block.cardStyle, card, skipDecoration: true),
      );
      cards.add(row ? Expanded(child: styled) : styled);
    }

    return _styled(
      style,
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
  ///
  /// [scope] is the parent's; [style] the card's effective style in its OWN
  /// scope (a pinned card's own package decides that — see [revnixOwnScope]).
  Widget? _card(CardBlock block, RevnixBlockScope scope, BlockStyle? style) {
    final selected = ctx.selectedPackage;
    if (block.repeat == 'packages') {
      // One designed card, rendered per package. With nothing attached a single
      // instance still renders, so the design stays visible. Each instance is
      // its own selected context: the selected one takes `selectedStyle`, and
      // its descendants see it as selected.
      final list = ctx.packages.isEmpty ? <RevnixPaywallPackage?>[null] : ctx.packages;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final each in list)
            _container(
              block,
              scope.enter(each, selected),
              revnixEffectiveStyle(block, scope.enter(each, selected)),
              selects: each?.packageId,
            ),
        ],
      );
    }

    // A card that names a package the offering does not reach is dropped rather
    // than rendered with unresolved tags. That includes a negative index,
    // which used to throw and take the whole screen with it.
    final pinned = revnixPinnedPackage(block, ctx.packages);
    if (block.packageIndex != null && pinned == null) return null;
    // A card pinned to a package doubles as its selection target — that is how
    // hand-styled plan rows (a highlighted annual beside a plain monthly)
    // become tappable without a products block. Its children inherit its
    // context, so a tick or a ring inside it answers the selection too. A
    // card that names no package is decoration, stays inert, and passes the
    // scope it sits in straight through.
    final inner = pinned != null ? scope.enter(pinned, selected) : scope;
    return _container(block, inner, style, selects: pinned?.packageId);
  }

  Widget _container(
    CardBlock block,
    RevnixBlockScope scope,
    BlockStyle? style, {
    String? selects,
  }) {
    final gap = style?.gap ?? 10;
    final pairs = _renderPairs(block.children, scope);
    final children = [for (final pair in pairs) pair.$2];

    Widget body;
    switch (block.layout) {
      case 'stack':
        body = Stack(
          clipBehavior: Clip.none,
          children: [
            for (final pair in pairs) _stackChild(pair.$1, pair.$2),
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
          mainAxisAlignment: _mainAxis(style?.justify),
          crossAxisAlignment: _crossAxis(style?.items),
          children: _withGaps(pairs, gap, horizontal: true),
        );
      default:
        // column, and anything unrecognized.
        body = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: _mainAxis(style?.justify),
          crossAxisAlignment: _crossAxis(style?.items, column: true),
          children: _withGaps(pairs, gap, horizontal: false),
        );
    }
    final styled = _styled(style, body);
    if (selects == null) return styled;
    // A selection target gets no pressed opacity: its selectedStyle is the
    // feedback (REV-262 §4).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ctx.onSelect(selects),
      child: styled,
    );
  }

  /// Inserts the gap and honours each child's flex/basis — a carousel card
  /// sized by basis collapses to nothing without it.
  List<Widget> _withGaps(
    List<(BlockStyle?, Widget)> pairs,
    double gap, {
    required bool horizontal,
  }) {
    final out = <Widget>[];
    for (var i = 0; i < pairs.length; i++) {
      if (i > 0) out.add(horizontal ? SizedBox(width: gap) : SizedBox(height: gap));
      final style = pairs[i].$1;
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

    final fill = skipDecoration
        ? const RevnixFill()
        : revnixBlockFill(style.fill, doc, onDiagnostic: ctx.onDiagnostic);
    final borderColor = skipDecoration
        ? null
        : revnixBlockStrokeColor(style.borderColor, doc, onDiagnostic: ctx.onDiagnostic);
    final hasBorder = borderColor != null || (!skipDecoration && style.borderWidth != null);
    final decoration = (!fill.isNone || hasBorder || (!skipDecoration && style.radius != null))
        ? BoxDecoration(
            color: fill.color,
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

    // A gradient fill paints as layers behind the content rather than on the
    // decoration, because CSS `background` can stack several and
    // BoxDecoration.gradient holds one. The padding moves onto the child so
    // those layers still cover it — a CSS background covers its padding box.
    final layers = revnixFillLayers(fill);
    if (layers.isNotEmpty) {
      out = Stack(
        // Passthrough hands the box's own constraints to the content, which is
        // exactly what it got as the Container's direct child — a stretched
        // column must not start shrink-wrapping because a gradient arrived.
        fit: StackFit.passthrough,
        children: [
          ...layers,
          padding == EdgeInsets.zero ? out : Padding(padding: padding, child: out),
        ],
      );
    }

    // A border on `decoration` reserves its width INSIDE the box, insetting the
    // child — which for a gradient fill means the layers stop short of the
    // border and the ground shows through under a translucent one. Painting the
    // same border in FRONT costs no space, so the fill covers its whole box the
    // way a CSS background does.
    final foreground = layers.isEmpty || decoration?.border == null
        ? null
        : BoxDecoration(
            border: decoration!.border,
            borderRadius: decoration.borderRadius,
          );
    out = Container(
      padding: padding == EdgeInsets.zero || layers.isNotEmpty ? null : padding,
      foregroundDecoration: foreground,
      width: style.width?.px,
      height: style.height?.px,
      constraints: style.minHeight == null && style.maxWidth?.px == null
          ? null
          : BoxConstraints(
              minHeight: style.minHeight ?? 0,
              maxWidth: style.maxWidth?.px ?? double.infinity,
            ),
      decoration: foreground == null
          ? decoration
          : BoxDecoration(color: decoration!.color, borderRadius: decoration.borderRadius),
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
    // CSS `translate`, resolved against the block's OWN size. It runs after the
    // margins so it composes with the stack offsets the way the browser does:
    // `left: 50%` pins the edge to the middle, then this pulls the block back
    // by half its own width to centre it. A percentage is a
    // FractionalTranslation (which is defined as a fraction of the child's
    // size); points are a plain Transform. Neither takes the block out of the
    // layout, exactly as CSS `translate` does not.
    final translate = revnixParseTranslate(style.translate);
    if (translate != null) {
      if (!translate.isAbsolute) {
        out = FractionalTranslation(
          translation: Offset(translate.x.fraction, translate.y.fraction),
          child: out,
        );
      }
      if (translate.x.points != 0 || translate.y.points != 0) {
        out = Transform.translate(
          offset: Offset(translate.x.points, translate.y.points),
          child: out,
        );
      }
    } else if (style.translate != null && style.translate!.trim().isNotEmpty) {
      ctx.onDiagnostic?.call('translate not applied: ${style.translate}');
    }
    // The three below stay unpainted on Flutter. Each leaves the block its
    // normal rectangle, its place and its colour — the safe direction — and
    // says so rather than letting a design look wrong for no stated reason.
    if (style.clipPath != null && style.clipPath!.trim().isNotEmpty) {
      ctx.onDiagnostic?.call('clipPath not drawn: ${style.clipPath}');
    }
    if (revnixFillSizeTiles(style.fillSize) &&
        (style.fill?.contains('gradient') ?? false)) {
      ctx.onDiagnostic?.call('fillSize not tiled: ${style.fillSize}');
    }
    if (style.filter != null && style.filter!.trim().isNotEmpty) {
      ctx.onDiagnostic?.call('filter not drawn: ${style.filter}');
    }
    // `textWrap` is deliberately NOT reported, here or on iOS, Android and
    // Unity. It asks for a balanced ragged edge, so ignoring it changes where a
    // headline wraps and never what it says — and half the shipped templates
    // set it, which would put a diagnostic on nearly every render and drown the
    // fallbacks that do mean something.
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
      final color = revnixBlockStrokeColor(parts.sublist(2).join(' '), doc,
          onDiagnostic: ctx.onDiagnostic);
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

/// Paints one parsed CSS gradient.
///
/// Exists for the radial case. Flutter measures [RadialGradient.radius] as a
/// fraction of the box's SHORTEST side, while the descriptor — and the iOS and
/// Android renderers — express it against the LONGEST, so a glow drawn on a
/// tall phone would come out roughly half the size it does everywhere else.
/// The box's own aspect is the only place that conversion can be done, so it
/// happens here rather than in the parser.
class _GradientBox extends StatelessWidget {
  const _GradientBox({required this.gradient});

  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final radial = gradient;
    if (radial is! RadialGradient) {
      return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final shortest = w < h ? w : h;
        final longest = w > h ? w : h;
        final scale = shortest > 0 ? longest / shortest : 1.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: radial.center,
              radius: radial.radius * scale,
              colors: radial.colors,
              stops: radial.stops,
              tileMode: radial.tileMode,
            ),
          ),
        );
      },
    );
  }
}

/// Does this tree author a dismiss affordance that is CERTAIN to render?
///
/// The renderer draws its own close button only when this is false, so a design
/// published before close existed becomes dismissible without being
/// re-authored, and a design that DOES author a close chip never shows two. The
/// same predicate exists in every Revnix SDK — keep them identical.
bool revnixHasCloseAction(List<PaywallBlock> blocks) => blocks.any((block) {
      // A block with `visibility` set is drawn only in one selection state,
      // so a close authored on it MIGHT not appear (REV-262 §1). Same rule as
      // the conditional containers below: it does not count.
      if (block.visibility != null) return false;
      if (block is TextBlock) return block.action == BlockAction.close;
      if (block is ImageBlock) return block.action == BlockAction.close;
      if (block is ButtonBlock) return block.action == BlockAction.close;
      // Conditional containers are deliberately not searched: a `repeat` card
      // renders once per package (none, when the offering is empty) and a
      // `packageIndex` card is hidden when the offering does not reach that
      // index, so a close authored inside one MIGHT not appear. Counting it
      // would suppress the fallback and leave the customer with no way out —
      // the exact bug this feature exists to fix.
      if (block is CardBlock) {
        return block.repeat == null &&
            block.packageIndex == null &&
            revnixHasCloseAction(block.children);
      }
      return false;
    });

/// A `button` block (REV-262 §4).
///
/// Draws at 80% opacity while the finger is down and back to 100% on release;
/// while [loading] it ignores taps, hides its label and centres a spinner in
/// [spinnerColor] in its place, keeping its size and fill so the layout does
/// not jump. Announced as a button, disabled while loading.
class RevnixBlockButton extends StatefulWidget {
  const RevnixBlockButton({
    super.key,
    required this.onTap,
    required this.label,
    required this.fill,
    required this.spinnerColor,
    this.radius,
    this.height,
    this.padding = EdgeInsets.zero,
    this.loading = false,
  });

  final VoidCallback onTap;
  final Widget label;
  final RevnixFill fill;
  final Color spinnerColor;
  final BorderRadius? radius;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool loading;

  /// The opacity of a pressed button — the same weight as the dashboard's
  /// `:active { opacity: .8 }` and UGUI's ColorTint pressed 0.8.
  static const double pressedOpacity = 0.8;

  @override
  State<RevnixBlockButton> createState() => _RevnixBlockButtonState();
}

class _RevnixBlockButtonState extends State<RevnixBlockButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(RevnixBlockButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A press that turned into a purchase must not leave the button dimmed
    // under its spinner.
    if (widget.loading && !oldWidget.loading) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.loading;
    return Semantics(
      button: true,
      enabled: !loading,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: loading ? null : (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: loading ? null : widget.onTap,
        child: Opacity(
          opacity: _pressed && !loading ? RevnixBlockButton.pressedOpacity : 1,
          child: RevnixFillBox(
            fill: widget.fill,
            radius: widget.radius,
            child: Container(
              height: widget.height,
              alignment: Alignment.center,
              padding: widget.padding,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The label keeps its box while hidden, so the button keeps
                  // its size; the spinner is centred over that box.
                  Opacity(opacity: loading ? 0 : 1, child: widget.label),
                  if (loading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.spinnerColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scroll physics for a paywall (REV-262 §3): the platform's own feel while
/// the content overflows the viewport, and no drag at all — so no bounce and
/// no overscroll — while it fits. Layered over the ambient physics, so an iOS
/// list still bounces at its ends when there IS something to scroll.
class RevnixPaywallScrollPhysics extends ScrollPhysics {
  const RevnixPaywallScrollPhysics({super.parent});

  @override
  RevnixPaywallScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      RevnixPaywallScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      position.maxScrollExtent > position.minScrollExtent &&
      super.shouldAcceptUserOffset(position);
}
