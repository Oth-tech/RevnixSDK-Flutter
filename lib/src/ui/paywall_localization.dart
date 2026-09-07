// REV-271: paywall localization. A designed paywall carries ONE tree plus a
// side table of translated strings — never one tree per language — so styles,
// layout and block ids are shared and only words differ.
//
// Selection happens HERE, at render, rather than server-side at resolve. The
// resolution is cached on the device, so a locale chosen by the server would
// pin a cached paywall to whatever language it was fetched in: change the
// phone's language and the old copy would keep rendering until the cache
// expired, and offline it would never change at all.
//
// Mirrored across all six Revnix SDKs — keep the key scheme, the fallback
// chain and the field list identical.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'paywall_blocks.dart';

/// The translations published with a document.
@immutable
class PaywallLocalization {
  const PaywallLocalization({this.defaultLocale, this.tables = const {}});

  /// The language the tree's own copy is written in. Never a key in [tables].
  final String? defaultLocale;

  /// BCP-47 tag → (`<blockId>.<path>` → translated string).
  final Map<String, Map<String, String>> tables;

  bool get isEmpty => tables.isEmpty;

  /// Reads `defaultLocale` / `locales` off a raw block document. A malformed
  /// table costs the TRANSLATIONS, never the paywall — the same forgiveness
  /// every other optional field in the parser gets.
  static PaywallLocalization parse(Object? value) {
    if (value is! Map) return const PaywallLocalization();
    final defaultLocale =
        value['defaultLocale'] is String ? value['defaultLocale'] as String : null;
    final raw = value['locales'];
    if (raw is! Map) return PaywallLocalization(defaultLocale: defaultLocale);
    final tables = <String, Map<String, String>>{};
    raw.forEach((tag, table) {
      // Normalized on the way IN so a hand-written "es_mx" in the catalog
      // still matches a device reporting "es-MX".
      final normalized = revnixNormalizeLocale(tag is String ? tag : null);
      if (normalized == null || table is! Map) return;
      final strings = <String, String>{};
      table.forEach((key, cell) {
        if (key is String && cell is String) strings[key] = cell;
      });
      if (strings.isNotEmpty) tables[normalized] = strings;
    });
    return PaywallLocalization(defaultLocale: defaultLocale, tables: tables);
  }
}

/// BCP-47, hyphenated: "es_MX" and "es-mx" both normalize to "es-MX". Applied
/// to authored tags and to the device's own locale alike, so the two can never
/// miss each other over punctuation or case. Null for anything that is not a
/// language tag, which keeps junk out of the lookup instead of into it.
String? revnixNormalizeLocale(String? tag) {
  if (tag == null) return null;
  final parts =
      tag.trim().replaceAll('_', '-').split('-').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final language = parts.first.toLowerCase();
  if (language.length < 2 ||
      language.length > 3 ||
      !RegExp(r'^[a-z]+$').hasMatch(language)) {
    return null;
  }
  final rest = <String>[];
  for (final part in parts.skip(1)) {
    // Region subtags are uppercase ("MX", "419"), scripts title case ("Hans");
    // anything else is a variant and stays lowercase. A subtag outside
    // BCP-47's shapes makes the WHOLE tag junk rather than passing through —
    // otherwise a device reporting "es-!!" would look up a language.
    if (part.length == 2 && RegExp(r'^[A-Za-z]+$').hasMatch(part)) {
      rest.add(part.toUpperCase());
    } else if (part.length == 3 && RegExp(r'^[0-9]+$').hasMatch(part)) {
      rest.add(part);
    } else if (part.length == 4 && RegExp(r'^[A-Za-z]+$').hasMatch(part)) {
      rest.add(part[0].toUpperCase() + part.substring(1).toLowerCase());
    } else if (part.length >= 5 &&
        part.length <= 8 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(part)) {
      rest.add(part.toLowerCase());
    } else {
      return null;
    }
  }
  return [language, ...rest].join('-');
}

String _baseLanguage(String tag) => tag.split('-').first;

/// Which tables to consult, most specific first.
///
/// "es-MX" on a paywall translated into "es" reads the "es" table: a regional
/// variant that was never authored falls back to its language rather than to
/// the source, which is the difference between a Mexican customer reading
/// Spanish and reading English. The authored tree is the last resort and is
/// deliberately NOT in this chain — the lookup falls through to it.
List<String> revnixLocaleChain(
  Iterable<String> available,
  String? locale,
  String? defaultLocale,
) {
  final chain = <String>[];
  void push(String? tag) {
    if (tag != null && available.contains(tag) && !chain.contains(tag)) {
      chain.add(tag);
    }
  }

  final wanted = revnixNormalizeLocale(locale);
  if (wanted != null) {
    push(wanted);
    push(_baseLanguage(wanted));
    // "es" asked for, only "es-MX" authored: one regional table beats the
    // source language, and the first SORTED match keeps the choice
    // deterministic across devices rather than map-order dependent.
    if (chain.isEmpty) {
      final language = _baseLanguage(wanted);
      final regional = available.where((t) => _baseLanguage(t) == language).toList()
        ..sort();
      if (regional.isNotEmpty) push(regional.first);
    }
  }
  push(revnixNormalizeLocale(defaultLocale));
  return chain;
}

