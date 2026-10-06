import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

/// REV-271 designed-paywall localization.
///
/// The dashboard writes the table; this SDK reads it. These are the parity
/// contract — the same cases run in revnix-app and in every other Revnix SDK,
/// so a paywall translated in the builder resolves identically everywhere.
///
/// The guarantees that matter are the ones a shipped app cannot be patched out
/// of: an untranslated string must never render blank, a regional locale must
/// reach its language, and the overlay must disturb nothing but words.
void main() {
  const source = '''
    {
      "version": 1, "background": "#101014", "textColor": "#F5F7FA",
      "accent": "#6478ff", "accentInk": "#0B0D10",
      "defaultLocale": "en",
      "locales": {
        "es": {
          "hed.text": "Desbloquea Pro",
          "feats.items.0.title": "Modo sin conexión",
          "plans.priceTpl": "{price}/mes",
          "cta.label": "Continuar"
        },
        "pt_br": { "hed.text": "Desbloqueie o Pro" }
      },
      "blocks": [
        { "id": "hed", "type": "text", "text": "Unlock Pro", "style": { "fontSize": 28 } },
        { "id": "feats", "type": "list", "items": [
            { "title": "Offline mode", "description": "Take it anywhere" },
            { "title": "No ads" } ] },
        { "id": "wrap", "type": "card", "layout": "column", "children": [
            { "id": "plans", "type": "products", "titleTpl": "{title}", "priceTpl": "{price}/mo" },
            { "id": "cta", "type": "button", "label": "Continue" } ] }
      ]
    }
  ''';

  PaywallBlockDoc doc([String json = source]) {
    final parsed = PaywallBlockDoc.parse(jsonDecode(json));
    expect(parsed, isNotNull);
    return parsed!;
  }

  group('locale tags', () {
    test('normalize to one canonical form', () {
      expect(revnixNormalizeLocale('es_mx'), 'es-MX');
      expect(revnixNormalizeLocale(' PT-br '), 'pt-BR');
      expect(revnixNormalizeLocale('zh-hans-cn'), 'zh-Hans-CN');
      expect(revnixNormalizeLocale('es-419'), 'es-419');
      // Junk must not become a language nobody can select.
      expect(revnixNormalizeLocale('english'), isNull);
      expect(revnixNormalizeLocale(''), isNull);
    });

    test('authored tags are normalized on parse', () {
      // "pt_br" was hand-written in the catalog; a device reporting "pt-BR"
      // must still find it.
      final out = revnixLocalizeDoc(doc(), 'pt-BR');
      expect((out.blocks[0] as TextBlock).text, 'Desbloqueie o Pro');
    });
  });

  group('fallback chain', () {
    test('a regional locale falls back to its language, not to English', () {
      expect(revnixLocaleChain(['es', 'fr'], 'es-MX', 'en'), ['es']);
      // Deterministic across devices: map order must not decide what a
      // customer reads.
      expect(revnixLocaleChain(['es-MX', 'es-AR'], 'es', null), ['es-AR']);
      expect(revnixLocaleChain(['es'], 'ja', null), isEmpty);
    });
  });

  group('applying a language', () {
    test('swaps strings at every depth and keeps copy tags', () {
      final out = revnixLocalizeDoc(doc(), 'es-MX');
      expect((out.blocks[0] as TextBlock).text, 'Desbloquea Pro');
      final card = out.blocks[2] as CardBlock;
      expect((card.children[1] as ButtonBlock).label, 'Continuar');
      final products = card.children[0] as ProductsBlock;
      // The tag survives translation, so {price} still resolves after it.
      expect(products.priceTpl, '{price}/mes');
      expect(products.titleTpl, '{title}');
    });

    test('untranslated strings keep the authored copy', () {
      final list = revnixLocalizeDoc(doc(), 'es').blocks[1] as ListBlock;
      expect(list.items[0].title, 'Modo sin conexión');
      // Same item, untranslated description — and a wholly untranslated row.
      expect(list.items[0].description, 'Take it anywhere');
      expect(list.items[1].title, 'No ads');
    });

    test('an empty translation means untranslated, not blank', () {
      // An export/import round-trip leaves empty cells everywhere; honouring
      // them would ship a paywall with no CTA label.
      final blanked = source.replaceAll('"cta.label": "Continuar"', '"cta.label": ""');
      final card = revnixLocalizeDoc(doc(blanked), 'es').blocks[2] as CardBlock;
      expect((card.children[1] as ButtonBlock).label, 'Continue');
    });

    test('only words change', () {
      final original = doc();
      final out = revnixLocalizeDoc(original, 'es');
      expect(out.accent, original.accent);
      expect(out.background, original.background);
      expect(out.blocks[0].id, 'hed');
      expect((out.blocks[0] as TextBlock).style?.fontSize, 28);
    });

    test('an unmatched locale renders the authored document', () {
      final out = revnixLocalizeDoc(doc(), 'ja');
      expect((out.blocks[0] as TextBlock).text, 'Unlock Pro');
    });

    test('a malformed table costs the translations, never the paywall', () {
      const broken = '''
        {"version":1,"background":"#000","textColor":"#fff","accent":"#6478ff",
         "accentInk":"#fff","locales":"nonsense",
         "blocks":[{"id":"hed","type":"text","text":"Unlock Pro"}]}
      ''';
      final parsed = doc(broken);
      expect(parsed.localization.isEmpty, isTrue);
      expect((revnixLocalizeDoc(parsed, 'es').blocks[0] as TextBlock).text, 'Unlock Pro');
    });

    test('defaultLocale on the output is the locale actually resolved', () {
      final out = revnixLocalizeDoc(doc(), 'es-MX');
      expect(out.localization.defaultLocale, 'es');
    });
  });

  group('link labels', () {
    test('resolves a language and its regional variants', () {
      expect(revnixLinkLabels('ur').restore, 'بحال کریں');
      expect(revnixLinkLabels('ur-PK').terms, 'شرائط');
    });

    test('Mandarin picks traditional script for TW/HK, simplified elsewhere', () {
      expect(revnixLinkLabels('zh-Hant-TW').restore, '恢復購買');
      expect(revnixLinkLabels('zh-TW').restore, '恢復購買');
      expect(revnixLinkLabels('zh-HK').restore, '恢復購買');
      expect(revnixLinkLabels('zh-Hans-HK').restore, '恢复购买');
      expect(revnixLinkLabels('zh-CN').restore, '恢复购买');
      expect(revnixLinkLabels('zh').restore, '恢复购买');
    });

    test('legacy and regional tags map through aliases', () {
      expect(revnixLinkLabels('iw').restore, 'שחזור');
      expect(revnixLinkLabels('no').restore, 'Gjenopprett');
      expect(revnixLinkLabels('pt_BR').restore, 'Restaurar');
    });

    test('falls back to English for anything unknown', () {
      expect(revnixLinkLabels('xx').restore, 'Restore');
      expect(revnixLinkLabels(null).restore, 'Restore');
      expect(revnixLinkLabels('').restore, 'Restore');
    });
  });

  group('locale override', () {
    tearDown(() => RevnixClient.setLocale(null));

    test('setLocale forces the device locale', () {
      RevnixClient.setLocale('ur');
      expect(revnixDeviceLocale(), 'ur');
    });

    test('clearing with null or empty restores the device locale', () {
      RevnixClient.setLocale('ur');
      RevnixClient.setLocale(null);
      expect(revnixDeviceLocale(), isNot('ur'));
      RevnixClient.setLocale('ur');
      RevnixClient.setLocale('');
      expect(revnixDeviceLocale(), isNot('ur'));
    });
  });
}
