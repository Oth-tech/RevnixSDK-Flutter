## Unreleased

- **`updateSkanConversionValue(value, coarse:, lockWindow:)` and
  `configure(skan:)`** (iOS only, AT10).

- **`logAdRevenue`.** Report impression-level ad revenue from your mediation
  SDK's paid-event callback (AdMob `onPaidEvent`, AppLovin MAX
  `onAdRevenuePaid`). Fire-and-forget like the other beacons. (PT8)

- **`getAttribution` / `onAttribution`.** The install-attribution verdict —
  which channel gets credit for this install, and the campaign fields that
  came with it — straight from the native SDK's own record.
  `getAttribution()` is a point-in-time read; `onAttribution` delivers the
  same verdict once the native SDK settles on it after cold-start install
  registration, and again whenever it later changes (de-duplicated
  natively). (AT11)

- **`getLastDeepLink`.** Reads the link the customer clicked most recently,
  straight from the native SDK's own deep-link handling, without waiting on
  a stream. Never throws; returns null when nothing has been recorded yet.

- **`resolveDeepLink`.** Unwraps a link an email service provider (Mailchimp,
  SendGrid, ...) wrapped in its own click-tracking domain, e.g.
  `https://click.mailchimp.com/track/abc` becomes
  `com.voigu.app://promo?utm_source=email&utm_campaign=summer50`. Route on
  the result and pass it to `handleDeepLink`; never throws, and a failure
  hands the input `url` back unchanged. (REV-299)

- **`onDeferredDeepLink` / `handleInstallReferrer`.** The link a customer
  clicked before installing, echoed once per install through the
  `onDeferredDeepLink` stream — exact on Android (from the install
  referrer), probabilistic on iOS (same-network click within the last hour).
  `handleInstallReferrer(referrer)` hands the raw Play Install Referrer
  string to the native Android SDK; a no-op on iOS. (REV-299)

- **On-device QR paywall preview.** `PlacementResolution.preview` and
  `revnixPreviewPlacementKey` decode a dashboard QR/link preview trigger, and
  `RevnixPaywall` refuses to purchase for that placement key. Needs the
  revnix-swift / revnix-kotlin submodule pins that recognize the preview deep
  link and forward it on `implicitPaywalls` — inert here until those land
  (the plugin bridges must then also forward `preview`; until then detect a
  preview by `placementKey`).

- **Device attribute contract.** The native SDKs now send the device facts —
  platform, OS version, app version, locale, currency, storefront, model,
  install date, SDK version, sandbox, first open — with every placement
  resolve (`X-Revnix-Device`), so targeting rules and audiences can use them
  from the first launch and the dashboard shows them on the customer as
  `device.*` attributes. `configure(device: {…})` overrides individual keys.
  Requires revnix-swift 0.3.0 / revnix-kotlin 0.3.0 (the submodules).
  (REV-268)

- **Five style fields the designs use now reach the renderer.** `translate`,
  `clipPath`, `fillSize`, `textWrap` and `filter` were named by no property on
  `BlockStyle`, so `fromJson` dropped them before the renderer ever saw them.
  `translate` is now drawn: 5 of the 25 template categories centre a pinned
  badge with `left: 50%` plus `translate: "-50% 0"`, and without the second
  half the chip sat half its own width off centre — on Flutter only, never in
  the dashboard preview the design was approved in. `clipPath`, `fillSize` and
  `filter` are decoded and reported through `onDiagnostic` (`clipPath not
  drawn`, `fillSize not tiled`, `filter not drawn`) rather than silently
  ignored, so a design that renders approximately says so in your logs.
  `textWrap` is decoded but not reported: it moves a line break, not the
  design, and half the gallery sets it.
- **`logPaywallEvent` — the six paywall interactions** (`selected`,
  `purchaseStarted`, `purchaseAbandoned`, `purchaseFailed`, `restore`,
  `error`), i.e. what the customer did BETWEEN the display and the close.
  `RevnixPaywall` sends all but the purchase outcome, which only your app can
  see. All six are pure history: over-reporting skews a report, it never
  grants or revokes access. `logPaywallShown` now resolves with the `viewId` it
  minted — hold it and pass it to `logPaywallClosed` and `logPaywallEvent` so
  the whole life of one impression threads together.
- **The selected plan is drawn from the design.** Every block carries
  `selectedStyle` and `visibility`, so a plan card can change its fill, border
  and text when its package is the selected one, and a block can be drawn only
  while selected (a filled radio dot) or only while not.
- The native SDKs are git submodules (`ios/revnix_flutter/Revnix` → RevnixSDK-iOS,
  `android/revnix-kotlin` → RevnixSDK-Android) instead of vendored copies,
  which had already drifted from upstream. Clone with
  `--recurse-submodules`. Both bridges now forward the placement's `paywall`
  as the raw wire value (upstream `paywallJSON` / `paywallJson`), so a
  designed paywall from a newer dashboard reaches Dart untouched. Until the
  package is on pub.dev, install it as a path dependency from a recursive
  clone: a pubspec `git:` dependency does not fetch submodules.
- The Swift package's iOS floor is 16.0, matching the podspec and
  revnix-swift (it said 13.0).

## 0.2.0

A/B experiments (REV-219) — parity with `revnix-swift` 0.2.0 and
`revnix-kotlin` 0.2.0, whose vendored copies are updated in step.

- `PlacementResolution.experiment` — the running experiment's sticky
  assignment (`PlacementExperiment`: `key`, `variantId`). Null when no
  running experiment covers the placement (or the server predates
  experiments); the served offering/paywall are already the variant's, so
  this is attribution metadata, not something to branch on.
- `resolvePlacement` now sends the customer id (`?customer=`) so the server
  can pin a sticky variant; older servers ignore the parameter.
- `setAttributes(Map<String, Object?>)` (REV-033) — the write half of
  audience targeting. String/num values upsert, `null` deletes. Awaits the
  write and throws on failure, unlike the fire-and-forget beacons, since the
  next `resolvePlacement` may depend on it. `email`/`username` are reserved
  (secret key only) and a server-set attribute cannot be changed from a
  device; both reject the whole batch.

## 0.1.0

Initial release — feature parity with `revnix-swift` 0.1.0 and
`revnix-kotlin` 0.1.0, which this plugin bridges (vendored until they ship to
CocoaPods / Maven Central).

- `RevnixClient.configure` / `instance` — publishable-key client, one per app
- Entitlements: network-first `entitlements()` with offline cache (`stale`
  survives the channel), `cachedEntitlements()`, fail-closed `isEntitled()`,
  read-your-writes `waitForEntitlements(seq)`
- Purchases: `registerPurchase` (StoreKit 2 JWS proof path on iOS,
  purchase-token claims on Android), durable retry queue
  (`retryPendingPurchases`, `pendingPurchaseCount`); Play Billing
  acknowledgement ordering lives in the native connector
- Placements: `resolvePlacement` with remote paywall config
- Telemetry: `registerInstall`, `logPaywallShown`, `diagnostics` stream
- Typed error taxonomy (`RevnixException` subclasses) — retryable vs
  deliberate is preserved across the platform channel
