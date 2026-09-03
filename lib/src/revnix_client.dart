import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'errors.dart';
import 'models.dart';

/// Flutter client for Revnix.
///
/// This is a thin, faithful bridge over the native SDKs — `revnix-swift` on
/// iOS and `revnix-kotlin` on Android. The resilience policy (offline cache,
/// retry queue, kill-switch discipline) lives there and is deliberately NOT
/// reimplemented in Dart: one implementation per platform means one place for
/// the policy to be right.
///
/// What this layer owes you is that nothing is lost in translation — typed
/// errors stay typed, and `stale` survives the channel.
class RevnixClient {
  RevnixClient._(this._channel);

  static const MethodChannel _defaultChannel =
      MethodChannel('com.revnix/revnix_flutter');

  static const EventChannel _diagnosticsChannel =
      EventChannel('com.revnix/revnix_flutter/diagnostics');

  final MethodChannel _channel;

  static RevnixClient? _instance;

  /// The configured client. Call [configure] once at startup first.
  static RevnixClient get instance {
    final client = _instance;
    if (client == null) {
      throw StateError(
        'RevnixClient.configure() must be called before RevnixClient.instance',
      );
    }
    return client;
  }

  /// Configure once at app startup.
  ///
  /// Use a **publishable** key (`rvx_pk_…`). Secret keys must never ship in a
  /// binary, so identify/alias are server-proxied by design and are not
  /// methods here.
  static Future<RevnixClient> configure({
    required String apiKey,
    required String baseUrl,
    Duration timeout = const Duration(seconds: 10),
    Duration entitlementsTtl = const Duration(seconds: 30),
    Duration offlineMaxCacheAge = const Duration(days: 14),
    @visibleForTesting MethodChannel? channel,
  }) async {
    final client = RevnixClient._(channel ?? _defaultChannel);
    await client._invoke<void>('configure', {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'timeoutMs': timeout.inMilliseconds,
      'entitlementsTtlMs': entitlementsTtl.inMilliseconds,
      'offlineMaxCacheAgeMs': offlineMaxCacheAge.inMilliseconds,
    });
    _instance = client;
    return client;
  }

  /// Anonymous id, minted and persisted natively on first use.
  Future<String> customerId() async =>
      await _invoke<String>('customerId') ?? '';

  /// Mint a fresh anonymous identity. Call at sign-out, or the next user
  /// inherits the previous one's cached entitlements.
  Future<String> logout() async => await _invoke<String>('logout') ?? '';

  /// Network-first entitlement read. Transient failures serve the cache
  /// flagged `stale`; deliberate rejections (401/403/404/409) throw.
  Future<CustomerEntitlements> entitlements() async {
    final map = await _invoke<Map<Object?, Object?>>('entitlements');
    return CustomerEntitlements.fromMap(map ?? const {});
  }

  /// The last cached snapshot, with no network call. Always `stale: true`.
  /// Null when this customer has never had a live read.
  Future<CustomerEntitlements?> cachedEntitlements() async {
    final map = await _invoke<Map<Object?, Object?>>('cachedEntitlements');
    return map == null ? null : CustomerEntitlements.fromMap(map);
  }

