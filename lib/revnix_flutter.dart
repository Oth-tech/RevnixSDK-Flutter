/// Revnix for Flutter — subscriptions and entitlements over the native SDKs.
///
/// The plugin wraps `revnix-swift` (StoreKit 2) and `revnix-kotlin` (Play
/// Billing 8). The resilience policy lives in those native SDKs and is not
/// reimplemented here — see the README for what that policy guarantees.
library;

export 'src/errors.dart';
export 'src/models.dart';
export 'src/revnix_client.dart';
export 'src/ui/revnix_paywall.dart';
