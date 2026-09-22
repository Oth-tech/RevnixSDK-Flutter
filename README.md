# revnix_flutter

Flutter plugin for [Revnix](https://revnix.io), subscriptions and
entitlements, wrapping the native SDKs rather than reimplementing them.

- **iOS** → [`RevnixSDK-iOS`](https://github.com/Oth-tech/RevnixSDK-iOS) (StoreKit 2)
- **Android** → [`RevnixSDK-Android`](https://github.com/Oth-tech/RevnixSDK-Android) (Play Billing 8)

> Those SDKs are not on CocoaPods / Maven Central yet, so this plugin carries
> them as **git submodules** (`ios/revnix_flutter/Revnix`, `android/revnix-kotlin`) and
> compiles their sources straight into the plugin. Clone with
> `git clone --recurse-submodules` (or run `git submodule update --init`
> in an existing checkout). To pick up a native fix, bump the submodule pin;
> never edit the native sources from here.

## Why a wrapper and not a Dart client

The resilience policy (offline cache, retry queue, kill-switch discipline) is
a *product contract*, not an implementation detail. Reimplementing it per
platform means one more place for it to silently rot. It already happened once:
the Swift port dropped a TTL bypass and broke post-purchase unlock until a test
caught it.

So the policy lives in the native SDKs, where it is tested (in
RevnixSDK-iOS and `revnix-core`). This plugin's job is to not lose it in
translation.

## Quick start

```dart
import 'package:revnix_flutter/revnix_flutter.dart';

final revnix = await RevnixClient.configure(
  apiKey: 'rvx_pk_live_…',            // publishable key only
  baseUrl: 'https://your-deployment.convex.site',
);

// Safe on every launch; the server dedupes on the purchase key.
await revnix.retryPendingPurchases();
await revnix.registerInstall();

// Gate. Never throws; a transient failure answers from the cache; a deliberate
// rejection, unknown entitlement, or unreachable with nothing cached, means locked.
if (await revnix.isEntitled('pro')) {
  // …
}
```

Use a **publishable** key (`rvx_pk_…`). Secret keys must never ship in a binary,
so `identify`/`alias` are deliberately not methods here; proxy them from your
server.

## Registering purchases

```dart
// Apple: send the JWS or the claim is only provisional.
await revnix.registerPurchase(RegisterPurchaseInput(
  source: RevnixStore.apple,
  token: originalTransactionId,
  productId: 'pro.monthly',
  transactionId: transactionId,
  signedTransactionInfo: jwsRepresentation,
));

// Google: the purchase token is BOTH the token and the transaction id.
final result = await revnix.registerPurchase(RegisterPurchaseInput.google(
  purchaseToken: purchase.purchaseToken,
  productId: 'pro.monthly',
));

// Read-your-writes: unlock without polling yourself.
await revnix.waitForEntitlements(result.seq);
```

`result.provisional` is normally `true` on Android: a Play purchase carries no
device-side proof, so Revnix corroborates it server-side via RTDN. It is `false`
on iOS, where the JWS verifies against Apple's chain.

## A/B experiments

`resolvePlacement` sends the customer id so the server can pin a sticky
variant when a running experiment covers the placement. The served
offering/paywall are already the variant's; render what you get. The
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

A test can be narrowed to an *audience*: conditions over customer attributes.
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
first resolve on a covered placement; eligibility is checked at that resolve.
`email` and `username` are reserved (secret key, from your server), and an
attribute your backend already set cannot be changed from a device; both
reject the whole batch rather than applying part of it.

## Paywall UI

`RevnixPaywall` renders a dashboard-published paywall config as a full screen (pure Dart over Flutter's own widgets), kept in lockstep with the dashboard's
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
  // One paywall.viewed per mount: the funnel's "Paywall displayed" stage.
  client: revnix,
  placementKey: 'onboarding',
  paywallId: paywall.paywallId,
)
```

Selection is controlled (`selectedPackageId` + `onSelectPackage`) or managed
internally; `loading: true` turns the CTA into a spinner. The plugin adds no
`url_launcher` dependency, so a dashboard-configured Terms/Privacy URL is
handed to your `onOpenUrl` callback to open; an explicit `onTerms`/`onPrivacy`
handler always wins over the config URL.

### Reporting the whole life of a display

Passing `client:` reports the impression. `RevnixPaywall` also reports the
close and most interactions; rendering your own paywall, these are yours:

| Call | What it does |
|---|---|
| `logPaywallShown(…) → Future<String?>` | The impression beacon, resolving with the `viewId` it minted. |
| `logPaywallClosed(viewId, …)` | Ends that display. Idempotent per view id, so a retry or a double-dismiss cannot count two. Without it a funnel knows how many saw the paywall, not how many left without buying. |
| `logPaywallEvent(event, viewId, …)` | One of six interactions — `selected`, `purchaseStarted`, `purchaseAbandoned`, `purchaseFailed`, `restore`, `error` — i.e. what happened BETWEEN the display and the close. |

The purchase **outcome** is always yours, even with the built-in renderer:
your app performs the `in_app_purchase` call, so only your app sees whether
the sheet was cancelled or the card was declined.

```dart
final viewId = await revnix.logPaywallShown(
  placementKey: 'onboarding', paywallId: paywall.paywallId) ?? '';

// From your own in_app_purchase error handling.
await revnix.logPaywallEvent(
  RevnixPaywallEvent.purchaseAbandoned, viewId, productId: productId);

await revnix.logPaywallClosed(viewId, placementKey: 'onboarding');
```

All six are pure ledger history: over-reporting can skew a report, it can
never grant or revoke access.

### Implicit placements

Six placements resolve without a `resolvePlacement` call: `app_install`,
`app_launch`, `session_start`, `deeplink_open`, `paywall_decline` and
`transaction_abandon`. Opt in with `implicitPlacements: true` (off by default)
and listen on `implicitPaywalls`; the native SDKs watch the foreground for
`session_start` and ask `GET /v1/config` once so an app that configured none
of the six costs one cached request per launch.

```dart
final revnix = await RevnixClient.configure(
  apiKey: 'rvx_pk_live_…', baseUrl: 'https://….convex.site',
  implicitPlacements: true,
);
revnix.implicitPaywalls.listen((trigger) => showPaywall(trigger.resolution));

// deeplink_open is the one moment the SDK cannot see itself:
appLinks.uriLinkStream.listen((uri) => revnix.handleDeepLink(uri.toString()));
```

With app_links 6 or later, `uriLinkStream` delivers the link that launched
the app as its first event and every link after it, and does not replay it
on a hot restart or a second subscription — subscribe once at startup and
do not also call `getInitialLink()`; it is the same cold-start link and
would count twice. On uni_links or app_links 5 and earlier the stream
carries only links that arrive while running, so also hand over
`getInitialLink()` once at startup.

Pass `placementKey: trigger.resolution.placementKey` to `RevnixPaywall` —
that marks the display as implicit and is what stops a `paywall_decline`
paywall from firing `paywall_decline` again. A close is a decline: never
report one for a display that ended in a purchase.

The dashboard QR/link preview (`<scheme>://revnix-preview?revnix_preview=…`)
arrives the same way — hand the URL to `handleDeepLink` and it comes back on
`implicitPaywalls` like any other trigger, detectable by
`resolution.placementKey == revnixPreviewPlacementKey`. `RevnixPaywall`
already refuses to call `onPurchase` for that placement key, showing a
"Purchases are disabled in preview." dialog instead;
a custom UI rendering the preview itself must add the same check.

### Deferred deep links

The link a customer clicked before they had the app, echoed back once per
install. Unlike the Unity and Capacitor SDKs, Flutter never calls
`registerInstall` on its own — call it yourself after `configure()`, as in
the quick start above, or the iOS side of this event never fires:

```dart
revnix.onDeferredDeepLink.listen((event) {
  final (url, match) = event;
  route(url); // match is DeferredDeepLinkMatch.exact or .probabilistic
});

// Android now reads the Play install referrer itself during configure() —
// you don't need to call this. It still exists for a host that reads the
// referrer some other way; a second call just double-reports, which the
// server absorbs harmlessly. No-op on iOS.
await revnix.handleInstallReferrer(referrer);
```

Unwrap a click-tracking link from an email service provider before routing
on it, from the same entry point:

```dart
final resolved = await revnix.resolveDeepLink(rawUrl);
route(resolved);
await revnix.handleDeepLink(resolved);
```

The most recent link the customer clicked, read straight from the native
SDK's own record rather than a stream. Never throws; null if nothing has
been recorded yet:

```dart
final last = await revnix.getLastDeepLink();
if (last != null) route(last.url);
```

## Errors

Every native failure arrives as a typed `RevnixException` with `isRetryable`
intact, never a bare `PlatformException`.

```dart
try {
  await revnix.entitlements();
} on RevnixAuthException catch (err) {
  // 401/403: key revoked or wrong kind. Deliberate; do NOT retry.
} on RevnixRateLimitException catch (err) {
  await Future<void>.delayed(Duration(milliseconds: err.retryAfterMs ?? 1000));
} on RevnixException catch (err) {
  if (err.isRetryable) showOfflineBanner();
}
```

The retryable/deliberate split is the contract: a transient failure serves the
cache, a deliberate rejection must surface, or there is no kill switch.
`isEntitled` is the exception; it never throws. A transient failure answers
from the offline cache; a deliberate rejection, or a failure with nothing
cached, resolves to `false`, so gates fail closed and a revoked key still
locks out a cached snapshot.

## Status

**Builds; not published.** The plugin compiles and runs end to end on both
platforms; the native SDKs come in as git submodules (see the note at the
top), so it does not depend on unpublished CocoaPods/Maven artifacts. The Dart layer is
complete and tested (`flutter test`, covering error rehydration, the
`stale` flag, gate fail-closed behaviour, wire marshalling, implicit placements
and the paywall renderer).

What remains is distribution: `revnix_flutter` 0.3.0 is not on pub.dev, so it
can only be consumed as a **path dependency** today, from a checkout cloned
with `--recurse-submodules`. A pubspec `git:` dependency does not work: pub
does not fetch submodules, so the native sources would be missing. The pub.dev
archive does include the submodule contents (`flutter pub publish --dry-run`
lists them), so publishing needs no extra step. When the native SDKs
reach CocoaPods and Maven Central, the submodules should be swapped for real
dependencies before publishing: one line each in `ios/revnix_flutter.podspec`
and `android/build.gradle.kts`, both marked in place.

## v1 non-goals

- `identify` / `alias`: server-proxied by design.
- Web, Dart's `int` is a double on `dart2js`, which would lose precision on
  unix-ms timestamps and ledger cursors. Mobile only.
- Amazon and other stores.
