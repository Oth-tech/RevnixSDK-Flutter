package com.revnix.revnix_flutter

import android.app.Activity
import android.content.Context
import com.revnix.CustomerEntitlements
import com.revnix.PlacementResolution
import com.revnix.RegisterPurchaseInput
import com.revnix.RegisterPurchaseResult
import com.revnix.RevnixClient
import com.revnix.RevnixConfig
import com.revnix.RevnixError
import com.revnix.RevnixPaywallEvent
import com.revnix.RevnixStore
import com.revnix.android.AndroidStorage
import com.revnix.android.PlayBillingConnector
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Android side of the Flutter bridge — a thin adapter over `revnix-kotlin`.
 *
 * Holds no policy of its own. In particular the Play Billing acknowledgement
 * ordering (acknowledge only AFTER the claim is recorded or durably queued)
 * stays inside [PlayBillingConnector], where it is tested — pulling it up into
 * bridge code is how that rule gets broken.
 */
class RevnixFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var context: Context

    private var client: RevnixClient? = null
    private var billing: PlayBillingConnector? = null
    private var activity: Activity? = null
    private var diagnosticsSink: EventChannel.EventSink? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.revnix/revnix_flutter")
        channel.setMethodCallHandler(this)
        events = EventChannel(
            binding.binaryMessenger,
            "com.revnix/revnix_flutter/diagnostics",
        )
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        billing?.close()
        client?.close()
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        diagnosticsSink = sink
    }

    override fun onCancel(arguments: Any?) {
        diagnosticsSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "configure") {
            configure(call, result)
            return
        }

        val active = client
        if (active == null) {
            result.error(
                "invalid",
                "RevnixClient.configure() must be called first",
                mapOf("isRetryable" to false),
            )
            return
        }

        scope.launch {
            try {
                when (call.method) {
                    "customerId" -> result.success(active.customerId())
                    "logout" -> result.success(active.logout())
                    "entitlements" -> result.success(map(active.entitlements()))
                    "cachedEntitlements" ->
                        result.success(active.cachedEntitlements()?.let(::map))
                    "isEntitled" ->
                        result.success(
                            active.isEntitled(call.argument<String>("entitlementId") ?: "")
                        )
                    "waitForEntitlements" -> {
                        val seq = (call.argument<Number>("seq") ?: 0).toLong()
                        result.success(map(active.waitForEntitlements(seq)))
                    }
                    "registerPurchase" ->
                        result.success(map(active.registerPurchase(purchaseInput(call))))
                    "retryPendingPurchases" ->
                        result.success(active.retryPendingPurchases())
                    "pendingPurchaseCount" ->
                        result.success(active.pendingPurchaseCount())
                    "resolvePlacement" ->
                        result.success(
                            map(
                                active.resolvePlacement(
                                    call.argument<String>("placementKey") ?: ""
                                )
                            )
                        )
                    "registerInstall" -> {
                        active.registerInstall(
                            platform = call.argument<String>("platform") ?: "android",
                            appVersion = call.argument<String>("appVersion"),
                        )
                        result.success(null)
                    }
                    "logPaywallShown" -> {
                        // REV-252: returns the view id so Dart can pair the
                        // close with the display it ended. Older Dart ignores it.
                        val viewId = active.logPaywallDisplay(
                            placementKey = call.argument<String>("placementKey"),
                            paywallId = call.argument<String>("paywallId"),
                        )
                        result.success(viewId)
                    }
                    "logPaywallClosed" -> {
                        active.logPaywallClosed(
                            viewId = call.argument<String>("viewId").orEmpty(),
                            placementKey = call.argument<String>("placementKey"),
                            paywallId = call.argument<String>("paywallId"),
                        )
                        result.success(null)
                    }
                    "logPaywallEvent" -> {
                        // REV-263: the wire name Dart sent maps 1:1 onto the
                        // enum's wireName; an unknown one is a Dart/native
                        // version skew, and reporting nothing beats reporting
                        // the wrong event.
                        val raw = call.argument<String>("event")
                        val event = RevnixPaywallEvent.entries
                            .firstOrNull { it.wireName == raw }
                        if (event == null) {
                            result.success(null)
                        } else {
                            active.logPaywallEvent(
                                event = event,
                                viewId = call.argument<String>("viewId").orEmpty(),
                                placementKey = call.argument<String>("placementKey"),
                                paywallId = call.argument<String>("paywallId"),
                                productId = call.argument<String>("productId"),
                                code = call.argument<String>("code"),
                                message = call.argument<String>("message"),
                                eventId = call.argument<String>("eventId"),
                            )
                            result.success(null)
                        }
                    }
                    "setAttributes" -> {
                        active.setAttributes(
                            call.argument<Map<String, Any?>>("attributes").orEmpty()
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (err: RevnixError) {
                val (code, details) = describe(err)
                result.error(code, err.message, details)
            } catch (err: Throwable) {
                result.error(
                    "network",
                    err.message ?: "unexpected failure",
                    mapOf("isRetryable" to true),
                )
            }
        }
    }

    private fun configure(call: MethodCall, result: MethodChannel.Result) {
        val apiKey = call.argument<String>("apiKey")
        val baseUrl = call.argument<String>("baseUrl")
        if (apiKey == null || baseUrl == null) {
            result.error(
                "invalid",
                "apiKey and baseUrl are required",
                mapOf("isRetryable" to false),
            )
            return
        }

        fun duration(key: String, fallbackMs: Long) =
            ((call.argument<Number>(key)?.toLong()) ?: fallbackMs).milliseconds

        val created = RevnixClient(
            RevnixConfig(
                apiKey = apiKey,
                baseUrl = baseUrl,
                storage = AndroidStorage(context),
                timeout = duration("timeoutMs", 10_000),
                offlineMaxCacheAge = duration("offlineMaxCacheAgeMs", 14L * 24 * 3600 * 1000),
                entitlementsTtl = duration("entitlementsTtlMs", 30_000),
                onDiagnostic = { event ->
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            diagnosticsSink?.success(
                                mapOf("op" to event.op, "message" to event.message)
                            )
                        }
                    }
                },
            )
        )
        client = created
        // Owns connection, purchase replay, acknowledgement, and the queue drain.
        billing = PlayBillingConnector.start(context, created)
        result.success(null)
    }

    // MARK: - Marshalling

    private fun purchaseInput(call: MethodCall) = RegisterPurchaseInput(
        source = RevnixStore.fromWire(call.argument<String>("source") ?: "google"),
        token = call.argument<String>("token") ?: "",
        productId = call.argument<String>("productId") ?: "",
        transactionId = call.argument<String>("transactionId") ?: "",
        occurredAt = call.argument<Number>("occurredAt")?.toLong(),
        expiresAt = call.argument<Number>("expiresAt")?.toLong(),
        signedTransactionInfo = call.argument<String>("signedTransactionInfo"),
    )

    private fun map(snapshot: CustomerEntitlements): Map<String, Any?> = mapOf(
        "customerId" to snapshot.customerId,
        "cursor" to snapshot.cursor,
        "stale" to snapshot.stale,
        "fetchedAt" to snapshot.fetchedAt,
        "entitlements" to snapshot.entitlements.map { ent ->
            mapOf(
                "entitlementId" to ent.entitlementId,
                "isActive" to ent.isActive,
                "expiresAt" to ent.expiresAt,
                "sources" to ent.sources.map { src ->
                    mapOf(
                        "kind" to src.kind,
                        "key" to src.key,
                        "isActive" to src.isActive,
                        "expiresAt" to src.expiresAt,
                    )
                },
            )
        },
    )

    private fun map(result: RegisterPurchaseResult): Map<String, Any?> = mapOf(
        "eventId" to result.eventId,
        "seq" to result.seq,
        "duplicate" to result.duplicate,
        "customerId" to result.customerId,
        "transferred" to result.transferred,
        "ownedByOtherCustomer" to result.ownedByOtherCustomer,
        "refused" to result.refused,
        "restored" to result.restored,
        "provisional" to result.provisional,
    )

    private fun map(resolution: PlacementResolution): Map<String, Any?> = mapOf(
        "status" to resolution.status,
        "placementKey" to resolution.placementKey,
        "revision" to resolution.revision,
        "offering" to mapOf(
            "offeringId" to resolution.offering.offeringId,
            "displayName" to resolution.offering.displayName,
            "packages" to resolution.offering.packages.map { pkg ->
                mapOf("packageId" to pkg.packageId, "productId" to pkg.productId)
            },
        ),
        // Passed through loose — Dart owns the typed PaywallConfig parse, so a
        // new dashboard field never requires a native release. The raw copy,
        // not the typed `paywall`, so nothing is lost on the way through.
        "paywall" to bridgeValue(resolution.paywallJson),
        // REV-219. The paywall key was once dropped right here, and a lost
        // experiment would silently corrupt A/B attribution — so this is the
        // raw wire value too, same as `paywall`; null stays null.
        "experiment" to bridgeValue(resolution.experimentJson),
    )

    /** Loose JSON → StandardMessageCodec-safe values (maps/lists/primitives). */
    private fun bridgeValue(element: JsonElement?): Any? = when (element) {
        null, is JsonNull -> null
        is JsonObject -> element.mapValues { bridgeValue(it.value) }
        is JsonArray -> element.map { bridgeValue(it) }
        is JsonPrimitive -> when {
            element.isString -> element.content
            else -> element.booleanOrNull ?: element.longOrNull
                ?: element.doubleOrNull ?: element.content
        }
    }

    /**
     * The bridge's real contract: a stable code plus `isRetryable`, so Dart can
     * rebuild the typed error. Lose this and a kill switch becomes
     * indistinguishable from an outage.
     */
    private fun describe(err: RevnixError): Pair<String, Map<String, Any?>> {
        val details = mutableMapOf<String, Any?>("isRetryable" to err.isRetryable)
        val code = when (err) {
            is RevnixError.Network -> "network"
            is RevnixError.Timeout -> "timeout"
            is RevnixError.RateLimited -> {
                details["status"] = 429
                details["retryAfterMs"] = err.retryAfterMs
                "rate_limited"
            }
            is RevnixError.Server -> {
                details["status"] = err.status
                "server"
            }
            is RevnixError.BadResponse -> "bad_response"
            is RevnixError.Auth -> {
                details["status"] = err.status
                "auth"
            }
            is RevnixError.NotFound -> {
                details["status"] = 404
                "not_found"
            }
            is RevnixError.PurchaseBlocked -> {
                details["status"] = 409
                "purchase_blocked"
            }
            is RevnixError.Invalid -> {
                details["status"] = err.status
                "invalid"
            }
        }
        return code to details
    }
}
