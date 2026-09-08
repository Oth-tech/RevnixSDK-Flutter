import Flutter
import UIKit
// revnix-swift is the git submodule at ios/revnix_flutter/Revnix. Under Swift Package
// Manager it is its own module (imported here); under CocoaPods the podspec
// compiles the same sources into this module, so there is nothing to import.
#if canImport(Revnix)
    import Revnix
#endif

/// iOS side of the Flutter bridge — a thin adapter over `revnix-swift`.
///
/// Deliberately holds no policy of its own: the offline cache, retry queue,
/// and kill-switch discipline all live in `RevnixClient`. This file's only
/// jobs are marshalling and, critically, preserving the error taxonomy across
/// the channel so a 401 does not arrive in Dart as a generic failure.
public class RevnixFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var client: RevnixClient?
    private var observer: Task<Void, Never>?
    private var diagnosticsSink: FlutterEventSink?
    /// REV-272: implicit-placement triggers. Its own channel rather than a
    /// second message shape on the diagnostics stream — a paywall to present
    /// and a swallowed background failure are different subscriptions with
    /// different lifetimes, and merging them would make Dart filter every
    /// diagnostic to find a trigger.
    private var implicitSink: FlutterEventSink?
    private let implicitStreamHandler = ImplicitStreamHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RevnixFlutterPlugin()
        let channel = FlutterMethodChannel(
            name: "com.revnix/revnix_flutter",
            binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)

        let events = FlutterEventChannel(
            name: "com.revnix/revnix_flutter/diagnostics",
            binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)

        // REV-272: implicit-placement triggers.
        let implicit = FlutterEventChannel(
            name: "com.revnix/revnix_flutter/implicit",
            binaryMessenger: registrar.messenger())
        instance.implicitStreamHandler.onSink = { [weak instance] sink in
            instance?.implicitSink = sink
        }
        implicit.setStreamHandler(instance.implicitStreamHandler)
    }

    /// A separate `FlutterStreamHandler` because the plugin itself already is
    /// one (for diagnostics) and a type can only serve one channel.
    final class ImplicitStreamHandler: NSObject, FlutterStreamHandler {
        var onSink: ((FlutterEventSink?) -> Void)?

        func onListen(
            withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
        ) -> FlutterError? {
            onSink?(events)
            return nil
        }

        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            onSink?(nil)
            return nil
        }
    }

    // MARK: - Diagnostics stream

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        diagnosticsSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        diagnosticsSink = nil
        return nil
    }

    // MARK: - Method channel

    public func handle(
        _ call: FlutterMethodCall, result: @escaping FlutterResult
    ) {
        let args = call.arguments as? [String: Any] ?? [:]

        if call.method == "configure" {
            configure(args, result: result)
            return
        }

        guard let client else {
            result(
                FlutterError(
                    code: "invalid",
                    message: "RevnixClient.configure() must be called first",
                    details: ["isRetryable": false]))
            return
        }

        Task {
            do {
                switch call.method {
                case "customerId":
                    result(await client.customerId())
                case "logout":
                    result(await client.logout())
                case "entitlements":
                    result(Self.map(try await client.entitlements()))
                case "cachedEntitlements":
                    result((await client.cachedEntitlements()).map(Self.map))
                case "isEntitled":
                    let id = args["entitlementId"] as? String ?? ""
                    result(await client.isEntitled(id))
                case "waitForEntitlements":
                    let seq = args["seq"] as? Int ?? 0
                    result(Self.map(try await client.waitForEntitlements(seq: seq)))
                case "registerPurchase":
                    let input = try Self.purchaseInput(args)
                    result(Self.map(try await client.registerPurchase(input)))
                case "retryPendingPurchases":
                    result(await client.retryPendingPurchases())
                case "pendingPurchaseCount":
                    result(await client.pendingPurchaseCount())
                case "resolvePlacement":
                    let key = args["placementKey"] as? String ?? ""
                    result(Self.map(try await client.resolvePlacement(key)))
                case "registerInstall":
                    await client.registerInstall(
                        platform: args["platform"] as? String ?? "ios",
                        appVersion: args["appVersion"] as? String)
                    result(nil)
                case "logPaywallShown":
                    // REV-252: returns the view id so Dart can pair the close
                    // with the display it ended. Older Dart ignores it.
                    let viewId = await client.logPaywallDisplay(
                        placementKey: args["placementKey"] as? String,
                        paywallId: args["paywallId"] as? String)
                    result(viewId)
                case "logPaywallClosed":
                    await client.logPaywallClosed(
                        viewId: args["viewId"] as? String ?? "",
                        placementKey: args["placementKey"] as? String,
                        paywallId: args["paywallId"] as? String)
                    result(nil)
                case "logPaywallEvent":
                    // REV-263: the wire name Dart sent maps 1:1 onto the
                    // enum's rawValue; an unknown one is a Dart/native
                    // version skew, and reporting nothing beats reporting the
                    // wrong event.
                    guard let raw = args["event"] as? String,
                        let event = RevnixPaywallEvent(rawValue: raw)
                    else {
                        result(nil)
                        return
                    }
                    await client.logPaywallEvent(
                        event,
                        viewId: args["viewId"] as? String ?? "",
                        placementKey: args["placementKey"] as? String,
                        paywallId: args["paywallId"] as? String,
                        productId: args["productId"] as? String,
                        code: args["code"] as? String,
                        message: args["message"] as? String,
                        eventId: args["eventId"] as? String)
                    result(nil)
                case "handleDeepLink":
                    // REV-272: the one implicit moment no SDK can see for
                    // itself — the URL reaches the host's own entry point.
                    // Answered immediately rather than awaited: this runs in the
                    // host's link handler right before it routes, and the
                    // trigger is two network round trips. Every Revnix telemetry
                    // call is a beacon; this is one too.
                    if let raw = args["url"] as? String, let url = URL(string: raw) {
                        Task { await client.handleDeepLink(url) }
                    }
                    result(nil)
                case "setAttributes":
                    let raw = args["attributes"] as? [String: Any] ?? [:]
                    try await client.setAttributes(Self.jsonValues(raw))
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            } catch let error as RevnixError {
                result(Self.flutterError(error))
            } catch {
                result(
                    FlutterError(
                        code: "network",
                        message: String(describing: error),
                        details: ["isRetryable": true]))
            }
        }
    }

    private func configure(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let apiKey = args["apiKey"] as? String,
            let baseURLString = args["baseUrl"] as? String,
            let baseURL = URL(string: baseURLString)
        else {
            result(
                FlutterError(
                    code: "invalid", message: "apiKey and baseUrl are required",
                    details: ["isRetryable": false]))
            return
        }

        let millis = { (key: String, fallback: TimeInterval) -> TimeInterval in
            guard let ms = args[key] as? Int else { return fallback }
            return TimeInterval(ms) / 1000
        }

        let sink = diagnosticsSink
        // REV-272: captured weakly-by-closure through a local, the same shape
        // the diagnostics sink uses — the sink is replaced when Dart
        // re-subscribes, so read it off the plugin at fire time rather than
        // snapshotting it here.
        let implicitTrigger: @Sendable (RevnixImplicitTrigger) -> Void = {
            [weak self] trigger in
            let payload: [String: Any?] = [
                "placement": trigger.placement.rawValue,
                "resolution": Self.map(trigger.resolution),
            ]
            DispatchQueue.main.async { self?.implicitSink?(payload) }
        }
        let client = RevnixClient(
            RevnixConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                timeout: millis("timeoutMs", 10),
                offlineMaxCacheAge: millis("offlineMaxCacheAgeMs", 14 * 24 * 3600),
                entitlementsTTL: millis("entitlementsTtlMs", 30),
                onDiagnostic: { event in
                    DispatchQueue.main.async {
                        sink?(["op": event.op, "message": event.message])
                    }
                },
                // REV-268: revnix-swift detects the device facts; Dart may
                // override the ones the app knows better.
                device: Self.deviceFacts(overrides: args["device"] as? [String: Any]),
                // REV-272: Dart opts in explicitly — the plugin always has a
                // handler to give, so "is there a listener" cannot be the
                // signal the way it is in revnix-react.
                onImplicitPaywall: implicitTrigger,
                implicitPlacements: args["implicitPlacements"] as? Bool ?? false,
                sessionTimeout: millis("sessionTimeoutMs", revnixDefaultSessionTimeout)
            ))
        // REV-272: retire the previous client BEFORE replacing it. Its
        // didBecomeActive observer lives on NotificationCenter and outlives the
        // reference, so a re-configure without this leaves two clients watching
        // the foreground — every return would then mint two session_start
        // triggers and emit two implicit-paywall events.
        if let previous = self.client {
            Task { await previous.stop() }
        }
        self.client = client

        // Transactions that complete outside a Dart-initiated purchase —
        // renewals, Ask to Buy approvals, another device — still have to reach
        // Revnix, so the observer belongs here rather than in Dart.
        observer = RevnixStoreKit.startObserving(client: client)
        Task { await client.retryPendingPurchases() }
        result(nil)
    }

    // MARK: - Marshalling

    /// Detected facts with the Dart-supplied overrides applied (REV-268).
    private static func deviceFacts(overrides: [String: Any]?) -> DeviceFacts {
        var facts = DeviceFacts.detect()
        guard let overrides else { return facts }
        if let v = overrides["platform"] as? String { facts.platform = v }
        if let v = overrides["osVersion"] as? String { facts.osVersion = v }
        if let v = overrides["appVersion"] as? String { facts.appVersion = v }
        if let v = overrides["locale"] as? String { facts.locale = v }
        if let v = overrides["currency"] as? String { facts.currency = v }
        if let v = overrides["storefront"] as? String { facts.storefront = v }
        if let v = overrides["model"] as? String { facts.model = v }
        if let v = overrides["sandbox"] as? Bool { facts.sandbox = v }
        return facts
    }

    private static func purchaseInput(_ args: [String: Any]) throws
        -> RegisterPurchaseInput
    {
        RegisterPurchaseInput(
            source: RevnixStore(rawValue: args["source"] as? String ?? "apple")
                ?? .apple,
            token: args["token"] as? String ?? "",
            productId: args["productId"] as? String ?? "",
            transactionId: args["transactionId"] as? String ?? "",
            occurredAt: args["occurredAt"] as? Int,
            expiresAt: args["expiresAt"] as? Int,
            signedTransactionInfo: args["signedTransactionInfo"] as? String)
    }

    private static func map(_ snapshot: CustomerEntitlements) -> [String: Any?] {
        [
            "customerId": snapshot.customerId,
            "cursor": snapshot.cursor,
            "stale": snapshot.stale,
            "fetchedAt": snapshot.fetchedAt,
            "entitlements": snapshot.entitlements.map { ent in
                [
                    "entitlementId": ent.entitlementId,
                    "isActive": ent.isActive,
                    "expiresAt": ent.expiresAt,
                    "sources": ent.sources.map { src in
                        [
                            "kind": src.kind, "key": src.key,
                            "isActive": src.isActive, "expiresAt": src.expiresAt,
                        ] as [String: Any?]
                    },
                ] as [String: Any?]
            },
        ]
    }

    private static func map(_ result: RegisterPurchaseResult) -> [String: Any?] {
        [
            "eventId": result.eventId,
            "seq": result.seq,
            "duplicate": result.duplicate,
            "customerId": result.customerId,
            "transferred": result.transferred,
            "ownedByOtherCustomer": result.ownedByOtherCustomer,
            "refused": result.refused,
            "restored": result.restored,
            "provisional": result.provisional,
        ]
    }

    private static func map(_ resolution: PlacementResolution) -> [String: Any?] {
        [
            "status": resolution.status,
            "placementKey": resolution.placementKey,
            "revision": resolution.revision,
            "offering": [
                "offeringId": resolution.offering.offeringId,
                "displayName": resolution.offering.displayName,
                "packages": resolution.offering.packages.map { pkg in
                    ["packageId": pkg.packageId, "productId": pkg.productId]
                },
            ] as [String: Any?],
            // Passed through loose — Dart owns the typed PaywallConfig parse,
            // so a new dashboard field never requires a native release. The
            // raw copy, not the typed `paywall`: that one is decoded through
            // the native block model and drops what it does not know.
            "paywall": resolution.paywallJSON.map(Self.bridgeValue),
            // REV-219. The paywall key was once dropped right here, and a lost
            // experiment would silently corrupt A/B attribution — so this is
            // the raw wire value too, same as `paywall`; nil stays nil.
            "experiment": resolution.experimentJSON.map(Self.bridgeValue),
        ]
    }

    /// Loose JSON → StandardMessageCodec-safe values (maps/lists/primitives).
    /// Attribute values arrive from Dart as NSString/NSNumber/NSNull. Anything
    /// else is a caller bug and is dropped rather than guessed at — the server
    /// would reject it with a 400 anyway.
    private static func jsonValues(_ raw: [String: Any]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in raw {
            if value is NSNull {
                out[key] = .null
            } else if let text = value as? String {
                out[key] = .string(text)
            } else if let number = value as? NSNumber {
                out[key] = .number(number.doubleValue)
            }
        }
        return out
    }

    private static func bridgeValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map(bridgeValue)
        case .object(let o): return o.mapValues(bridgeValue)
        }
    }

    /// The bridge's real contract: every case maps to a stable code plus
    /// `isRetryable`, so Dart can rebuild the typed error. Losing this would
    /// make a kill switch indistinguishable from an outage.
    private static func flutterError(_ error: RevnixError) -> FlutterError {
        var code = "network"
        var details: [String: Any?] = ["isRetryable": error.isRetryable]

        switch error {
        case .network: code = "network"
        case .timeout: code = "timeout"
        case .rateLimited(let retryAfterMs):
            code = "rate_limited"
            details["status"] = 429
            details["retryAfterMs"] = retryAfterMs
        case .server(let status):
            code = "server"
            details["status"] = status
        case .badResponse: code = "bad_response"
        case .auth(let status):
            code = "auth"
            details["status"] = status
        case .notFound:
            code = "not_found"
            details["status"] = 404
        case .purchaseBlocked:
            code = "purchase_blocked"
            details["status"] = 409
        case .invalid(let status, _):
            code = "invalid"
            details["status"] = status
        }

        return FlutterError(
            code: code, message: String(describing: error), details: details)
    }
}
