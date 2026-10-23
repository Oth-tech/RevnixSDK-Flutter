import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('identify', () {
    test('forwards the user id and returns the native customer id', () async {
      const channel = MethodChannel('test.revnix/identify');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'identify') {
          call = received;
          return 'user_42';
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      final id = await client.identify('user_42');

      expect(call, isNotNull);
      expect(call!.arguments, <Object?, Object?>{'userId': 'user_42'});
      expect(id, 'user_42');
    });
  });
}
