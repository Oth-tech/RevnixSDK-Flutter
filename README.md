# revnix_flutter

Flutter plugin for [Revnix](https://revnix.com) — subscriptions and
entitlements, wrapping the native SDKs rather than reimplementing them.

- **iOS** → [`revnix-swift`](https://github.com/Oth-tech/revnix-swift) (StoreKit 2)
- **Android** → [`revnix-kotlin`](https://github.com/Oth-tech/revnix-kotlin) (Play Billing 8)

## Why a wrapper and not a Dart client

The resilience policy — offline cache, retry queue, kill-switch discipline — is
a *product contract*, not an implementation detail. Reimplementing it per
platform means one more place for it to silently rot. It already happened once:
the Swift port dropped a TTL bypass and broke post-purchase unlock until a test
caught it.

So the policy lives in the native SDKs, where it is tested (27 cases in
revnix-swift, 26 in revnix-core). This plugin's job is to not lose it in
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

**Not published.** The Dart layer is complete and tested (`flutter test` — 25
tests covering error rehydration, the `stale` flag, gate fail-closed behaviour,
and wire marshalling). The native plugin code is written but **cannot be
compiled yet**: it depends on `Revnix` (CocoaPods) and
`com.revnix:revnix-android` (Maven), neither of which is published. Publishing
the two native SDKs unblocks it.

## v1 non-goals

- Paywall UI rendering — `resolvePlacement` ships the config, your app renders it.
- `identify` / `alias` — server-proxied by design.
- Web — Dart's `int` is a double on `dart2js`, which would lose precision on
  unix-ms timestamps and ledger cursors. Mobile only.
- Amazon and other stores.
