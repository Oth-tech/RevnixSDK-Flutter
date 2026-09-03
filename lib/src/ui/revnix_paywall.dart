/// RevnixPaywall — renders a published [PaywallConfig] exactly as the
/// dashboard paywall-builder previews it (`PaywallPhonePreview.tsx` in
/// revnix-app is the reference renderer; the React Native port lives in
/// `revnix-sdk/src/ui/RevnixPaywall.tsx` — keep the three in lockstep). The
/// config decides template, copy, accent, badge, highlight, and hero image;
/// the app supplies package titles/prices (from StoreKit / Play Billing) and
/// the purchase handlers, so the display never disagrees with the charge.
///
/// `template` is a LAYOUT id. "focus" | "feature-list" | "minimal" are the
/// original three and render byte-identically to the other SDK ports; the
/// newer layouts (hero, timeline, plans, feature-grid, offer, reveal) are
/// distinct screen structures the dashboard's template gallery presets over.
/// An unrecognized template (config published by a newer dashboard) falls
/// back to the classic structure instead of rendering nothing.
///
/// Pure Dart over Flutter's own widgets — no platform channels, no new pub
/// dependencies.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../revnix_client.dart';
import 'paywall_blocks.dart';

/// One purchasable row. [priceLabel] must come from the store (localized).
@immutable
class RevnixPaywallPackage {
  const RevnixPaywallPackage({
    required this.packageId,
    required this.title,
    required this.priceLabel,
    this.period,
    this.amountMinor,
    this.currency,
    this.productId,
  });

  final String packageId;
  final String title;
  final String priceLabel;

  /// Renewal cycle from the product ("annual", "monthly", "weekly", …). Drives
  /// the `{period}` / `{period_short}` tags on a designed paywall; null for
  /// lifetime and one-time products.
  final String? period;

  /// The store's price in MINOR units, with its currency — what
  /// `{price_per_month}` and `{save_percent}` are computed from. Omit them and
  /// those tags stay visible rather than resolving to a wrong number; see
  /// [revnixMinorUnits] before converting from major units.
  final int? amountMinor;
  final String? currency;

  /// REV-263: the catalog product behind this package. Only telemetry reads it
  /// — a `selected` or `purchaseStarted` report names the plan the way the rest
  /// of the ledger does. Optional: without it the interaction is still
  /// reported, just with no plan attached.
  final String? productId;
}

/// Colors the paywall renders with. Every field is optional — a null field
/// falls back to the base scheme the config's `mode` picks ([dark] unless the
/// dashboard set `mode: "light"`), so a partial override layers on top of
/// either scheme. The palettes mirror the dashboard preview chrome (kept in
/// lockstep with PaywallPhonePreview SCREEN_PALETTES).
class RevnixPaywallTheme {
  const RevnixPaywallTheme({
    this.background,
    this.textPrimary,
    this.textSecondary,
    this.textFaint,
    this.border,
    this.accentInk,
  });

  final Color? background;
  final Color? textPrimary;
  final Color? textSecondary;
  final Color? textFaint;
  final Color? border;

  /// Text color on accent-filled surfaces (CTA, badge).
  final Color? accentInk;

  /// Default palette — a fixed dark screen, as the dashboard previews it.
  static const RevnixPaywallTheme dark = RevnixPaywallTheme(
    background: Color(0xFF0F1116),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9AA0A8),
    textFaint: Color(0xFF6B7078),
    border: Color(0xFF2A2E36),
    accentInk: Color(0xFF0A0B0D),
  );

  /// Base theme when the dashboard config sets `mode: "light"`.
  static const RevnixPaywallTheme light = RevnixPaywallTheme(
    background: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF16181D),
    textSecondary: Color(0xFF5B6068),
    textFaint: Color(0xFF9AA0A8),
    border: Color(0xFFE2E5EA),
    accentInk: Color(0xFFFFFFFF),
  );
}

/// Accent used when the config carries none ("#6478ff").
const Color _defaultAccent = Color(0xFF6478FF);

// Currency symbols the anchor-price guard recognizes (majors; a symbol-less
// anchor can't be judged and renders as entered).
final RegExp _currencySymbol = RegExp(r'[$€£¥₹₩₽₺₫₪฿₴₦₱]');

