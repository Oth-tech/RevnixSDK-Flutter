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
