import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

// REV-272: the implicit placement contract, Flutter side.
//
// The native SDKs do the watching; this layer's job is that nothing is lost in
// translation. The server 400s a key it does not know and the failure is SILENT
// from the app's side, so the key spellings are asserted hard, and the trigger
// payload is decoded from the exact map shape the plugins send.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the vocabulary matches the server contract', () {
    test('six keys, in contract order', () {
      expect(
        RevnixImplicitPlacement.values.map((p) => p.key).toList(),
        <String>[
          'app_install',
          'app_launch',
          'session_start',
          'deeplink_open',
          'paywall_decline',
          'transaction_abandon',
        ],
      );
    });

    test('every key is one the catalog would accept', () {
      // A placement key must match ^[a-z0-9][a-z0-9._-]{0,63}$ server-side,
      // which is why the deep link moment is `deeplink_open` and not
      // Superwall's `deepLink_open` — the capital L could never be stored.
      final pattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
      for (final placement in RevnixImplicitPlacement.values) {
        expect(pattern.hasMatch(placement.key), isTrue,
            reason: '${placement.key} would be refused by the catalog');
      }
      expect(pattern.hasMatch('deepLink_open'), isFalse);
    });

    test('keys round-trip, and an ordinary placement is not one of the six', () {
      for (final placement in RevnixImplicitPlacement.values) {
        expect(RevnixImplicitPlacement.fromKey(placement.key), placement);
      }
      expect(RevnixImplicitPlacement.fromKey('premium_button'), isNull);
      expect(RevnixImplicitPlacement.fromKey(null), isNull);
    });

  });

  group('decoding a trigger from the platform channel', () {
    Map<Object?, Object?> triggerMap({
      String? placement = 'paywall_decline',
    }) =>
        <Object?, Object?>{
          'placement': placement,
          'resolution': <Object?, Object?>{
            'status': 'ok',
            'placementKey': placement,
            'revision': 7,
            'offering': <Object?, Object?>{
              'offeringId': 'default',
              'displayName': 'Default',
              'packages': <Object?>[],
            },
            'paywall': <Object?, Object?>{
              'paywallId': 'pw_winback',
              'name': 'Win-back',
              'config': <Object?, Object?>{},
            },
          },
        };

    test('carries the moment and the resolution', () {
      final trigger = RevnixImplicitTrigger.fromMap(triggerMap());
      expect(trigger.placement, RevnixImplicitPlacement.paywallDecline);
      expect(trigger.resolution.paywall?.paywallId, 'pw_winback');
      expect(trigger.resolution.revision, 7);
    });

    test('a moment this Dart layer does not know decodes to null, not a crash', () {
      // Version skew: a native SDK newer than the Dart package. Dropping the
      // enum is survivable; throwing on the event stream is not.
      final trigger =
          RevnixImplicitTrigger.fromMap(triggerMap(placement: 'survey_response'));
      expect(trigger.placement, isNull);
      expect(trigger.resolution.paywall?.paywallId, 'pw_winback');
    });
  });

  group('the method channel', () {
    test('configure passes the implicit options through', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('test.revnix/implicit');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        implicitPlacements: true,
        sessionTimeout: const Duration(minutes: 5),
        channel: channel,
      );

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['implicitPlacements'], isTrue);
      expect(args['sessionTimeoutMs'], 5 * 60 * 1000);
    });

    test('implicit placements are off unless the app asks', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('test.revnix/implicit-off');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      final args = calls.single.arguments as Map<Object?, Object?>;
      // Without this the native side would ask /v1/config on every launch of
      // every Flutter app, configured or not.
      expect(args['implicitPlacements'], isFalse);
    });

    test('handleDeepLink forwards the URL to the native side', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('test.revnix/implicit-link');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        implicitPlacements: true,
        channel: channel,
      );
      await client.handleDeepLink('https://example.com/promo?ref=ad');

      final call = calls.last;
      expect(call.method, 'handleDeepLink');
      expect((call.arguments as Map<Object?, Object?>)['url'],
          'https://example.com/promo?ref=ad');
    });
  });
}
