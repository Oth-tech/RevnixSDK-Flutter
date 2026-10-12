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
  });
}