  /// Gate helper — never throws. Unknown or unreachable resolves to false, so
  /// gates fail closed.
  Future<bool> isEntitled(String entitlementId) async {
    try {
      return await _invoke<bool>('isEntitled', {
            'entitlementId': entitlementId,
          }) ??
          false;
    } on RevnixException {
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Read-your-writes: poll until the ledger reflects [seq]. Bypasses the soft
  /// TTL, and returns the last read rather than throwing if the ledger never
  /// catches up.
  Future<CustomerEntitlements> waitForEntitlements(int seq) async {
    final map = await _invoke<Map<Object?, Object?>>(
      'waitForEntitlements',
      {'seq': seq},
    );
    return CustomerEntitlements.fromMap(map ?? const {});
  }

  /// Register a store purchase. On a transient failure the native SDK queues
  /// it durably and rethrows, so the claim is never lost.
  Future<RegisterPurchaseResult> registerPurchase(
    RegisterPurchaseInput input,
  ) async {
    final map = await _invoke<Map<Object?, Object?>>(
      'registerPurchase',
      input.toMap(),
    );
    return RegisterPurchaseResult.fromMap(map ?? const {});
  }

  /// Drain the persistent retry queue. Safe to call on every launch and
  /// foreground — the server dedupes on the purchase key.
  Future<int> retryPendingPurchases() async =>
      await _invoke<int>('retryPendingPurchases') ?? 0;

  /// How many registrations are still queued.
  Future<int> pendingPurchaseCount() async =>
      await _invoke<int>('pendingPurchaseCount') ?? 0;

  /// Resolve a placement to its offering and remote paywall config.
  Future<PlacementResolution> resolvePlacement(String key) async {
    final map = await _invoke<Map<Object?, Object?>>(
      'resolvePlacement',
      {'placementKey': key},
    );
    return PlacementResolution.fromMap(map ?? const {});
  }

  /// Fire-and-forget install beacon; recorded once per customer id.
  Future<void> registerInstall({String? platform, String? appVersion}) =>
      _invoke<void>('registerInstall', {
        'platform': ?platform,
        'appVersion': ?appVersion,
      });

  /// Fire-and-forget paywall impression. Call when the paywall becomes
  /// visible, not when you start loading it.
  ///
  /// Resolves with the view id the beacon generated (REV-252), or null on a
  /// host platform that predates close reporting. Hand that id to
  /// [logPaywallClosed] when the customer dismisses THIS display: the two
  /// events sharing one view id is what lets the ledger pair a close with the
  /// display it ended, and the gap between their timestamps is the customer's
  /// dwell on the screen. Ignoring the result is still valid — it stays a
  /// fire-and-forget beacon. [RevnixPaywall] does all of this for you.
  Future<String?> logPaywallShown({String? placementKey, String? paywallId}) =>
      _invoke<String>('logPaywallShown', {
        'placementKey': ?placementKey,
        'paywallId': ?paywallId,
      });

  /// Fire-and-forget paywall dismissal (REV-252) — the other half of a
  /// display's life. Idempotent per view id, exactly like the impression.
  ///
  /// Pass the id [logPaywallShown] resolved with for this display.
  Future<void> logPaywallClosed(
    String viewId, {
    String? placementKey,
    String? paywallId,
  }) =>
      _invoke<void>('logPaywallClosed', {
        'viewId': viewId,
        'placementKey': ?placementKey,
        'paywallId': ?paywallId,
      });

  /// Report one of the six paywall interactions (REV-263) — what the customer
  /// DID on a display, between the [logPaywallShown] that opened it and the
  /// [logPaywallClosed] (or purchase) that ended it.
  ///
  /// Fire-and-forget like the other beacons.
  ///
  /// [viewId] is the id [logPaywallShown] resolved with for THIS display.
  /// Passing it is what threads the whole life of one impression together and
  /// puts the event on the paywall's own analytics row.
  ///
  /// [RevnixPaywall] reports [RevnixPaywallEvent.selected],
  /// [RevnixPaywallEvent.purchaseStarted], [RevnixPaywallEvent.restore] and a
  /// no-products [RevnixPaywallEvent.error] for you. The purchase OUTCOME is
  /// yours: only your app performs the store call, so report
  /// [RevnixPaywallEvent.purchaseAbandoned] /
  /// [RevnixPaywallEvent.purchaseFailed] from your own in_app_purchase error
  /// handling.
  ///
  /// [eventId] is the idempotency key and defaults to [viewId], which caps the
  /// report at one per display per event. Pass one per occurrence — and reuse
  /// it across your own retries — to record each occurrence.
  Future<void> logPaywallEvent(
    RevnixPaywallEvent event,
    String viewId, {
    String? placementKey,
    String? paywallId,
    String? productId,
    String? code,
    String? message,
    String? eventId,
  }) =>
      _invoke<void>('logPaywallEvent', {
        'event': event.wireName,
        'viewId': viewId,
        'placementKey': ?placementKey,
        'paywallId': ?paywallId,
        'productId': ?productId,
        'code': ?code,
        // The server bounds `message` at 1024; trimming here keeps a long
        // localized store error from turning the whole report into a 400.
        'message': ?(message != null && message.length > 1024
            ? message.substring(0, 1024)
            : message),
        'eventId': ?eventId,
      });

  /// Set attributes on the current customer. Attributes are what A/B-test
  /// audiences target — set `country`, `app_version`, `locale`, or any custom
  /// key you want to segment on. A null value deletes the key.
  ///
  /// Throws, unlike the fire-and-forget beacons: the next placement resolve
  /// may depend on these. `email` and `username` are reserved (secret key
  /// only), and an attribute your backend already set cannot be changed from
  /// a device.
  Future<void> setAttributes(Map<String, Object?> attributes) =>
      _invoke<void>('setAttributes', {'attributes': attributes});

  /// Background failures the SDK swallowed (queue drains, telemetry beacons).
  Stream<RevnixDiagnostic> get diagnostics => _diagnosticsChannel
      .receiveBroadcastStream()
      .map((event) => RevnixDiagnostic.fromMap(
          (event as Map<Object?, Object?>?) ?? const {}));

  /// Single funnel for every call, so a native failure always arrives as a
  /// typed [RevnixException] rather than a bare PlatformException.
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (err) {
      throw revnixExceptionFrom(
        err.code,
        err.message,
        err.details as Map<Object?, Object?>?,
      );
    }
  }
}