/// The device's language. `PlatformDispatcher.locale` is what Flutter itself
/// localizes to, so a paywall matching it matches the rest of the app.
String? revnixDeviceLocale() {
  try {
    return ui.PlatformDispatcher.instance.locale.toLanguageTag();
  } catch (_) {
    return null;
  }
}

PaywallBlock _localizeBlock(PaywallBlock block, String Function(String, String) lookup) {
  String at(String path, String authored) => lookup('${block.id}.$path', authored);
  String? opt(String path, String? authored) =>
      authored == null ? null : at(path, authored);
  if (block is TextBlock) {
    return TextBlock(
      id: block.id,
      text: at('text', block.text),
      style: block.style,
      selectedStyle: block.selectedStyle,
      visibility: block.visibility,
      action: block.action,
    );
  }
  if (block is ButtonBlock) {
    return ButtonBlock(
      id: block.id,
      label: at('label', block.label),
      style: block.style,
      selectedStyle: block.selectedStyle,
      visibility: block.visibility,
      action: block.action,
    );
  }
  if (block is ListBlock) {
    var index = -1;
    return ListBlock(
      id: block.id,
      items: block.items.map((item) {
        index++;
        return BlockListItem(
          icon: item.icon,
          title: at('items.$index.title', item.title),
          description: opt('items.$index.description', item.description),
        );
      }).toList(),
      iconColor: block.iconColor,
      style: block.style,
      selectedStyle: block.selectedStyle,
      visibility: block.visibility,
    );
  }
  if (block is ProductsBlock) {
    return ProductsBlock(
      id: block.id,
      direction: block.direction,
      titleTpl: opt('titleTpl', block.titleTpl),
      priceTpl: opt('priceTpl', block.priceTpl),
      highlightSub: opt('highlightSub', block.highlightSub),
      badgeText: opt('badgeText', block.badgeText),
      cardStyle: block.cardStyle,
      highlightStyle: block.highlightStyle,
      style: block.style,
      selectedStyle: block.selectedStyle,
      visibility: block.visibility,
    );
  }
  if (block is CardBlock) {
    return CardBlock(
      id: block.id,
      layout: block.layout,
      repeat: block.repeat,
      packageIndex: block.packageIndex,
      columns: block.columns,
      gridColumns: block.gridColumns,
      children: block.children.map((c) => _localizeBlock(c, lookup)).toList(),
      style: block.style,
      selectedStyle: block.selectedStyle,
      visibility: block.visibility,
    );
  }
  return block;
}

/// Returns the document with every string swapped for [locale]'s.
///
/// Applied ONCE before rendering rather than at each text node: the widgets
/// then need no localization awareness at all, and the six SDKs cannot drift
/// on which fields are translatable. Returns [doc] untouched when nothing
/// applies, so an untranslated paywall allocates nothing.
///
/// `{price}` and the other copy tags survive, because they are resolved AFTER
/// this on the localized string — "Solo {price} al mes" works.
PaywallBlockDoc revnixLocalizeDoc(PaywallBlockDoc doc, String? locale) {
  final localization = doc.localization;
  if (localization.isEmpty) return doc;
  final chain =
      revnixLocaleChain(localization.tables.keys, locale, localization.defaultLocale);
  if (chain.isEmpty) return doc;
  String lookup(String key, String authored) {
    for (final tag in chain) {
      final value = localization.tables[tag]?[key];
      // An empty translation means "not translated", never "render nothing":
      // a blank CTA is a dead paywall, and export/import round-trips leave
      // empty cells behind for every untouched row.
      if (value != null && value.isNotEmpty) return value;
    }
    return authored;
  }

  return PaywallBlockDoc(
    version: doc.version,
    layout: doc.layout,
    background: doc.background,
    backgroundSpec: doc.backgroundSpec,
    textColor: doc.textColor,
    accent: doc.accent,
    accentInk: doc.accentInk,
    fontFamily: doc.fontFamily,
    blocks: doc.blocks.map((b) => _localizeBlock(b, lookup)).toList(),
    localization: localization,
  );
}
