import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('flushEvents and preload', () {
    test('forward the channel methods and argument map', () async {
      const channel = MethodChannel('test.revnix/flush-preload');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'flushEvents' || received.method == 'preload') {
          calls.add(received);
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.flushEvents();
      await client.preload(['onboarding', 'home']);

      expect(calls.map((c) => c.method), ['flushEvents', 'preload']);
      expect(calls[1].arguments, <Object?, Object?>{
        'placementKeys': ['onboarding', 'home'],
      });
    });

    test('configure carries deviceIntegrity, false by default', () async {
      const channel = MethodChannel('test.revnix/device-integrity');
      final configures = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'configure') configures.add(received.arguments);
        return null;
      });

      for (final on in [false, true]) {
        await RevnixClient.configure(
          apiKey: 'rvx_pk_test',
          baseUrl: 'https://x.convex.site',
          deviceIntegrity: on,
          channel: channel,
        );
      }
      await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      expect(
        configures.map((a) => (a as Map)['deviceIntegrity']),
        [false, true, false],
      );
    });

    test('configure carries collectAdvertisingId, false by default', () async {
      const channel = MethodChannel('test.revnix/advertising-id');
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final configures = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'configure') configures.add(received.arguments);
        return null;
      });

      await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        collectAdvertisingId: true,
        channel: channel,
      );
      await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      expect(
        configures.map((a) => (a as Map)['collectAdvertisingId']),
        [true, false],
      );
    });
  });
}
