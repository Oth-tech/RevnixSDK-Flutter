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