// Soft card surface used by the feature-grid / reveal / review blocks. Not
// part of the public theme — derived from the config's mode, in lockstep
// with the dashboard preview's SCREEN_PALETTES.card.
const Color _cardBgDark = Color(0xFF181B22);
const Color _cardBgLight = Color(0xFFF4F5F7);

/// JS-style truthiness for config strings: absent and empty both mean "not
/// set", matching the React Native renderer's `value ?` checks.
bool _filled(String? value) => value != null && value.isNotEmpty;

/// Parses a dashboard accent like "#6478ff" (also bare / 3-digit hex);
/// anything unparseable falls back, never throws on a bad config.
Color _hexColor(String? hex, Color fallback) {
  if (hex == null) return fallback;
  var digits = hex.startsWith('#') ? hex.substring(1) : hex;
  if (digits.length == 3) {
    digits = digits.split('').map((c) => '$c$c').join();
  }
  if (digits.length != 6) return fallback;
  final value = int.tryParse(digits, radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}

/// JS `String(rating)`: integral doubles print without the ".0" (5.0 → "5"),
/// so the star row's numeric label matches the other renderers.
String _ratingLabel(double rating) =>
    rating == rating.roundToDouble() ? rating.round().toString() : rating.toString();

/// Fully-resolved palette: the config's base scheme with the host override
/// layered on top, non-null so the render code stays clean.
class _Palette {
  _Palette(RevnixPaywallTheme base, RevnixPaywallTheme? override)
      : background = override?.background ?? base.background!,
        textPrimary = override?.textPrimary ?? base.textPrimary!,
        textSecondary = override?.textSecondary ?? base.textSecondary!,
        textFaint = override?.textFaint ?? base.textFaint!,
        border = override?.border ?? base.border!,
        accentInk = override?.accentInk ?? base.accentInk!;

  final Color background;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;
  final Color border;
  final Color accentInk;
}

/// Renders a published [PaywallConfig] as a full paywall screen.
///
/// ```dart
/// RevnixPaywall(
///   config: resolution.paywall!.config,
///   packages: [
///     RevnixPaywallPackage(
///       packageId: 'monthly',
///       title: 'Monthly',
///       priceLabel: product.price, // the store's localized price
///     ),
///   ],
///   onPurchase: (packageId) => buy(packageId),
/// )
/// ```
///
/// Selection is controlled ([selectedPackageId] + [onSelectPackage]) or
/// internal; the initial selection is the config's highlight package, else
/// the first package. The "minimal" template shows only the highlighted
/// package.
class RevnixPaywall extends StatefulWidget {
  const RevnixPaywall({
    super.key,
    required this.config,
    required this.packages,
    required this.onPurchase,
    this.selectedPackageId,
    this.onSelectPackage,
    this.loading = false,
    this.onRestore,
    this.onTerms,
    this.onPrivacy,
    this.onClose,
    this.onOpenUrl,
    this.theme,
    this.client,
    this.placementKey,
    this.paywallId,
    this.disableViewTracking = false,
    this.onDiagnostic,
  });

  final PaywallConfig config;
  final List<RevnixPaywallPackage> packages;

  /// Called with the selected packageId when the CTA is pressed.
  final void Function(String packageId) onPurchase;

  /// Controlled selection; omit to let the paywall manage it (initial
  /// selection is the config's highlight package, else the first package).
  final String? selectedPackageId;
  final void Function(String packageId)? onSelectPackage;

  /// Renders a spinner in the CTA and disables purchasing.
  final bool loading;

  final VoidCallback? onRestore;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;

  /// Dismissal (REV-252). The HOST performs it — only the app knows whether
  /// that means popping a route, closing a dialog, or advancing onboarding —
  /// so the paywall never dismisses itself. Omit it and no close is drawn at
  /// all: a dead close button is worse than none. Passing [client] as well
  /// reports `paywall.closed` against this display's own view id.
  final VoidCallback? onClose;

  /// Opens a dashboard-configured footer URL ([PaywallFooter.termsUrl] /
  /// [PaywallFooter.privacyUrl]). Explicit [onTerms]/[onPrivacy] handlers
  /// win over config URLs — the app knows best how to open its own legal
  /// pages (in-app browser etc.). The plugin deliberately adds no
  /// url_launcher dependency, so when only a config URL exists the URL is
  /// handed to this callback for the host to open; without it such links
  /// render inert.
  final void Function(String url)? onOpenUrl;

  /// Partial palette override, layered on the scheme `config.mode` picks.
  final RevnixPaywallTheme? theme;

  /// When given, the paywall reports one paywall.viewed per mount (REV-094)
  /// — the analytics funnel's "Paywall displayed" stage. Pass
  /// [RevnixClient.instance] once configured.
  final RevnixClient? client;

  /// Placement/paywall attribution attached to the view report.
  final String? placementKey;
  final String? paywallId;

  /// Opt out of the automatic view report while still passing [client].
  final bool disableViewTracking;

  /// Reports a paint string the block renderer could not read — a `fill`,
  /// border or text colour in a form this SDK version does not understand.
  ///
  /// Local only: nothing is sent anywhere. The screen still draws (an
  /// unreadable fill falls back to a colour from the design rather than to
  /// black), so this is the only way to learn that a paywall is rendering
  /// approximately. [RevnixClient.diagnostics] carries the client's own
  /// swallowed failures and is a separate stream; render diagnostics are
  /// synchronous and belong to the widget that drew them.
  final void Function(RevnixDiagnostic diagnostic)? onDiagnostic;

  @override
  State<RevnixPaywall> createState() => _RevnixPaywallState();
}

class _RevnixPaywallState extends State<RevnixPaywall> {
  String? _internalSelected;

  @override
  void initState() {
    super.initState();
    // One view per mount: a re-shown paywall (new State) is a genuine new
    // display; rebuilds are not. Fire-and-forget — a lost beacon must never
    // surface in the purchase UI.
    final client = widget.client;
    if (client != null && !widget.disableViewTracking) {
      final report = client
          .logPaywallShown(
            placementKey: widget.placementKey,
            paywallId: widget.paywallId,
          )
          .then<String?>((id) => id, onError: (_) => null);
      _viewReport = report;
      // Nothing on screen depends on the view id, so the future is held rather
      // than awaited into state — rebuilding the paywall the instant its view
      // is recorded would be a pointless frame.
      unawaited(report);
      // REV-263: an offering with nothing to sell is the one failure the
      // widget can see by itself, and the one most worth knowing about — the
      // paywall painted, the customer could not buy.
      if (widget.packages.isEmpty) {
        _report(
          RevnixPaywallEvent.error,
          code: 'no_products',
          message: 'paywall displayed with no packages',
        );
      }
    }
  }

  /// The in-flight view beacon (REV-252). The close AWAITS this rather than
  /// reading an id off a field: the id only exists once the request returns,
  /// and a customer who dismisses in that window would otherwise report a
  /// close with no id and lose the pairing.
  Future<String?>? _viewReport;

  /// Runs the host's dismissal, reporting `paywall.closed` alongside it. The
  /// host's callback runs FIRST and unconditionally: the beacon is
  /// best-effort, and an analytics failure must never be able to trap the
  /// customer on the screen.
  void _close() {
    widget.onClose?.call();
    final client = widget.client;
    final report = _viewReport;
    if (client == null || widget.disableViewTracking || report == null) return;
    // Awaiting the view beacon is what keeps the pair intact when the customer
    // dismisses before it lands. It has usually resolved long ago, in which
    // case this continues on the next microtask.
    unawaited(report.then((viewId) {
      if (viewId == null) return null;
      return client
          .logPaywallClosed(
            viewId,
            placementKey: widget.placementKey,
            paywallId: widget.paywallId,
          )
          .then((_) {}, onError: (_) {});
    }, onError: (_) {}));
  }

  // ——— REV-263: the interaction vocabulary ———
  //
  // The widget reports what it genuinely OBSERVES: the selection change, the
  // CTA press, the restore press, and an offering that arrived with nothing to
  // sell. It never reports the purchase OUTCOME — the store call happens in
  // the host, so only the host knows whether the customer cancelled at the
  // sheet or the payment was refused. Report those with
  // `client.logPaywallEvent(...)` from your own in_app_purchase handling.
  void _report(
    RevnixPaywallEvent event, {
    String? productId,
    String? code,
    String? message,
    String? eventId,
  }) {
    final client = widget.client;
    final report = _viewReport;
    if (client == null || widget.disableViewTracking || report == null) return;
    // Awaiting the view beacon for the same reason the close does: an
    // interaction reported before the display id exists could not be tied to
    // the display it happened on.
    unawaited(report.then((viewId) {
      if (viewId == null) return null;
      return client
          .logPaywallEvent(
            event,
            viewId,
            placementKey: widget.placementKey,
            paywallId: widget.paywallId,
            productId: productId,
            code: code,
            message: message,
            eventId: eventId == null ? null : '$viewId:$eventId',
          )
          .then((_) {}, onError: (_) {});
    }, onError: (_) {}));
  }

  /// The catalog product behind a package, so a report names the plan the way
  /// the rest of the ledger does. Null when the offering did not carry one —
  /// reporting the package id instead would look like a product that does not
  /// exist.
  String? _productIdFor(String packageId) {
    for (final pkg in widget.packages) {
      if (pkg.packageId == packageId) return pkg.productId;
    }
    return null;
  }

  /// Rises per CTA press, so a retry after a failure is its own occurrence
  /// rather than a duplicate of the first try.
  int _purchaseAttempts = 0;

  /// Every CTA path routes through here, so the start report can never be
  /// wired on one render path and forgotten on the other.
  void _purchase(String packageId) {
    _purchaseAttempts += 1;
    _report(
      RevnixPaywallEvent.purchaseStarted,
      productId: _productIdFor(packageId),
      eventId: 'buy:$_purchaseAttempts',
    );
    widget.onPurchase(packageId);
  }

  /// Restore — the report rides along with the host's handler.
  void _restore() {
    _report(RevnixPaywallEvent.restore);
    widget.onRestore?.call();
  }

  void _select(String packageId) {
    setState(() => _internalSelected = packageId);
    // One report per (display, package): a customer toggling monthly → yearly
    // → monthly weighed two plans, not three, and the server's default key
    // (the viewId alone) would keep only the first.
    _report(
      RevnixPaywallEvent.selected,
      productId: _productIdFor(packageId),
      eventId: 'sel:$packageId',
    );
    widget.onSelectPackage?.call(packageId);
  }

  /// The designed-paywall path. The document carries its own palette, so the
  /// classic theme and the `template` layout play no part here.
  Widget _buildBlocks(PaywallBlockDoc doc) {
    final shown = widget.packages;
    // The one selection rule every renderer shares (REV-262 §1): the host's
    // choice when it names an offered package, else the customer's tap, else
    // the config highlight, else the first package.
    final selectedId = revnixResolveSelectedPackageId(
      shown,
      hostSelected: widget.selectedPackageId,
      internalSelected: _internalSelected,
      highlight: widget.config.highlightPackageId,
    );

    return RevnixPaywallBlockScreen(
      ctx: BlockRenderContext(
        doc: doc,
        packages: shown,
        selectedPackageId: selectedId,
        // The renderer draws the wait — spinner in place of the label, taps
        // ignored — rather than the host swallowing the tap silently.
        loading: widget.loading,
        heroImageUrl: widget.config.heroImageUrl,
        footerTermsUrl: widget.config.footer?.termsUrl,
        footerPrivacyUrl: widget.config.footer?.privacyUrl,
        onPurchase: (id) {
          if (!widget.loading) _purchase(id);
        },
        onSelect: _select,
        onRestore: widget.onRestore == null ? null : _restore,
        onTerms: widget.onTerms,
        onPrivacy: widget.onPrivacy,
        onClose: widget.onClose == null ? null : _close,
        onDiagnostic: widget.onDiagnostic == null
            ? null
            : (message) => widget.onDiagnostic!(
                  RevnixDiagnostic(op: 'paywall.render', message: message),
                ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    // Precedence: a designed paywall (`config.blocks`) wins over the classic
    // layouts below, which stay the fallback for every paywall published
    // before the block builder — so anything already live renders unchanged.
    final blockDoc = PaywallBlockDoc.parse(config.blocks);
    if (blockDoc != null) return _buildBlocks(blockDoc);

    // Base scheme comes from the dashboard config (mode: dark|light, absent =
    // dark for legacy configs); the host's explicit theme override wins on top.
    final isLight = config.mode == 'light';
    final base = isLight ? RevnixPaywallTheme.light : RevnixPaywallTheme.dark;
    final t = _Palette(base, widget.theme);
    final accent = _hexColor(config.accent, _defaultAccent);
    // The RN renderer's `${accent}26` / `${accent}40` hex-alpha tints.
    final accentTint = accent.withAlpha(0x26); // 15% — soft fills
    final accentSoft = accent.withAlpha(0x40); // 25% — rails, inactive dots
    final cardBg = isLight ? _cardBgLight : _cardBgDark;
    final layout = config.template;

    // Same template semantics as the dashboard preview: "minimal" shows only
    // the highlighted package; feature bullets render on the feature layouts.
    final shown = layout == 'minimal' && _filled(config.highlightPackageId)
        ? widget.packages
            .where((p) => p.packageId == config.highlightPackageId)
            .toList()
        : widget.packages;

    String? fallbackSelected;
    for (final p in shown) {
      if (p.packageId == config.highlightPackageId) {
        fallbackSelected = p.packageId;
        break;
      }
    }
    fallbackSelected ??= shown.isEmpty ? null : shown.first.packageId;
    final selectedId = widget.selectedPackageId ??
        (_internalSelected != null &&
                shown.any((p) => p.packageId == _internalSelected)
            ? _internalSelected
            : fallbackSelected);

    // Footer links are dashboard-configured (config.footer); a legacy config
    // without the field keeps the original always-on footer. Explicit host
    // handlers win over config URLs; the URL (via onOpenUrl) is the
    // no-handler fallback.
    final footer = config.footer;
    VoidCallback? openUrl(String? url) {
      final onOpenUrl = widget.onOpenUrl;
      return _filled(url) && onOpenUrl != null ? () => onOpenUrl(url!) : null;
    }

    final footerItems = <({String label, VoidCallback? onTap})>[
      if (footer?.showRestore ?? true)
        (label: 'Restore', onTap: widget.onRestore == null ? null : _restore),
      if (footer?.showTerms ?? true)
        (label: 'Terms', onTap: widget.onTerms ?? openUrl(footer?.termsUrl)),
      if (footer?.showPrivacy ?? true)
        (
          label: 'Privacy',
          onTap: widget.onPrivacy ?? openUrl(footer?.privacyUrl)
        ),
    ];

    // ——— shared blocks (each layout composes a subset; keep every block in
    // lockstep with the same-named block in PaywallPhonePreview.tsx) ———

    // Classic header: hero image card (or accent icon tile) + centered
    // headline/subheadline. Byte-identical to the pre-layout renderer.
    final heroOrIcon = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 22),
      child: _filled(config.heroImageUrl)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                config.heroImageUrl!,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 180),
              ),
            )
          : Center(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child:
                    Text('◆', style: TextStyle(fontSize: 27, color: accent)),
              ),
            ),
    );

    final headlineBlock = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          config.headline,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
      ),
      if (_filled(config.subheadline))
        Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: Text(
            config.subheadline!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 21 / 15,
              color: t.textSecondary,
            ),
          ),
        ),
    ];

    // Hero layout banner: full-width media with a content-safe scrim overlay
    // carrying the headline/subheadline (always light-on-scrim). Falls back
    // to an accent field with the brand glyph when no hero image is set.
    final heroBanner = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 260),
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              Positioned.fill(
                child: _filled(config.heroImageUrl)
                    ? Image.network(
                        config.heroImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      )
                    : ColoredBox(color: accent),
              ),
              if (!_filled(config.heroImageUrl))
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 72),
                      child: Center(
                        child: Text(
                          '◆',
                          style: TextStyle(
                            fontSize: 64,
                            color: Color(0x59FFFFFF), // rgba(255,255,255,.35)
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                color: const Color(0x73000000), // rgba(0,0,0,.45) scrim
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.headline,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                    if (_filled(config.subheadline))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          config.subheadline!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 19 / 13.5,
                            color: Color(0xD9FFFFFF), // rgba(255,255,255,.85)
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Legacy feature bullets (feature-list layout).
    final featureBullets = config.features.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: Column(
              spacing: 14,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in config.features)
                  Row(
                    spacing: 12,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          _filled(f.icon) ? f.icon! : '✓',
                          style: TextStyle(
                            fontSize: 15,
                            height: 21 / 15,
                            color: accent,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.title,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                height: 21 / 15.5,
                                color: t.textPrimary,
                              ),
                            ),
                            if (_filled(f.description))
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  f.description!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 18 / 13,
                                    color: t.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );

    // Compact single-line checks (hero banner body, plans checklist).
    final featureChecks = config.features.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in config.features)
                  Row(
                    spacing: 10,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          _filled(f.icon) ? f.icon! : '✓',
                          style: TextStyle(fontSize: 14, color: accent),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          f.title,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            height: 20 / 14.5,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );

    // Trial timeline: icon dots joined by an accent rail; the first step is
    // filled solid ("you are here"), later steps are tinted.
    final timelineBlock = config.features.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < config.features.length; i++)
                  IntrinsicHeight(
                    child: Row(
                      spacing: 12,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Column(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: i == 0 ? accent : accentTint,
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: Text(
                                  _filled(config.features[i].icon)
                                      ? config.features[i].icon!
                                      : '✓',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: i == 0 ? t.accentInk : accent,
                                  ),
                                ),
                              ),
                              if (i != config.features.length - 1)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4),
                                    child:
                                        Container(width: 2, color: accentSoft),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: 6,
                              bottom:
                                  i == config.features.length - 1 ? 0 : 22,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  config.features[i].title,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    height: 21 / 15.5,
                                    color: t.textPrimary,
                                  ),
                                ),
                                if (_filled(config.features[i].description))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Text(
                                      config.features[i].description!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 18 / 13,
                                        color: t.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

    // Feature grid: two-column soft cards with an accent icon tile each (an
    // odd trailing card grows to the full row, as the RN wrap does).
    Widget gridCard(PaywallFeature f) => Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  color: accentTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _filled(f.icon) ? f.icon! : '✓',
                  style: TextStyle(fontSize: 15, color: accent),
                ),
              ),
              Text(
                f.title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 18 / 13.5,
                  color: t.textPrimary,
                ),
              ),
              if (_filled(f.description))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    f.description!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      color: t.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );

    final featureGrid = config.features.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < config.features.length; i += 2)
                  IntrinsicHeight(
                    child: Row(
                      spacing: 10,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: gridCard(config.features[i])),
                        if (i + 1 < config.features.length)
                          Expanded(child: gridCard(config.features[i + 1])),
                      ],
                    ),
                  ),
              ],
            ),
          );

    // Reveal: onboarding-style numbered benefit cards + progress dots.
    final progressDots = Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        spacing: 6,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == 0 ? accent : accentSoft,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );

    final revealCards = config.features.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < config.features.length; i++)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      spacing: 12,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accentTint,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                config.features[i].title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 20 / 15,
                                  color: t.textPrimary,
                                ),
                              ),
                              if (_filled(config.features[i].description))
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text(
                                    config.features[i].description!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 18 / 13,
                                      color: t.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

    // Social proof card: star row (+ numeric rating), quote, attribution.
    Widget? reviewCardFor(PaywallReview? review) {
      if (review == null ||
          (review.rating == null && !_filled(review.quote))) {
        return null;
      }
      final rating = review.rating;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var n = 1; n <= 5; n++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Text(
                        '★',
                        style: TextStyle(
                          fontSize: 15,
                          color: n <= rating.round() ? accent : t.border,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      _ratingLabel(rating),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            if (_filled(review.quote))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '“${review.quote}”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 19 / 13.5,
                    fontStyle: FontStyle.italic,
                    color: t.textPrimary,
                  ),
                ),
              ),
            if (_filled(review.author))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '— ${review.author}',
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ),
          ],
        ),
      );
    }

    final reviewCard = reviewCardFor(config.review);
    final countLine = _filled(config.review?.count)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              config.review!.count!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.textSecondary),
            ),
          )
        : null;

    // Offer bits: urgency line above the CTA; anchor price struck through on
    // the highlighted package.
    final urgencyLine = _filled(config.offer?.urgencyText)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              config.offer!.urgencyText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          )
        : null;

    // The anchor is dashboard free text while priceLabel is the store's
    // localized price — never pair them when their currency symbols disagree,
    // or a EUR customer would see a struck-through USD anchor next to the
    // real charge (this file's "display never disagrees with the charge"
    // rule; kept in lockstep with the preview's anchorPriceFor). Symbol-less
    // anchors can't be judged and pass through.
    String? anchorPriceFor(String priceLabel) {
      final anchor = config.offer?.strikethroughPrice;
      if (!_filled(anchor)) return null;
      final symbol = _currencySymbol.firstMatch(anchor!)?.group(0);
      return symbol == null || priceLabel.contains(symbol) ? anchor : null;
    }

    TextStyle anchorStyle(double fontSize) => TextStyle(
          fontSize: fontSize,
          decoration: TextDecoration.lineThrough,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: t.textFaint,
        );

    Widget priceLine(RevnixPaywallPackage pkg, bool highlighted) {
      final anchorPrice = highlighted ? anchorPriceFor(pkg.priceLabel) : null;
      final price = Text(
        pkg.priceLabel,
        style: TextStyle(
          fontSize: 14,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: t.textSecondary,
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: anchorPrice == null
            ? price
            : Row(
                spacing: 6,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [Text(anchorPrice, style: anchorStyle(13)), price],
              ),
      );
    }

    // Standard package rows (all layouts except plans columns / offer
    // spotlight). `withBadge: false` suppresses the row badge where the
    // layout already presents the badge elsewhere (offer pill).
    Widget packageRow(RevnixPaywallPackage pkg, bool withBadge) {
      final selected = pkg.packageId == selectedId;
      final highlighted = pkg.packageId == config.highlightPackageId;
      final badged = withBadge && highlighted && _filled(config.badgeText);
      final borderWidth = selected ? 2.0 : 1.0;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => _select(pkg.packageId),
          behavior: HitTestBehavior.opaque,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  // RN lays the border inside the box (border-box), so the
                  // padding here includes the border width.
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 15) +
                          EdgeInsets.all(borderWidth),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? accent : t.border,
                      width: borderWidth,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      priceLine(pkg, highlighted),
                    ],
                  ),
                ),
                if (badged)
                  Positioned(
                    top: -11,
                    right: 14,
                    child: Container(
                      // Absolute views take no width constraint from the
                      // card — a long badge string used to grow past the
                      // card edge (kept in lockstep with the dashboard
                      // preview, which truncates the same way).
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        config.badgeText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.accentInk,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget packageRows(List<RevnixPaywallPackage> list,
            {bool withBadge = true}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final pkg in list) packageRow(pkg, withBadge)],
          ),
        );

    // Plans layout: packages side by side as tier columns; the highlighted
    // tier carries the badge pill inside the column. Columns stay readable up
    // to 3 — beyond that the layout falls back to stacked rows (never drop a
    // purchasable package), same rule as the dashboard preview.
    final usePlanColumns = shown.length <= 3;
    Widget planColumn(RevnixPaywallPackage pkg) {
      final selected = pkg.packageId == selectedId;
      final highlighted = pkg.packageId == config.highlightPackageId;
      final anchorPrice = highlighted ? anchorPriceFor(pkg.priceLabel) : null;
      final borderWidth = selected ? 2.0 : 1.0;
      return Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          selected: selected,
          child: GestureDetector(
            onTap: () => _select(pkg.packageId),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 14) +
                      EdgeInsets.all(borderWidth),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? accent : t.border,
                  width: borderWidth,
                ),
              ),
              child: Column(
                children: [
                  if (highlighted && _filled(config.badgeText))
                    Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        config.badgeText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.accentInk,
                        ),
                      ),
                    ),
                  Text(
                    pkg.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 19 / 14,
                      color: t.textPrimary,
                    ),
                  ),
                  if (anchorPrice != null)
                    Text(anchorPrice, style: anchorStyle(13)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      pkg.priceLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final planColumns = Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: IntrinsicHeight(
        child: Row(
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final pkg in shown) planColumn(pkg)],
        ),
      ),
    );

    // Offer layout: the badge becomes a large centered pill; the highlighted
    // (else first) package renders as a spotlight card with the anchor price.
    RevnixPaywallPackage? spotlightLookup;
    for (final p in shown) {
      if (p.packageId == config.highlightPackageId) {
        spotlightLookup = p;
        break;
      }
    }
    spotlightLookup ??= shown.isEmpty ? null : shown.first;
    final spotlightPkg = spotlightLookup;

    final offerPill = _filled(config.badgeText)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Container(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    config.badgeText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                ),
              ),
            ),
          )
        : null;

    final offerSpotlight = spotlightPkg == null
        ? const <Widget>[]
        : <Widget>[
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: spotlightPkg.packageId == selectedId,
              child: GestureDetector(
                onTap: () => _select(spotlightPkg.packageId),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  // 18pt padding inside the always-2pt border, as RN lays it.
                  padding: const EdgeInsets.all(18) + const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      width: 2,
                      color: spotlightPkg.packageId == selectedId
                          ? accent
                          : t.border,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        spotlightPkg.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          spacing: 8,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            if (anchorPriceFor(spotlightPkg.priceLabel) !=
                                null)
                              Text(
                                anchorPriceFor(spotlightPkg.priceLabel)!,
                                style: anchorStyle(15),
                              ),
                            Text(
                              spotlightPkg.priceLabel,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                color: t.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (shown.length > 1)
              packageRows(
                shown
                    .where((p) => p.packageId != spotlightPkg.packageId)
                    .toList(),
                withBadge: false,
              ),
          ];

    final cta = Semantics(
      button: true,
      child: GestureDetector(
        onTap: () {
          if (!widget.loading && selectedId != null) {
            _purchase(selectedId);
          }
        },
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: widget.loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accentInk,
                  ),
                )
              : Text(
                  config.ctaLabel,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: t.accentInk,
                  ),
                ),
        ),
      ),
    );

    final footerBlock = footerItems.isEmpty
        ? null
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < footerItems.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      ' · ',
                      style: TextStyle(fontSize: 13, color: t.textFaint),
                    ),
                  ),
                GestureDetector(
                  onTap: footerItems[i].onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      footerItems[i].label,
                      style: TextStyle(fontSize: 13, color: t.textFaint),
                    ),
                  ),
                ),
              ],
            ],
          );

    // Tail shared by every layout: urgency → CTA → count → footer.
    final tail = <Widget>[
      ?urgencyLine,
      cta,
      ?countLine,
      ?footerBlock,
    ];

    List<Widget> body;
    switch (layout) {
      case 'hero':
        body = [
          heroBanner,
          ?featureChecks,
          ?reviewCard,
          packageRows(shown),
          ...tail,
        ];
      case 'timeline':
        body = [
          heroOrIcon,
          ...headlineBlock,
          ?timelineBlock,
          ?reviewCard,
          packageRows(shown),
          ...tail,
        ];
      case 'plans':
        body = [
          heroOrIcon,
          ...headlineBlock,
          if (usePlanColumns) planColumns else packageRows(shown),
          ?featureChecks,
          ?reviewCard,
          ...tail,
        ];
      case 'feature-grid':
        body = [
          heroOrIcon,
          ...headlineBlock,
          ?featureGrid,
          ?reviewCard,
          packageRows(shown),
          ...tail,
        ];
      case 'offer':
        body = [
          heroOrIcon,
          ?offerPill,
          ...headlineBlock,
          ...offerSpotlight,
          ?reviewCard,
          ...tail,
        ];
      case 'reveal':
        body = [
          progressDots,
          heroOrIcon,
          ...headlineBlock,
          ?revealCards,
          packageRows(shown),
          ...tail,
        ];
      default:
        // focus | feature-list | minimal — the original structure, unchanged
        // for legacy configs (review/offer blocks only exist when configured).
        body = [
          heroOrIcon,
          ...headlineBlock,
          if (layout == 'feature-list' && featureBullets != null)
            featureBullets,
          ?reviewCard,
          packageRows(shown),
          ...tail,
        ];
    }

    // PROPORTIONS mirror the RN renderer 1:1 (RN pt = Flutter logical px).
    //
    // Responsive rules:
    //  · the scroll body centers vertically on tall screens (no dead bottom
    //    half) and scrolls normally when it overflows.
    //  · content maxWidth 440 — on tablets/wide screens the column stays a
    //    readable width, horizontally centered, instead of stretching edge
    //    to edge.
    return Material(
      color: t.background,
      child: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, viewport) {
                final minHeight = viewport.hasBoundedHeight
                    ? (viewport.maxHeight - 28 - 32).clamp(0.0, double.infinity)
                    : 0.0;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: body,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            ..._classicClose(t),
          ],
        ),
      ),
    );
  }

  /// The dismiss affordance the classic layouts get (REV-252).
  ///
  /// The nine `template` layouts have the same problem the designed ones had —
  /// nothing on the screen closes them — and [RevnixPaywall.onClose] is a
  /// parameter of the shared widget, so a host that wires it must get a close
  /// on either path rather than silently nothing. Classic layouts author no
  /// elements of their own, so there is never a design chip to suppress: the
  /// rule reduces to "draw it whenever the host wired a handler".
  ///
  /// The designed path draws its own (inside the block renderer, where it can
  /// see the tree), so this is never reached there.
  List<Widget> _classicClose(_Palette t) {
    if (widget.onClose == null) return const [];
    return [
      Positioned(
        top: 14,
        right: 14,
        child: Semantics(
          button: true,
          label: 'Close',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.textPrimary.withValues(alpha: 0.14),
              ),
              child: Text(
                '\u00d7',
                style: TextStyle(color: t.textPrimary, fontSize: 17, height: 1),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
