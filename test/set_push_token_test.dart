import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setPushToken', () {
    test('forwards the channel method and argument map', () async {
      const channel = MethodChannel('test.revnix/set-push-token');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'setPushToken') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.setPushToken('abc123');

      expect(call, isNotNull);
      expect(call!.method, 'setPushToken');
      expect(call!.arguments, <Object?, Object?>{
        'token': 'abc123',
      });
    });
  });
}
