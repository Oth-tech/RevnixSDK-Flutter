/// Models are 1:1 with `revnix-app/public/openapi.yaml` schemas, and identical
/// in shape to the Swift, Kotlin, and KMP ports.
///
/// Dart's `int` is 64-bit on mobile, so unix-ms timestamps and ledger cursors
/// are safe. This plugin is mobile-only in v1 — on the web target `int` is a
/// double and large values would lose precision.
library;

enum RevnixStore {
  apple,
  google;

  String get wire => name;

  static RevnixStore fromWire(String value) =>
      RevnixStore.values.firstWhere((s) => s.wire == value,
          orElse: () => RevnixStore.apple);
}

/// REV-263: the six paywall interactions [RevnixClient.logPaywallEvent] can
/// report — what the customer did on a display, between the view that opened
/// it and the close or purchase that ended it. The server turns each into the
/// ledger type `paywall.<wireName>`.
enum RevnixPaywallEvent {
  /// A package was picked.
  selected('selected'),

  /// Checkout was started.
  purchaseStarted('purchase_started'),

  /// The customer backed out at the store sheet.
  purchaseAbandoned('purchase_abandoned'),

  /// The store refused the payment.
  purchaseFailed('purchase_failed'),

  /// Restore purchases was tapped.
  restore('restore'),

  /// The paywall itself failed — config, products, or render.
  error('error');

  const RevnixPaywallEvent(this.wireName);

  final String wireName;
}

class EntitlementSource {
  const EntitlementSource({
    required this.kind,
    required this.key,
    required this.isActive,
    this.expiresAt,
  });

  final String kind;
  final String key;
  final bool isActive;
  final int? expiresAt;

  static EntitlementSource fromMap(Map<Object?, Object?> map) =>
      EntitlementSource(
        kind: map['kind'] as String? ?? '',
        key: map['key'] as String? ?? '',
        isActive: map['isActive'] as bool? ?? false,
        expiresAt: map['expiresAt'] as int?,
      );
}

class Entitlement {
  const Entitlement({
    required this.entitlementId,
    required this.isActive,
    this.expiresAt,
    this.sources = const [],
  });

  final String entitlementId;
  final bool isActive;

  /// Unix ms; null for a lifetime purchase or an open-ended grant.
  final int? expiresAt;
  final List<EntitlementSource> sources;

