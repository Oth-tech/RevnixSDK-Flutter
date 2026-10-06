# revnix_flutter_example

Demonstrates how to use the revnix_flutter plugin.

`lib/main.dart` configures `RevnixClient` with a test publishable key,
drains the purchase retry queue with `retryPendingPurchases`, registers the
install, then shows the customer id and `pro` entitlement, first from
`cachedEntitlements()` (instant, offline-safe) and then from `entitlements()`
once the network answer lands.

## Running it

```
git submodule update --init
flutter run
```

Put a test publishable key (`rvx_pk_test_…`) and your deployment's
`baseUrl` in the `RevnixClient.configure` call in `lib/main.dart` before
running.
