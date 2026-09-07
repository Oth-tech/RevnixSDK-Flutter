import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

/// Bridge contract tests.
///
/// The resilience policy itself is proven in the native SDKs (27 cases in
/// revnix-swift, 26 in revnix-core, 25 × 2 targets in revnix-kmp). What this
/// suite proves is that the bridge does not LOSE it: typed errors stay typed
/// across the channel, `stale` survives, gates still fail closed, and the wire
/// contract is marshalled correctly.
///
/// That is the failure mode a wrapped SDK actually has — a 401 arriving as a
/// generic PlatformException would silently defeat the kill switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.revnix/test');
  final log = <MethodCall>[];

  /// Route calls to canned results, or throw a native-shaped error.
  void mock(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return handler(call);
    });
  }

  Future<RevnixClient> client() => RevnixClient.configure(
        apiKey: 'rvx_pk_test_abc',
        baseUrl: 'https://example.convex.site',
        channel: channel,
      );

  const entitlementsPayload = <Object?, Object?>{
    'customerId': 'cust_1',
    'cursor': 7,
    'stale': false,
    'fetchedAt': 1700000000000,
    'entitlements': [
      {
        'entitlementId': 'pro',
        'isActive': true,
        'expiresAt': 4102444800000,
        'sources': [
          {
            'kind': 'subscription',
            'key': 's1',
            'isActive': true,
            'expiresAt': 4102444800000,
          }
        ],
      }
    ],
  };

  setUp(log.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('typed errors survive the bridge', () {
    // Each taxonomy code must rehydrate into its Dart type with isRetryable
    // intact — the retryable/deliberate split is the whole contract.
    final cases = <String, Matcher>{
      'network': isA<RevnixNetworkException>(),
      'timeout': isA<RevnixTimeoutException>(),
      'rate_limited': isA<RevnixRateLimitException>(),
      'server': isA<RevnixServerException>(),
      'bad_response': isA<RevnixBadResponseException>(),
      'auth': isA<RevnixAuthException>(),
      'not_found': isA<RevnixNotFoundException>(),
      'purchase_blocked': isA<RevnixPurchaseBlockedException>(),
      'invalid': isA<RevnixInvalidException>(),
    };

    for (final entry in cases.entries) {
      test('${entry.key} rehydrates', () async {
        mock((call) {
          if (call.method == 'configure') return null;
          throw PlatformException(code: entry.key, message: 'boom');
        });
        final revnix = await client();
        await expectLater(revnix.entitlements(), throwsA(entry.value));
      });
    }

    test('retryable and deliberate are not confused', () async {
      mock((call) {
        if (call.method == 'configure') return null;
        throw PlatformException(code: 'auth', message: 'revoked', details: {
          'status': 401,
        });
      });
      final revnix = await client();
      try {
        await revnix.entitlements();
        fail('expected a RevnixAuthException');
      } on RevnixException catch (err) {
        // A revoked key must NOT look retryable, or the cache would paper
        // over a kill switch.
        expect(err.isRetryable, isFalse);
        expect(err.status, 401);
      }
    });

    test('429 carries retryAfterMs across the channel', () async {
      mock((call) {
        if (call.method == 'configure') return null;
        throw PlatformException(
          code: 'rate_limited',
          message: 'slow down',
          details: {'retryAfterMs': 2000},
        );
      });
      final revnix = await client();
      try {
        await revnix.resolvePlacement('main');
        fail('expected a RevnixRateLimitException');
      } on RevnixException catch (err) {
        expect(err.retryAfterMs, 2000);
        expect(err.isRetryable, isTrue);
      }
    });

    test('an unknown code fails closed rather than looking retryable', () {
      final err = revnixExceptionFrom('something_new', 'huh', null);
      expect(err.isRetryable, isFalse);
    });
  });

  group('device facts (REV-268)', () {
    test('overrides ride the configure call and are omitted when absent', () async {
      mock((call) => null);
      log.clear();
      await RevnixClient.configure(
        apiKey: 'rvx_pk_test_abc',
        baseUrl: 'https://example.convex.site',
        channel: channel,
        device: {'storefront': 'US', 'sandbox': true},
      );
      final withDevice = log.single.arguments as Map<Object?, Object?>;
      expect(withDevice['device'], {'storefront': 'US', 'sandbox': true});

      log.clear();
      await client();
      final without = log.single.arguments as Map<Object?, Object?>;
      // The native side detects the facts itself; Dart only speaks up when
      // the app knows better, so the key must not be sent as null.
      expect(without.containsKey('device'), isFalse);
    });
  });

  group('entitlements', () {
    test('a live snapshot parses with stale false', () async {
      mock((call) => call.method == 'configure' ? null : entitlementsPayload);
      final revnix = await client();
      final snapshot = await revnix.entitlements();

      expect(snapshot.cursor, 7);
      expect(snapshot.stale, isFalse);
      expect(snapshot.customerId, 'cust_1');
      expect(snapshot.isEntitled('pro'), isTrue);
      expect(snapshot.isEntitled('gold'), isFalse);
      expect(snapshot.entitlements.single.sources.single.kind, 'subscription');
    });

    test('the stale flag survives the channel', () async {
      // If `stale` were dropped in translation, an app could not tell a live
      // read from a cached one — and offline UX depends on that difference.
      mock((call) => call.method == 'configure'
          ? null
          : {...entitlementsPayload, 'stale': true});
      final revnix = await client();
      expect((await revnix.entitlements()).stale, isTrue);
    });

    test('cachedEntitlements returns null when nothing is cached', () async {
      mock((call) => call.method == 'configure' ? null : null);
      final revnix = await client();
      expect(await revnix.cachedEntitlements(), isNull);
    });

    test('isEntitled never throws, even on a deliberate rejection', () async {
      mock((call) {
        if (call.method == 'configure') return null;
        throw PlatformException(code: 'auth', message: 'revoked');
      });
      final revnix = await client();
      // Gates fail closed rather than propagating.
      expect(await revnix.isEntitled('pro'), isFalse);
    });

    test('isEntitled survives a missing plugin', () async {
      mock((call) {
        if (call.method == 'configure') return null;
        throw MissingPluginException('not registered');
      });
      final revnix = await client();
      expect(await revnix.isEntitled('pro'), isFalse);
    });

    test('waitForEntitlements forwards the ledger seq', () async {
      mock((call) => call.method == 'configure'
          ? null
          : {...entitlementsPayload, 'cursor': 9});
      final revnix = await client();
      final settled = await revnix.waitForEntitlements(9);

      expect(settled.cursor, 9);
      expect(log.last.method, 'waitForEntitlements');
      expect((log.last.arguments as Map)['seq'], 9);
    });
  });

  group('purchases', () {
    test('an Apple purchase marshals the JWS proof', () async {
      mock((call) => call.method == 'configure'
          ? null
          : {
              'eventId': 'evt_1',
              'seq': 9,
              'duplicate': false,
              'customerId': 'cust_1',
              'transferred': false,
              'provisional': false,
            });
      final revnix = await client();
      final result = await revnix.registerPurchase(
        const RegisterPurchaseInput(
          source: RevnixStore.apple,
          token: 'orig.1',
          productId: 'pro.monthly',
          transactionId: 'txn.1',
          signedTransactionInfo: 'jws.payload.sig',
        ),
      );

      expect(result.seq, 9);
      expect(result.provisional, isFalse);
      final args = log.last.arguments as Map;
      expect(args['source'], 'apple');
      // Without the proof on the wire the server can only record a
      // provisional claim.
      expect(args['signedTransactionInfo'], 'jws.payload.sig');
    });

    test('the Google helper sets transactionId to the purchase token', () async {
      mock((call) => call.method == 'configure'
          ? null
          : {
              'eventId': 'evt_2',
              'seq': 4,
              'duplicate': false,
              'customerId': 'cust_1',
              'provisional': true,
            });
      final revnix = await client();
      final result = await revnix.registerPurchase(
        RegisterPurchaseInput.google(
          purchaseToken: 'tok_abc',
          productId: 'pro.monthly',
        ),
      );

      final args = log.last.arguments as Map;
      expect(args['source'], 'google');
      // Play has no separate transaction id — the token is both.
      expect(args['token'], 'tok_abc');
      expect(args['transactionId'], 'tok_abc');
      // Device claims carry no Play-side proof, so this is expected.
      expect(result.provisional, isTrue);
    });

    test('a blocked purchase surfaces as a deliberate error', () async {
      mock((call) {
        if (call.method == 'configure') return null;
        throw PlatformException(code: 'purchase_blocked', message: 'blocked');
      });
      final revnix = await client();
      await expectLater(
        revnix.registerPurchase(
          const RegisterPurchaseInput(
            source: RevnixStore.apple,
            token: 't',
            productId: 'p',
            transactionId: 'x',
          ),
        ),
        throwsA(isA<RevnixPurchaseBlockedException>()),
      );
    });

    test('the queue count comes back across the bridge', () async {
      mock((call) => call.method == 'configure' ? null : 3);
      final revnix = await client();
      expect(await revnix.pendingPurchaseCount(), 3);
    });
  });

  group('placements and telemetry', () {
    test('a resolution parses its offering and packages', () async {
      mock((call) => call.method == 'configure'
          ? null
          : {
              'status': 'ok',
              'placementKey': 'onboarding',
              'revision': 3,
              'offering': {
                'offeringId': 'off_1',
                'displayName': 'Default',
                'packages': [
                  {'packageId': 'pkg_1', 'productId': 'pro.monthly'},
                ],
              },
            });
      final revnix = await client();
      final resolution = await revnix.resolvePlacement('onboarding');

      expect(resolution.revision, 3);
      expect(resolution.offering.packages.single.productId, 'pro.monthly');
      // No paywall attached to this placement.
      expect(resolution.paywall, isNull);
      // The experiment key is ABSENT here (old native SDK / old server) —
      // that must parse the same as an explicit null.
      expect(resolution.experiment, isNull);
    });

    test('an experiment assignment survives the bridge', () async {
      // The natives pass experiment as an explicit {key, variantId} map —
      // exactly the shape mocked here. Losing it would silently corrupt A/B
      // attribution, the same class of bug that once dropped `paywall`.
      mock((call) => call.method == 'configure'
          ? null
          : {
              'status': 'ok',
              'placementKey': 'onboarding',
              'revision': 7,
              'offering': {
                'offeringId': 'off_1',
                'displayName': 'Variant B',
                'packages': [
                  {'packageId': 'pkg_1', 'productId': 'pro.yearly'},
                ],
              },
              'paywall': null,
              'experiment': {'key': 'onboarding-price', 'variantId': 'var_b'},
            });
      final revnix = await client();
      final resolution = await revnix.resolvePlacement('onboarding');

      expect(resolution.experiment, isNotNull);
      expect(resolution.experiment!.key, 'onboarding-price');
      expect(resolution.experiment!.variantId, 'var_b');
      // The served offering is already the variant's — attribution only.
      expect(resolution.offering.displayName, 'Variant B');
    });

    test('an explicit null experiment parses to null', () async {
      // The bridge always includes the key; null means "no running
      // experiment", and must not throw or fabricate an assignment.
      mock((call) => call.method == 'configure'
          ? null
          : {
              'status': 'ok',
              'placementKey': 'onboarding',
              'revision': 3,
              'offering': {
                'offeringId': 'off_1',
                'displayName': 'Default',
                'packages': <Object?>[],
              },
              'paywall': null,
              'experiment': null,
            });
      final revnix = await client();
      expect((await revnix.resolvePlacement('onboarding')).experiment, isNull);
    });

    test('a paywall parses the full template contract', () async {
      // Everything the dashboard's template feature can set: a post-legacy
      // layout, light mode, review + offer blocks, and footer URLs.
      mock((call) => call.method == 'configure'
          ? null
          : {
              'status': 'ok',
              'placementKey': 'onboarding',
              'revision': 5,
              'offering': {
                'offeringId': 'off_1',
                'displayName': 'Default',
                'packages': [
                  {'packageId': 'pkg_1', 'productId': 'pro.yearly'},
                ],
              },
              'paywall': {
                'paywallId': 'pw_1',
                'name': 'Winter offer',
                'config': {
                  'template': 'timeline',
                  'mode': 'light',
                  'headline': 'Go Pro',
                  'subheadline': 'Everything unlocked',
                  'features': [
                    {'icon': 'bolt', 'title': 'Fast', 'description': 'Quick'},
                    {'title': 'Icon-less'},
                  ],
                  'ctaLabel': 'Start free trial',
                  'highlightPackageId': 'pkg_1',
                  'badgeText': 'SAVE 17%',
                  'accent': '#6478ff',
                  'heroImageUrl': 'https://cdn.example/hero.png',
                  'review': {
                    'rating': 4.8,
                    'quote': 'Changed my life',
                    'author': 'Sam',
                    'count': 'Join 2M+ users',
                  },
                  'offer': {
                    'strikethroughPrice': r'$79.99',
                    'urgencyText': 'Ends tonight',
                  },
                  'footer': {
                    'showRestore': true,
                    'showTerms': true,
                    'showPrivacy': false,
                    'termsUrl': 'https://example.com/terms',
                  },
                },
              },
              'experiment': {'key': 'winter-offer-test', 'variantId': 'var_a'},
            });
      final revnix = await client();
      final resolution = await revnix.resolvePlacement('onboarding');
      // Paywall and experiment must BOTH survive — one field being dropped in
      // marshalling is the bug class this suite exists to catch.
      expect(resolution.experiment!.key, 'winter-offer-test');
      expect(resolution.experiment!.variantId, 'var_a');
      final paywall = resolution.paywall!;

      expect(paywall.paywallId, 'pw_1');
      expect(paywall.name, 'Winter offer');
      final config = paywall.config;
      expect(config.template, 'timeline');
      expect(config.mode, 'light');
      expect(config.headline, 'Go Pro');
      expect(config.subheadline, 'Everything unlocked');
      expect(config.features, hasLength(2));
      expect(config.features.first.icon, 'bolt');
      expect(config.features.first.description, 'Quick');
      expect(config.features.last.icon, isNull);
      expect(config.features.last.title, 'Icon-less');
      expect(config.ctaLabel, 'Start free trial');
      expect(config.highlightPackageId, 'pkg_1');
      expect(config.badgeText, 'SAVE 17%');
      expect(config.accent, '#6478ff');
      expect(config.heroImageUrl, 'https://cdn.example/hero.png');
      expect(config.review!.rating, 4.8);
      expect(config.review!.quote, 'Changed my life');
      expect(config.review!.author, 'Sam');
      expect(config.review!.count, 'Join 2M+ users');
      expect(config.offer!.strikethroughPrice, r'$79.99');
      expect(config.offer!.urgencyText, 'Ends tonight');
      expect(config.footer!.showRestore, isTrue);
      expect(config.footer!.showTerms, isTrue);
      expect(config.footer!.showPrivacy, isFalse);
      expect(config.footer!.termsUrl, 'https://example.com/terms');
      expect(config.footer!.privacyUrl, isNull);
    });

    test('a legacy paywall config parses without the new fields', () async {
      // Pre-templates configs have only the original shape — no mode, review,
      // offer, or footer. They must keep parsing unchanged.
      mock((call) => call.method == 'configure'
          ? null
          : {
              'status': 'ok',
              'placementKey': 'onboarding',
              'revision': 2,
              'offering': {
                'offeringId': 'off_1',
                'displayName': 'Default',
                'packages': <Object?>[],
              },
              'paywall': {
                'paywallId': 'pw_legacy',
                'name': 'Original',
                'config': {
                  'template': 'focus',
                  'headline': 'Unlock everything',
                  'features': [
                    {'title': 'All access'},
                  ],
                  'ctaLabel': 'Continue',
                },
              },
            });
      final revnix = await client();
      final config = (await revnix.resolvePlacement('onboarding')).paywall!.config;

      expect(config.template, 'focus');
      // Absent mode = legacy dark; the model surfaces null and lets the
      // renderer default.
      expect(config.mode, isNull);
      expect(config.headline, 'Unlock everything');
      expect(config.features.single.title, 'All access');
      expect(config.ctaLabel, 'Continue');
      expect(config.review, isNull);
      expect(config.offer, isNull);
      expect(config.footer, isNull);

      // A template value newer than this SDK must not throw — the layout
      // union will grow again.
      expect(
        PaywallConfig.fromMap(const {'template': 'holo-carousel'}).template,
        'holo-carousel',
      );
    });

    test('telemetry beacons forward their arguments', () async {
      mock((call) => call.method == 'configure' ? null : null);
      final revnix = await client();
      await revnix.registerInstall(platform: 'ios', appVersion: '1.2.3');
      expect((log.last.arguments as Map)['appVersion'], '1.2.3');

      await revnix.logPaywallShown(placementKey: 'onboarding');
      expect(log.last.method, 'logPaywallShown');
      expect((log.last.arguments as Map)['placementKey'], 'onboarding');
    });
  });

  test('configure forwards its options natively', () async {
    mock((call) => null);
    await RevnixClient.configure(
      apiKey: 'rvx_pk_test_abc',
      baseUrl: 'https://example.convex.site',
      entitlementsTtl: Duration.zero,
      channel: channel,
    );
    final args = log.first.arguments as Map;
    expect(args['apiKey'], 'rvx_pk_test_abc');
    // Duration.zero disables the soft TTL natively (always-fetch).
    expect(args['entitlementsTtlMs'], 0);
    expect(args['offlineMaxCacheAgeMs'], const Duration(days: 14).inMilliseconds);
  });
}