  static Entitlement fromMap(Map<Object?, Object?> map) => Entitlement(
        entitlementId: map['entitlementId'] as String? ?? '',
        isActive: map['isActive'] as bool? ?? false,
        expiresAt: map['expiresAt'] as int?,
        sources: (map['sources'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(EntitlementSource.fromMap)
            .toList(),
      );
}

class CustomerEntitlements {
  const CustomerEntitlements({
    required this.customerId,
    required this.cursor,
    this.entitlements = const [],
    this.stale,
    this.fetchedAt,
  });

  final String customerId;

  /// Ledger position this read reflects (read-your-writes).
  final int cursor;
  final List<Entitlement> entitlements;

  /// True when served from the offline cache.
  final bool? stale;

  /// Unix ms this snapshot was fetched.
  final int? fetchedAt;

  bool isEntitled(String entitlementId) => entitlements
      .any((e) => e.entitlementId == entitlementId && e.isActive);

  static CustomerEntitlements fromMap(Map<Object?, Object?> map) =>
      CustomerEntitlements(
        customerId: map['customerId'] as String? ?? '',
        cursor: map['cursor'] as int? ?? 0,
        entitlements: (map['entitlements'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(Entitlement.fromMap)
            .toList(),
        stale: map['stale'] as bool?,
        fetchedAt: map['fetchedAt'] as int?,
      );
}

class RegisterPurchaseInput {
  const RegisterPurchaseInput({
    required this.source,
    required this.token,
    required this.productId,
    required this.transactionId,
    this.occurredAt,
    this.expiresAt,
    this.signedTransactionInfo,
  });

  /// Convenience for Google, where the purchase token is BOTH the token and
  /// the transaction id — Play has no separate transaction identifier.
  factory RegisterPurchaseInput.google({
    required String purchaseToken,
    required String productId,
    int? occurredAt,
  }) =>
      RegisterPurchaseInput(
        source: RevnixStore.google,
        token: purchaseToken,
        productId: productId,
        transactionId: purchaseToken,
        occurredAt: occurredAt,
      );

  final RevnixStore source;

  /// Apple: originalTransactionId · Google: purchaseToken.
  final String token;
  final String productId;
  final String transactionId;
  final int? occurredAt;
  final int? expiresAt;

  /// StoreKit 2 JWS — the proof path. Claims without it are provisional.
  final String? signedTransactionInfo;

  Map<String, Object?> toMap() => {
        'source': source.wire,
        'token': token,
        'productId': productId,
        'transactionId': transactionId,
        if (occurredAt != null) 'occurredAt': occurredAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (signedTransactionInfo != null)
          'signedTransactionInfo': signedTransactionInfo,
      };
}

class RegisterPurchaseResult {
  const RegisterPurchaseResult({
    required this.eventId,
    required this.seq,
    required this.duplicate,
    required this.customerId,
    this.transferred = false,
    this.ownedByOtherCustomer,
    this.refused,
    this.restored,
    this.provisional,
  });

  final String eventId;

  /// Ledger position — pass to [waitForEntitlements] to unlock.
  final int seq;
  final bool duplicate;

  /// The canonical id to use going forward. The SDK adopts it automatically.
  final String customerId;
  final bool transferred;
  final bool? ownedByOtherCustomer;
  final String? refused;
  final bool? restored;

  /// Recorded without store proof — live but time-boxed until the store
  /// confirms. Expect true on Android; Play claims carry no device-side proof.
  final bool? provisional;

  static RegisterPurchaseResult fromMap(Map<Object?, Object?> map) =>
      RegisterPurchaseResult(
        eventId: map['eventId'] as String? ?? '',
        seq: map['seq'] as int? ?? 0,
        duplicate: map['duplicate'] as bool? ?? false,
        customerId: map['customerId'] as String? ?? '',
        transferred: map['transferred'] as bool? ?? false,
        ownedByOtherCustomer: map['ownedByOtherCustomer'] as bool?,
        refused: map['refused'] as String?,
        restored: map['restored'] as bool?,
        provisional: map['provisional'] as bool?,
      );
}

class PlacementPackage {
  const PlacementPackage({required this.packageId, required this.productId});

  final String packageId;
  final String productId;

  static PlacementPackage fromMap(Map<Object?, Object?> map) => PlacementPackage(
        packageId: map['packageId'] as String? ?? '',
        productId: map['productId'] as String? ?? '',
      );
}

class PlacementOffering {
  const PlacementOffering({
    required this.offeringId,
    required this.displayName,
    this.packages = const [],
  });

  final String offeringId;
  final String displayName;
  final List<PlacementPackage> packages;

  static PlacementOffering fromMap(Map<Object?, Object?> map) =>
      PlacementOffering(
        offeringId: map['offeringId'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
        packages: (map['packages'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(PlacementPackage.fromMap)
            .toList(),
      );
}

/// One feature row in a paywall config.
class PaywallFeature {
  const PaywallFeature({this.icon, required this.title, this.description});

  final String? icon;
  final String title;
  final String? description;

  static PaywallFeature fromMap(Map<Object?, Object?> map) => PaywallFeature(
        icon: map['icon'] as String?,
        title: map['title'] as String? ?? '',
        description: map['description'] as String?,
      );
}

/// Social proof, dashboard-configured. Render whichever pieces are set:
/// stars/quote card above the packages, [count] under the CTA.
class PaywallReview {
  const PaywallReview({this.rating, this.quote, this.author, this.count});

  /// 0–5; rendered as a star row.
  final double? rating;
  final String? quote;
  final String? author;

  /// e.g. "Join 2M+ users" — small line under the CTA.
  final String? count;

  static PaywallReview fromMap(Map<Object?, Object?> map) => PaywallReview(
        rating: (map['rating'] as num?)?.toDouble(),
        quote: map['quote'] as String?,
        author: map['author'] as String?,
        count: map['count'] as String?,
      );
}

/// Win-back/offer presentation: anchor price struck through on the
/// highlighted package, urgency line above the CTA.
class PaywallOffer {
  const PaywallOffer({this.strikethroughPrice, this.urgencyText});

  final String? strikethroughPrice;
  final String? urgencyText;

  static PaywallOffer fromMap(Map<Object?, Object?> map) => PaywallOffer(
        strikethroughPrice: map['strikethroughPrice'] as String?,
        urgencyText: map['urgencyText'] as String?,
      );
}

/// Footer links, dashboard-configured. When a URL is set open it directly;
/// otherwise run the host app's own terms/privacy handler.
class PaywallFooter {
  const PaywallFooter({
    required this.showRestore,
    required this.showTerms,
    required this.showPrivacy,
    this.termsUrl,
    this.privacyUrl,
  });

  final bool showRestore;
  final bool showTerms;
  final bool showPrivacy;
  final String? termsUrl;
  final String? privacyUrl;

  static PaywallFooter fromMap(Map<Object?, Object?> map) => PaywallFooter(
        // Absent footer (legacy config) means "show all three", so a missing
        // flag defaults to shown rather than hidden.
        showRestore: map['showRestore'] as bool? ?? true,
        showTerms: map['showTerms'] as bool? ?? true,
        showPrivacy: map['showPrivacy'] as bool? ?? true,
        termsUrl: map['termsUrl'] as String?,
        privacyUrl: map['privacyUrl'] as String?,
      );
}

/// Remote paywall render contract — the app draws this with its own
/// components; prices still come from the store (StoreKit / Play Billing) so
/// the display never disagrees with the charge.
class PaywallConfig {
  const PaywallConfig({
    required this.template,
    this.mode,
    required this.headline,
    this.subheadline,
    this.features = const [],
    required this.ctaLabel,
    this.highlightPackageId,
    this.badgeText,
    this.accent,
    this.heroImageUrl,
    this.review,
    this.offer,
    this.footer,
    this.blocks,
  });

  /// Layout — the screen structure to render. Known values: "focus",
  /// "feature-list", "minimal", "hero", "timeline", "plans", "feature-grid",
  /// "offer", "reveal". Kept as a plain string so a newer dashboard adding a
  /// layout never breaks parsing — fall back to a default layout for values
  /// you don't recognize.
  final String template;

  /// Color scheme: "dark" or "light". Null (legacy config) = dark.
  final String? mode;
  final String headline;
  final String? subheadline;
  final List<PaywallFeature> features;
  final String ctaLabel;

  /// packageId of the visually highlighted package.
  final String? highlightPackageId;

  /// Badge on the highlighted package, e.g. "SAVE 17%".
  final String? badgeText;

  /// Accent hex like "#6478ff"; fall back to the app theme when absent.
  final String? accent;

  /// Hero image URL rendered above the headline in place of the icon tile.
  final String? heroImageUrl;
  final PaywallReview? review;
  final PaywallOffer? offer;

  /// Null (legacy config) = show all three footer links.
  final PaywallFooter? footer;

  /// A designed paywall: the block tree the dashboard's builder authored.
  /// When present [RevnixPaywall] renders THIS and the fields above act as the
  /// fallback for apps on an SDK that predates block rendering — so an older
  /// app keeps showing a sane classic screen instead of nothing.
  ///
  /// Held as the raw decoded map rather than a typed tree so a document from a
  /// NEWER dashboard can never fail to parse here; `PaywallBlockDoc.parse`
  /// turns it into the parts this SDK understands.
  final Object? blocks;

  static PaywallConfig fromMap(Map<Object?, Object?> map) {
    final review = map['review'] as Map<Object?, Object?>?;
    final offer = map['offer'] as Map<Object?, Object?>?;
    final footer = map['footer'] as Map<Object?, Object?>?;
    return PaywallConfig(
      template: map['template'] as String? ?? '',
      mode: map['mode'] as String?,
      headline: map['headline'] as String? ?? '',
      subheadline: map['subheadline'] as String?,
      features: (map['features'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(PaywallFeature.fromMap)
          .toList(),
      ctaLabel: map['ctaLabel'] as String? ?? '',
      highlightPackageId: map['highlightPackageId'] as String?,
      badgeText: map['badgeText'] as String?,
      accent: map['accent'] as String?,
      heroImageUrl: map['heroImageUrl'] as String?,
      review: review == null ? null : PaywallReview.fromMap(review),
      offer: offer == null ? null : PaywallOffer.fromMap(offer),
      footer: footer == null ? null : PaywallFooter.fromMap(footer),
      blocks: map['blocks'],
    );
  }
}

/// Remote paywall design attached to a placement.
class PlacementPaywall {
  const PlacementPaywall({
    required this.paywallId,
    required this.name,
    required this.config,
  });

  final String paywallId;
  final String name;
  final PaywallConfig config;

  static PlacementPaywall fromMap(Map<Object?, Object?> map) =>
      PlacementPaywall(
        paywallId: map['paywallId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        config: PaywallConfig.fromMap(
            (map['config'] as Map<Object?, Object?>?) ?? const {}),
      );
}

/// The running experiment's sticky assignment for this customer (REV-219).
/// Attribution only — the served offering/paywall are already the variant's,
/// so the app just renders what it gets.
class PlacementExperiment {
  const PlacementExperiment({required this.key, required this.variantId});

  final String key;
  final String variantId;

  static PlacementExperiment fromMap(Map<Object?, Object?> map) =>
      PlacementExperiment(
        key: map['key'] as String? ?? '',
        variantId: map['variantId'] as String? ?? '',
      );
}

class PlacementResolution {
  const PlacementResolution({
    required this.status,
    required this.placementKey,
    required this.revision,
    required this.offering,
    this.paywall,
    this.experiment,
    this.preview = false,
  });

  final String status;
  final String placementKey;

  /// Published catalog revision this resolution came from.
  final int revision;
  final PlacementOffering offering;

  /// Remote paywall render contract — your app renders it in v1. Null when
  /// the placement has no paywall attached.
  final PlacementPaywall? paywall;

  /// Sticky experiment assignment for this customer. Null when no running
  /// experiment covers the placement — the server sends null, and older
  /// servers omit the key entirely; both parse to null.
  final PlacementExperiment? experiment;

  /// True only on a dashboard QR/link preview resolution, never on a real
  /// resolve. A preview may carry [revision] 0 and an empty [offering] — the
  /// preview does not tie to a published catalog revision.
  final bool preview;

  static PlacementResolution fromMap(Map<Object?, Object?> map) {
    final paywall = map['paywall'] as Map<Object?, Object?>?;
    final experiment = map['experiment'] as Map<Object?, Object?>?;
    return PlacementResolution(
      status: map['status'] as String? ?? '',
      placementKey: map['placementKey'] as String? ?? '',
      revision: map['revision'] as int? ?? 0,
      offering: PlacementOffering.fromMap(
          (map['offering'] as Map<Object?, Object?>?) ?? const {}),
      paywall: paywall == null ? null : PlacementPaywall.fromMap(paywall),
      experiment:
          experiment == null ? null : PlacementExperiment.fromMap(experiment),
      preview: map['preview'] == true,
    );
  }
}

/// A background failure the SDK swallowed rather than surfacing.
class RevnixDiagnostic {
  const RevnixDiagnostic({required this.op, required this.message});

  final String op;
  final String message;

  static RevnixDiagnostic fromMap(Map<Object?, Object?> map) => RevnixDiagnostic(
        op: map['op'] as String? ?? '',
        message: map['message'] as String? ?? '',
      );
}

/// REV-272: which of the six implicit moments fired.
///
/// A placement is normally a location the host resolves by name, so every new
/// place a paywall could appear costs a code change and a store release. These
/// six are the same in every app and visible to the SDK without the host
/// saying anything, so an operator can attach a paywall to them from the
/// dashboard alone.
enum RevnixImplicitPlacement {
  appInstall('app_install'),
  appLaunch('app_launch'),
  sessionStart('session_start'),

  /// Lowercase, not Superwall's `deepLink_open`: a placement key must match
  /// `^[a-z0-9][a-z0-9._-]{0,63}$` server-side.
  deeplinkOpen('deeplink_open'),
  paywallDecline('paywall_decline'),
  transactionAbandon('transaction_abandon');

  const RevnixImplicitPlacement(this.key);

  /// The placement key as it appears in the dashboard and on the wire.
  final String key;

  static RevnixImplicitPlacement? fromKey(String? key) {
    for (final value in RevnixImplicitPlacement.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// REV-299: how confidently the server matched a deferred deep link to this
/// install. iOS never reports [exact] — there is no install-time signal that
/// certain, only fingerprint matching against a click seen shortly before.
enum DeferredDeepLinkMatch {
  exact,
  probabilistic;

  static DeferredDeepLinkMatch? fromWire(String? value) => switch (value) {
        'exact' => exact,
        'probabilistic' => probabilistic,
        _ => null,
      };
}

/// The placementKey a dashboard QR/link preview resolves under
/// (`<scheme>://revnix-preview?revnix_preview=<token>`, forwarded to
/// [RevnixClient.implicitPaywalls] by the native SDK). Not one of the six
/// [RevnixImplicitPlacement] keys, and never sent to the triggered ledger.
const String revnixPreviewPlacementKey = 'revnix_preview';

/// REV-272: one implicit moment that resolved to a paywall. Only ever
/// delivered WITH a paywall — a moment the server answered with none (nothing
/// attached, or the same paywall the customer is leaving) is reported and then
/// dropped, since there is nothing to present.
class RevnixImplicitTrigger {
  const RevnixImplicitTrigger({
    required this.placement,
    required this.resolution,
  });

  /// Which of the six fired. Null only on a version skew — a native SDK newer
  /// than this Dart layer reporting a moment it does not know.
  final RevnixImplicitPlacement? placement;

  /// The resolution, exactly as [RevnixClient.resolvePlacement] would return.
  final PlacementResolution resolution;

  static RevnixImplicitTrigger fromMap(Map<Object?, Object?> map) =>
      RevnixImplicitTrigger(
        placement:
            RevnixImplicitPlacement.fromKey(map['placement'] as String?),
        resolution: PlacementResolution.fromMap(
            (map['resolution'] as Map<Object?, Object?>?) ?? const {}),
      );
}
