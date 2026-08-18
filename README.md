# revnix_flutter

Flutter plugin for [Revnix](https://revnix.com) — subscriptions and
entitlements, wrapping the native SDKs rather than reimplementing them.

- **iOS** → [`RevnixSDK-iOS`](https://github.com/Oth-tech/RevnixSDK-iOS) (StoreKit 2)
- **Android** → [`RevnixSDK-Android`](https://github.com/Oth-tech/RevnixSDK-Android) (Play Billing 8)

> Until those SDKs ship to CocoaPods / Maven Central, their 0.2.0 sources are
> **vendored** inside this plugin (`ios/…/Revnix/`, `android/…/com/revnix/`)
> so the plugin builds standalone. Fix native bugs upstream, then re-copy.
> See [`android/src/main/kotlin/com/revnix/VENDORED.md`](android/src/main/kotlin/com/revnix/VENDORED.md).

## Why a wrapper and not a Dart client

The resilience policy — offline cache, retry queue, kill-switch discipline — is
a *product contract*, not an implementation detail. Reimplementing it per
platform means one more place for it to silently rot. It already happened once:
the Swift port dropped a TTL bypass and broke post-purchase unlock until a test
caught it.

So the policy lives in the native SDKs, where it is tested (32 cases in
RevnixSDK-iOS, 31 in `revnix-core`). This plugin's job is to not lose it in
translation.

## Quick start

```dart
import 'package:revnix_flutter/revnix_flutter.dart';

final revnix = await RevnixClient.configure(
  apiKey: 'rvx_pk_live_…',            // publishable key only
  baseUrl: 'https://your-deployment.convex.site',
);

// Safe on every launch — the server dedupes on the purchase key.
await revnix.retryPendingPurchases();
await revnix.registerInstall(platform: 'flutter');

// Gate. Never throws; unknown or unreachable means locked.
if (await revnix.isEntitled('pro')) {
  // …
}
```

Use a **publishable** key (`rvx_pk_…`). Secret keys must never ship in a binary,
so `identify`/`alias` are deliberately not methods here — proxy them from your
server.

## Registering purchases

```dart
// Apple — send the JWS or the claim is only provisional.
await revnix.registerPurchase(RegisterPurchaseInput(
  source: RevnixStore.apple,
  token: originalTransactionId,
  productId: 'pro.monthly',
  transactionId: transactionId,
  signedTransactionInfo: jwsRepresentation,
));

// Google — the purchase token is BOTH the token and the transaction id.
final result = await revnix.registerPurchase(RegisterPurchaseInput.google(
  purchaseToken: purchase.purchaseToken,
  productId: 'pro.monthly',
));

// Read-your-writes: unlock without polling yourself.
await revnix.waitForEntitlements(result.seq);
```

`result.provisional` is normally `true` on Android — a Play purchase carries no
device-side proof, so Revnix corroborates it server-side via RTDN. It is `false`
on iOS, where the JWS verifies against Apple's chain.

## A/B experiments

`resolvePlacement` sends the customer id so the server can pin a sticky
variant when a running experiment covers the placement. The served
offering/paywall are already the variant's — render what you get. The
assignment itself is attribution metadata:

```dart
final resolution = await revnix.resolvePlacement('onboarding');
// Null when no running experiment covers this placement.
final experiment = resolution.experiment;
if (experiment != null) {
  analytics.log('paywall_variant', {
    'experiment': experiment.key,
    'variant': experiment.variantId,
  });
}
```

### Targeting: `setAttributes`

A test can be narrowed to an *audience* — conditions over customer attributes.
`setAttributes` supplies the facts those conditions read, which for a
mobile-only app is the only place they exist:

```dart
await revnix.setAttributes({
  'country': 'US',
  'app_version': '4.2.0',
  'lifetime_orders': 3,
  'stale_key': null,   // null deletes the key
});
```

Values must be `String`, `num`, or `null`. This awaits the write and throws on
failure, unlike the fire-and-forget beacons, because the next
`resolvePlacement` may depend on it. Set an audience's attributes *before* the
first resolve on a covered placement — eligibility is checked at that resolve.
`email` and `username` are reserved (secret key, from your server), and an
attribute your backend already set cannot be changed from a device; both
reject the whole batch rather than applying part of it.

## Paywall UI

`RevnixPaywall` renders a dashboard-published paywall config as a full screen
— pure Dart over Flutter's own widgets, kept in lockstep with the dashboard's
paywall-builder preview and the React Native renderer. The config decides
layout, copy, accent, and badge; **you** supply package titles and localized
prices from the store, so the display never disagrees with the charge.

```dart
final resolution = await revnix.resolvePlacement('onboarding');
final paywall = resolution.paywall!;

RevnixPaywall(
  config: paywall.config,
  packages: [
    // priceLabel must be the store's localized price string.
    RevnixPaywallPackage(packageId: 'monthly', title: 'Monthly', priceLabel: r'$9.99'),
    RevnixPaywallPackage(packageId: 'annual', title: 'Annual', priceLabel: r'$59.99'),
  ],
  onPurchase: (packageId) { /* run the store purchase, then registerPurchase */ },
  onRestore: () { /* restore purchases */ },
  // One paywall.viewed per mount — the funnel's "Paywall displayed" stage.
  client: revnix,
  placementKey: 'onboarding',
  paywallId: paywall.paywallId,
)
```

Selection is controlled (`selectedPackageId` + `onSelectPackage`) or managed
internally; `loading: true` turns the CTA into a spinner. The plugin adds no
`url_launcher` dependency, so a dashboard-configured Terms/Privacy URL is
handed to your `onOpenUrl` callback to open — an explicit `onTerms`/`onPrivacy`
handler always wins over the config URL.

## Errors

Every native failure arrives as a typed `RevnixException` with `isRetryable`
intact, never a bare `PlatformException`.

```dart
try {
  await revnix.entitlements();
} on RevnixAuthException catch (err) {
  // 401/403 — key revoked or wrong kind. Deliberate; do NOT retry.
} on RevnixRateLimitException catch (err) {
  await Future<void>.delayed(Duration(milliseconds: err.retryAfterMs ?? 1000));
} on RevnixException catch (err) {
  if (err.isRetryable) showOfflineBanner();
}
```

The retryable/deliberate split is the contract: a transient failure serves the
cache, a deliberate rejection must surface, or there is no kill switch.
`isEntitled` is the exception — it never throws and resolves to `false`, so
gates fail closed.

## Status

**Builds; not published.** The plugin compiles and runs end to end on both
platforms — the native sources are vendored (see the note at the top), so it
no longer depends on unpublished CocoaPods/Maven artifacts. The Dart layer is
complete and tested (`flutter test` — 29 tests covering error rehydration, the
`stale` flag, gate fail-closed behaviour, and wire marshalling).

What remains is distribution: `revnix_flutter` 0.2.0 is not on pub.dev, so it
can only be consumed as a path or git dependency today. When the native SDKs
reach CocoaPods and Maven Central, the vendored copies should be dropped in
favour of real dependencies before publishing.

## v1 non-goals

- `identify` / `alias` — server-proxied by design.
- Web — Dart's `int` is a double on `dart2js`, which would lose precision on
  unix-ms timestamps and ledger cursors. Mobile only.
- Amazon and other stores.
