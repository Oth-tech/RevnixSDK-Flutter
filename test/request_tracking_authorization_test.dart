import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('requestTrackingAuthorization', () {
    test('returns the native status and passes attWaitTimeout in ms', () async {
      const channel = MethodChannel('test.revnix/att');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        calls.add(received);
        return received.method == 'requestTrackingAuthorization' ? 3 : null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        attWaitTimeout: const Duration(seconds: 20),
        channel: channel,
      );

      expect(await client.requestTrackingAuthorization(), 3);
      expect((calls.first.arguments as Map)['attWaitTimeoutMs'], 20000);
    });

    test('falls back to -1 when the platform answers null', () async {
      const channel = MethodChannel('test.revnix/att-null');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async => null);

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      expect(await client.requestTrackingAuthorization(), -1);
    });
  });
}
