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

  /// REV-272: implicit-placement triggers. Its own channel rather than a
  /// second message shape on the diagnostics stream — a paywall to present and
  /// a swallowed background failure are different subscriptions with different
  /// lifetimes.
  static const EventChannel _implicitChannel =
      EventChannel('com.revnix/revnix_flutter/implicit');

  static const EventChannel _deferredDeepLinkChannel =
      EventChannel('com.revnix/revnix_flutter/deferred_deep_link');

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
  ///
  /// [device] overrides individual device facts (REV-268). The native SDK
  /// detects platform, OS version, app version, locale, currency, model and
  /// the sandbox flag itself and sends them with every placement resolve, so
  /// targeting rules ("US storefront", "app version at least 3") can be
  /// evaluated on the request that serves the paywall; pass only what you
  /// know better — `{'storefront': 'US'}`, say. Keys: `platform`,
  /// `osVersion`, `appVersion`, `locale`, `currency`, `storefront`, `model`,
  /// `sandbox` (bool).
  ///
  /// [implicitPlacements] (REV-272) turns on the six moments the SDK reports
  /// on its own — `app_install`, `app_launch`, `session_start`,
  /// `deeplink_open`, `paywall_decline`, `transaction_abandon`. With it on,
  /// the native SDK asks `GET /v1/config` once and then fires only for the
  /// moments this app has configured in the dashboard, delivering each one
  /// that resolves to a paywall on [implicitPaywalls]. Off by default: without
  /// a listener there would be nothing to do with the answer.
  ///
  /// [skan] (iOS only) — set false to opt out of SKAdNetwork entirely.
  /// Registration with Apple otherwise happens automatically inside
  /// [registerInstall]; see [updateSkanConversionValue] to report conversion
  /// values.
  static Future<RevnixClient> configure({
    required String apiKey,
    required String baseUrl,
    Duration timeout = const Duration(seconds: 10),
    Duration entitlementsTtl = const Duration(seconds: 30),
    Duration offlineMaxCacheAge = const Duration(days: 14),
    Map<String, Object>? device,
    bool implicitPlacements = false,
    Duration sessionTimeout = const Duration(minutes: 30),
    bool skan = true,
    @visibleForTesting MethodChannel? channel,
  }) async {
    final client = RevnixClient._(channel ?? _defaultChannel);
    await client._invoke<void>('configure', {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'timeoutMs': timeout.inMilliseconds,
      'entitlementsTtlMs': entitlementsTtl.inMilliseconds,
      'offlineMaxCacheAgeMs': offlineMaxCacheAge.inMilliseconds,
      'device': ?device,
      'implicitPlacements': implicitPlacements,
      'sessionTimeoutMs': sessionTimeout.inMilliseconds,
      'skan': skan,
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
  ///
  /// A close is a DECLINE. Do not report one for a display that ended in a
  /// purchase — with implicit placements on, a close is also the
  /// `paywall_decline` moment, and a win-back offer seconds after a successful
  /// purchase is the one thing an operator never means.
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

  /// REV-272: implicit-placement triggers — one event per moment that
  /// resolved to a paywall. Present each however your app presents paywalls;
  /// the SDK deliberately does not present for you, because it does not own
  /// your `Navigator` and a paywall pushed over a splash route is worse than
  /// no paywall.
  ///
  /// Requires `implicitPlacements: true` in [configure]; the stream stays
  /// silent otherwise.
  ///
  /// ⚠️ Pass `trigger.resolution.placementKey` to [logPaywallShown] for the
  /// display you present. That is what tells the SDK this display came FROM an
  /// implicit trigger, and it is the only thing that stops a `paywall_decline`
  /// paywall from firing `paywall_decline` again when the customer dismisses it
  /// — a loop with no way out but force-quitting. The server refuses to serve
  /// back the very same paywall as a backstop, but it cannot see a rule
  /// pointing at a DIFFERENT paywall that points back.
  Stream<RevnixImplicitTrigger> get implicitPaywalls => _implicitChannel
      .receiveBroadcastStream()
      .map((event) => RevnixImplicitTrigger.fromMap(
          (event as Map<Object?, Object?>?) ?? const {}));

  /// REV-272: hand the SDK the URL that opened your app, from wherever you
  /// already receive it (`uni_links`, `go_router`, `AppLinks`).
  ///
  /// This is the one implicit moment the SDK cannot see for itself — the URL
  /// reaches your app's own entry point, and an SDK intercepting it would be
  /// fighting your router. Does nothing unless `deeplink_open` is configured
  /// in the dashboard.
  Future<void> handleDeepLink(String url) =>
      _invoke<void>('handleDeepLink', {'url': url});

  /// Unwraps a link an email service provider (Mailchimp, SendGrid, …)
  /// wrapped in its own click-tracking domain, e.g.
  /// `https://click.mailchimp.com/track/abc` becomes
  /// `com.voigu.app://promo?utm_source=email&utm_campaign=summer50`. Route on
  /// the returned URL and pass it to [handleDeepLink]; never throws, and any
  /// failure hands the input `url` straight back.
  Future<String> resolveDeepLink(String url) async {
    if (url.isEmpty) return url;
    try {
      final resolved = await _invoke<String>('resolveDeepLink', {'url': url});
      return resolved == null || resolved.isEmpty ? url : resolved;
    } on RevnixException {
      return url;
    } on PlatformException {
      return url;
    } on MissingPluginException {
      return url;
    }
  }

  /// The link the customer clicked most recently, straight from the native
  /// SDK's own deep-link handling — a point-in-time read, not a stream. Never
  /// throws: any platform error returns null.
  Future<LastDeepLink?> getLastDeepLink() async {
    try {
      final map =
          await _invoke<Map<Object?, Object?>>('getLastDeepLink');
      final url = map?['url'];
      return map == null || url is! String || url.isEmpty
          ? null
          : LastDeepLink.fromMap(map);
    } on RevnixException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// REV-299: the link the customer clicked before they had the app, echoed
  /// back by the native SDK from the `registerInstall` response at most once
  /// per install. An event that arrives before you listen is held natively
  /// and delivered to your first listener, so subscribing any time after
  /// [configure] still sees it.
  ///
  /// A message whose `match` this Dart layer does not know (a native SDK
  /// newer than this package) or whose `url` is missing or empty is dropped
  /// rather than delivered malformed.
  ///
  /// A single broadcast stream shared by every listener: `EventChannel`
  /// tears down the native side's handler on the FIRST cancel, so a second
  /// `.listen()` (or a one-shot `.first`) on a fresh
  /// `receiveBroadcastStream()` would silently kill an earlier subscriber
  /// and — worse — lose the at-most-once event for good.
  Stream<(String url, DeferredDeepLinkMatch match)> get onDeferredDeepLink =>
      _deferredDeepLink;

  late final Stream<(String url, DeferredDeepLinkMatch match)>
      _deferredDeepLink = _deferredDeepLinkChannel
          .receiveBroadcastStream()
          .map((event) {
            final map = (event as Map<Object?, Object?>?) ?? const {};
            final url = map['url'] as String?;
            final match =
                DeferredDeepLinkMatch.fromWire(map['match'] as String?);
            if (url == null || url.isEmpty || match == null) return null;
            return (url, match);
          })
          .where((event) => event != null)
          .cast<(String, DeferredDeepLinkMatch)>()
          .asBroadcastStream();

  /// REV-299: Android only. Hand the raw Play Install Referrer string to the
  /// native SDK (read it with an install-referrer plugin of your choice —
  /// this method does not read it for you). A no-op on iOS, which has no
  /// install referrer.
  Future<void> handleInstallReferrer(String referrer) =>
      _invoke<void>('handleInstallReferrer', {'referrer': referrer});

  /// AT10: report a SKAdNetwork conversion value. iOS only — a no-op on
  /// Android. Registration with Apple is automatic inside [registerInstall];
  /// this only updates the conversion value already registered.
  ///
  /// [value] is the fine-grained conversion value, 0-63. [coarse] is the
  /// coarse value Apple falls back to once the fine value is no longer
  /// available. The value goes to Apple, never to Revnix — nothing here
  /// touches the network. For Apple to deliver the postback your app needs
  /// `NSAdvertisingAttributionReportEndpoint` in its Info.plist.
  Future<void> updateSkanConversionValue(
    int value, {
    RevnixCoarseValue? coarse,
    bool lockWindow = false,
  }) =>
      _invoke<void>('updateSkanConversionValue', {
        'value': value,
        'coarse': ?coarse?.name,
        'lockWindow': lockWindow,
      });

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
