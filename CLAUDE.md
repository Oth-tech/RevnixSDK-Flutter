# RevnixSDK-Flutter

Flutter plugin `revnix_flutter` (pub.dev, publisher revnix.io, repo `Oth-tech/RevnixSDK-Flutter`, default branch `main`). Subscriptions, entitlements, placements/paywalls, A/B, attribution and deep links against the Revnix backend (`../revnix-app`, Convex HTTP `/v1`, `baseUrl` passed by the app). Mobile only (iOS + Android).

## Stack
- Version lives in TWO files: `pubspec.yaml` (`version:`) and `ios/revnix_flutter.podspec` (`s.version`). `scripts/release.sh` bumps both plus CHANGELOG; never hand-bump.
- Dart `sdk: ^3.8.0`, Flutter `>=3.32.0`. Runtime dep: only `flutter`. Dev: `flutter_test`, `flutter_lints ^6.0.0` (`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`, excludes `build/** android/** ios/**`).
- Android (`android/build.gradle.kts`): Kotlin 2.3.20, AGP 9.0.1, compileSdk 36, minSdk 24, JDK 17. iOS: deployment target 16.0, Swift 5, CocoaPods podspec AND SwiftPM (`ios/revnix_flutter/Package.swift`).
- No HTTP or billing of its own. It WRAPS the native SDKs (StoreKit 2 / Play Billing 8); offline cache, retry queue and signing live in the natives. Never reimplement resilience in Dart.

## Native SDKs are git submodules, compiled in
- `android/revnix-kotlin` = `Oth-tech/RevnixSDK-Android` (`../RevnixSDK-Android`); `ios/revnix_flutter/Revnix` = `Oth-tech/RevnixSDK-iOS` (`../RevnixSDK-iOS`). See `.gitmodules`.
- Android: `build.gradle.kts` adds the submodule's `revnix-core` + `revnix-android` `src/main/kotlin` to `java.srcDirs` and re-declares their dependencies by hand (coroutines, kotlinx-serialization, okhttp, billing-ktx 8.3.0, installreferrer, play integrity). A new native dependency upstream must be copied into this file. INTERNET permission is in `android/src/main/AndroidManifest.xml` (submodule manifests are not merged).
- iOS: the podspec globs `Revnix/Sources/Revnix/**/*.swift` plus the plugin sources; SwiftPM needs the submodule INSIDE `ios/revnix_flutter/`.
- Never edit submodule files here: change upstream, release there, then re-pin. `pub publish` archives the working tree including submodule files. Fresh clone needs `git submodule update --init`.

## Structure
- `lib/revnix_flutter.dart`: the only public entry (exports). `lib/src/revnix_client.dart`: `RevnixClient` singleton (`configure(apiKey:, baseUrl:, …)` then `.instance`); `models.dart`, `errors.dart`.
- `lib/src/ui/`: Dart-rendered paywall (`revnix_paywall.dart`, `paywall_blocks.dart`, `paywall_background.dart`, `paywall_geometry.dart`, `paywall_localization.dart`) rendering the server paywall JSON forwarded raw from the natives.
- Bridges: `android/src/main/kotlin/com/revnix/revnix_flutter/RevnixFlutterPlugin.kt` (~650 lines), `ios/revnix_flutter/Sources/revnix_flutter/RevnixFlutterPlugin.swift` (~620 lines).
- `example/`: app with path dep `../` (`lib/main.dart` configures with a test key, shows customer id + `pro` entitlement), plus `example/integration_test/` and `example/test/`.
- `test/`: 24 Dart unit tests, one per API area, plus `test/paywall-*-wire.json` fixtures. No Android unit tests. `build/` and `.dart_tool/` are generated.

## Platform channels (names must match Dart, Kotlin and Swift)
- MethodChannel `com.revnix/revnix_flutter`; EventChannels `com.revnix/revnix_flutter/diagnostics`, `…/implicit`, `…/deferred_deep_link`, `…/attribution`.
- Dart `RevnixClient._invoke(method, args)` → `onMethodCall` switch in both plugins. Adding an API = Dart method + Kotlin case + Swift case + `test/<area>_test.dart` (tests mock a channel passed through the `@visibleForTesting channel:` parameter of `configure`).
- Purchases: built-in `purchase(productId)` (null = cancelled/pending) and `restore()`; `registerPurchase` for apps on their own IAP plugin. Attribution/deep links: `handleDeepLink`, `resolveDeepLink`, `getLastDeepLink`, `onDeferredDeepLink`, `handleInstallReferrer`, `setAttribution`, `getAttribution` / `onAttribution`, `updateSkanConversionValue`, `requestTrackingAuthorization`.

## Commands
Flutter is not on PATH on this Mac: `export PATH="$HOME/development/flutter/bin:$PATH"`.
```bash
flutter pub get
flutter analyze                       # exits 1 on infos; CI uses stable, which may be newer than local
flutter test                          # single: flutter test test/purchase_test.dart
flutter pub publish --dry-run         # CI asserts the archive contains revnix-kotlin and Revnix
cd example && flutter run             # needs a real key + baseUrl in lib/main.dart; iOS needs the Xcode license accepted
```
- `scripts/release.sh --bump auto|major|minor|patch [--version x.y.z] [--dry-run]` is CI's; locally only `--dry-run`. Bump derives from `## Unreleased` in `CHANGELOG.md` (`### Breaking` → major, `### Added` → minor, else patch).

## Git, CI, release
- `.github/workflows/ci.yml` (job `check`): PRs to `main` + manual; submodules recursive, `subosito/flutter-action` stable, analyze, test, publish dry-run content check.
- `.github/workflows/release.yml`: manual dispatch (bump/version/app_sha/run_key), dispatched by `../revnix-app/.github/workflows/release-sdks.yml` (job `revnix-flutter`, after `revnix-ios`). Analyzes/tests main, moves submodules to upstream `main` (`submodule update --remote`), runs release.sh, opens + merges the bump PR with `--merge`, tags `vX.Y.Z`, then dispatches `publish.yml` (tags pushed with `GITHUB_TOKEN` don't trigger workflows).
- `.github/workflows/publish.yml`: tag `v*.*.*` or dispatch; tests, tag must equal the pubspec version, native sources must be in the archive, `flutter pub publish --force` via OIDC (`id-token: write`).
- Never hand-push a version tag. Merge commits only into `main` (ruleset; squash is refused). Opposite of revnix-app, which squash-merges into `dev`.

## Gotchas
- `/usr/bin/git` is blocked by the Xcode license prompt on this Mac (which also blocks local iOS builds). Read-only git: `/Applications/GitHub Desktop.app/Contents/Resources/app/git/bin/git`; that binary has no `submodule` subcommand here.
