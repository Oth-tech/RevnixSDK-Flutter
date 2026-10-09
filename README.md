<p align="center">
  <a href="https://www.revnix.io"><img src="https://www.revnix.io/sdk/logo.png" width="360" alt="Revnix"></a>
</p>

<h1 align="center">Subscriptions, Paywalls and Attribution<br>for Your Flutter App</h1>

<p align="center">
  <a href="https://pub.dev/packages/revnix_flutter"><img src="https://img.shields.io/pub/v/revnix_flutter?color=2f6fe0&logo=dart" alt="pub version"></a>
  <a href="https://github.com/Oth-tech/RevnixSDK-Flutter/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-2f6fe0" alt="license"></a>
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android-2f6fe0?logo=flutter&logoColor=white" alt="platforms">
</p>

<p align="center">
  <a href="https://www.revnix.io"><b>Website</b></a> •
  <a href="https://www.revnix.io/docs/flutter"><b>Docs</b></a> •
  <a href="https://www.revnix.io/docs/flutter/reference"><b>API Reference</b></a>
</p>

![Revnix: subscriptions, paywalls and attribution for mobile apps](https://www.revnix.io/sdk/hero.png)

Revnix SDK makes in-app subscriptions, paywalls and attribution for Flutter fast and easy. One plugin buys through StoreKit 2 and Google Play Billing, validates the receipt on the server and unlocks the entitlement. No separate IAP plugin.

## Table of Contents

- [Why Revnix?](#why-revnix)
- [Getting Started](#getting-started)
- [Quick start](#quick-start)
- [Purchases and entitlements without server code](#purchases-and-entitlements-without-server-code)
- [Paywalls that update without app releases](#paywalls-that-update-without-app-releases)
- [A/B tests with a built-in holdout](#ab-tests-with-a-built-in-holdout)
- [Attribution and deep links](#attribution-and-deep-links)
- [Real-time analytics for your Flutter app](#real-time-analytics-for-your-flutter-app)
- [Requirements](#requirements)
- [Documentation](#documentation)
- [Migrating from another SDK](#migrating-from-another-sdk)
- [Support](#support)
- [License](#license)

## Why Revnix?

- [Purchases in one call](https://www.revnix.io/docs/flutter/make-purchases). `purchase()` opens the App Store or Google Play sheet, validates the receipt on the server and grants the entitlement. No IAP plugin, no server code.
- [Entitlements that work offline](https://www.revnix.io/docs/flutter/check-entitlements). Entitlement checks are cached on device, so a user who paid stays unlocked without a network.
- [Remote paywalls](https://www.revnix.io/docs/paywall-builder). Design paywalls in the dashboard, pick from 250 templates and ship copy, prices and layout changes without an app release.
- [A/B tests and holdouts](https://www.revnix.io/docs/ab-tests). Split a placement between variants, measure revenue per user with credible intervals and ship the winner from the dashboard.
- [Attribution and deep links](https://www.revnix.io/docs/attribution). Install attribution, deferred deep links, Apple Search Ads, Google Ads and MMP forwarding, all from the same plugin.
- [Integrations](https://www.revnix.io/docs/integrations). Send subscription events to analytics, attribution and messaging tools, or to your own server through signed webhooks.
- [Real-time analytics](https://www.revnix.io/docs/analytics). Revenue, MRR, LTV, ROAS, cohorts and funnels for iOS and Android, filtered by store, product, channel and campaign.

## Getting Started

```sh
flutter pub add revnix_flutter
```

The native Swift and Kotlin SDKs ship inside the plugin and compile with your app. There is nothing else to add on iOS or Android.

Read the [installation guide](https://www.revnix.io/docs/flutter/installation) and [configuration reference](https://www.revnix.io/docs/flutter/configuration) to set up the plugin.

## Quick start

```dart
import 'package:revnix_flutter/revnix_flutter.dart';

// 1. Configure once at app start
final revnix = await RevnixClient.configure(
  apiKey: 'rvx_pk_live_…',
  baseUrl: 'https://<your-deployment>.convex.site',
);
await revnix.retryPendingPurchases();
await revnix.registerInstall();

// 2. Buy: opens the store sheet, validates the receipt, grants the entitlement
final result = await revnix.purchase('pro.monthly');
if (result != null) await revnix.waitForEntitlements(result.seq);

// 3. Check access anywhere
if (await revnix.isEntitled('pro')) {
  // unlocked
}
```

Your API key and deployment URL are in the dashboard under Settings. See [API keys](https://www.revnix.io/docs/api-keys).

## Purchases and entitlements without server code

**Revnix handles the hard parts of subscriptions in a small, developer-friendly plugin.**

- `purchase(productId)` runs the whole flow: store sheet, server-side receipt validation, entitlement, transaction finish. `restore()` brings purchases back on a new device.
- Renewals, refunds, upgrades and purchases on other devices are picked up from the stores and reflected in the entitlement on their own.
- Entitlements and placements are cached on device, so paid users stay unlocked offline. `isEntitled()` never throws and fails closed.
- Failed registrations are queued durably; `retryPendingPurchases()` drains the queue on the next launch.
- Typed errors: `purchase_blocked`, `product_not_found`, `store_error` and more, each a `RevnixException` with `isRetryable`. See [Make purchases](https://www.revnix.io/docs/flutter/make-purchases).
- Already using `in_app_purchase`? Keep it and call `registerPurchase()` instead.

## Paywalls that update without app releases

![Revnix paywall builder: element tree, background library and a live iPhone preview](https://www.revnix.io/sdk/react-native/paywalls.png)

With the [Revnix paywall builder](https://www.revnix.io/docs/paywall-builder) you design the paywall in the dashboard and render it in your app.

- **Pure Flutter renderer**: `RevnixPaywall` draws the published design with Flutter's own widgets, kept in lockstep with the dashboard preview. No WebView, no extra dependency.
- **250 templates**: pick a layout, theme and accent, then edit copy, packages and badges.
- **Update without redeploying**: change prices, copy or layout any time; the next `resolvePlacement()` picks it up.
- **Implicit placements**: `app_launch`, `session_start`, `paywall_decline` and three more fire without a resolve call.
- **Localized**: 43 languages for the built-in strings, plus per-locale copy of your own. `RevnixClient.setLocale()` overrides the device language.

Learn more in [Show paywalls](https://www.revnix.io/docs/flutter/show-paywalls) and [Placements](https://www.revnix.io/docs/placements).

## A/B tests with a built-in holdout

![Revnix A/B test results with a winner and credible intervals](https://www.revnix.io/sdk/react-native/ab-test.png)

- Split a placement's traffic between offering and paywall variants. Conversions, trials, revenue per user and MRR are calculated per variant.
- Add a **holdout** variant that shows no paywall at all, to measure what the paywall is really worth.
- Bayesian results with 95% credible intervals and a sample-size planner, so you know when to stop.
- Target a test at an audience with `setAttributes()`. Ship the winner from the dashboard; the plugin needs no change.

Learn more in [A/B tests](https://www.revnix.io/docs/ab-tests).

## Attribution and deep links

![Revnix MRR by country, last 90 days](https://www.revnix.io/sdk/react-native/attribution.png)

- **Install attribution** from Revnix links, with per-link click lookback windows. `getAttribution()` and `onAttribution` expose the verdict. See [Attribution](https://www.revnix.io/docs/attribution).
- **Deferred deep links** resolve on first launch through `onDeferredDeepLink`, so a user who installs from a campaign lands on the right screen. See [Deferred deep links](https://www.revnix.io/docs/deferred-deep-links).
- **Apple Search Ads** and **Google Ads** attribution, with App Tracking Transparency via `requestTrackingAuthorization()`. See [Apple Search Ads](https://www.revnix.io/docs/apple-search-ads) and [Google Ads](https://www.revnix.io/docs/google-ads-attribution).
- **MMP forwarding** to AppsFlyer and Adjust with `setAttribution()`, **ad revenue** logging with `logAdRevenue()` and **uninstall measurement** with `setPushToken()`. See [MMP attribution](https://www.revnix.io/docs/mmp-attribution), [Ad revenue](https://www.revnix.io/docs/ad-revenue) and [Uninstall measurement](https://www.revnix.io/docs/uninstall-measurement).
- **SKAdNetwork** conversion values with `updateSkanConversionValue()`. See [SKAdNetwork](https://www.revnix.io/docs/skadnetwork).
- **Fraud prevention**: anonymous-IP and click-injection checks keep paid channels honest. See [Fraud prevention](https://www.revnix.io/docs/fraud-prevention).

## Real-time analytics for your Flutter app

![Revnix overview: active subscriptions, revenue and MRR over 90 days](https://www.revnix.io/sdk/react-native/analytics.png)

- Revenue, MRR, ARR, ARPU, LTV and ROAS, updated from the ledger as purchases arrive.
- Cohorts, retention, funnels and predicted LTV. See [Analytics](https://www.revnix.io/docs/analytics).
- Filter and group by store, product, country, channel, campaign and A/B test variant.
- Custom events with `track()`. Saved reports, alerts and a REST API for your own dashboards. See [Reports](https://www.revnix.io/docs/reports) and [REST API](https://www.revnix.io/docs/rest-api).

## Requirements

| Requirement | Minimum |
| --- | --- |
| Flutter | 3.32 (Dart 3.8) |
| iOS | 16.0 |
| Android | API 24 (Android 7.0) |
| JDK (Android build) | 17 |

The plugin is mobile only. Web, desktop and stores other than the App Store and Google Play are not supported.

## Documentation

- [Overview](https://www.revnix.io/docs/flutter)
- [Installation](https://www.revnix.io/docs/flutter/installation)
- [Configuration](https://www.revnix.io/docs/flutter/configuration)
- [Make purchases](https://www.revnix.io/docs/flutter/make-purchases)
- [Check entitlements](https://www.revnix.io/docs/flutter/check-entitlements)
- [Show paywalls](https://www.revnix.io/docs/flutter/show-paywalls)
- [API reference](https://www.revnix.io/docs/flutter/reference)

Revnix also ships SDKs for [React Native](https://www.revnix.io/docs/react-native), [iOS](https://www.revnix.io/docs/ios), [Android](https://www.revnix.io/docs/android), [Capacitor](https://www.revnix.io/docs/capacitor) and [Unity](https://www.revnix.io/docs/unity).

## Migrating from another SDK

Moving from Adapty or RevenueCat? Revnix imports your customers and purchase history, and the SDK calls map one to one.

- [Migrate from Adapty](https://www.revnix.io/docs/migrate-from-adapty)
- [Migrate from RevenueCat](https://www.revnix.io/docs/migrate-from-revenuecat)

## Support

- Email [support@revnix.io](mailto:support@revnix.io) with questions, bugs or feature requests.
- Check the [status page](https://www.revnix.io/status) for incidents.
- Want to work on the plugin itself? Clone with `git clone --recurse-submodules`: the native SDKs live in `ios/revnix_flutter/Revnix` and `android/revnix-kotlin` and are never edited from here.

## License

Revnix SDK is available under the MIT license. See [LICENSE](https://github.com/Oth-tech/RevnixSDK-Flutter/blob/main/LICENSE) for details.
