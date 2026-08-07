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

class PlacementResolution {
  const PlacementResolution({
    required this.status,
    required this.placementKey,
    required this.revision,
    required this.offering,
    this.paywall,
  });

  final String status;
  final String placementKey;

  /// Published catalog revision this resolution came from.
  final int revision;
  final PlacementOffering offering;

  /// Remote paywall render contract — your app renders it in v1.
  final Map<Object?, Object?>? paywall;

  static PlacementResolution fromMap(Map<Object?, Object?> map) =>
      PlacementResolution(
        status: map['status'] as String? ?? '',
        placementKey: map['placementKey'] as String? ?? '',
        revision: map['revision'] as int? ?? 0,
        offering: PlacementOffering.fromMap(
            (map['offering'] as Map<Object?, Object?>?) ?? const {}),
        paywall: map['paywall'] as Map<Object?, Object?>?,
      );
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
