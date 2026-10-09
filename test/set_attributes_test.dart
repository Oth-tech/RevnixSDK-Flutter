import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setAttributes', () {
    Future<(RevnixClient, List<MethodCall>)> configure() async {
      const channel = MethodChannel('test.revnix/set-attributes');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'setAttributes') calls.add(received);
        return null;
      });
      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      return (client, calls);
    }

    test('forwards String, num and null values', () async {
      final (client, calls) = await configure();
      await client.setAttributes({'country': 'US', 'orders': 3, 'old': null});
      expect(calls.single.arguments, <Object?, Object?>{
        'attributes': {'country': 'US', 'orders': 3, 'old': null},
      });
    });

    test('rejects a bool before touching the channel', () async {
      final (client, calls) = await configure();
      await expectLater(
        () => client.setAttributes({'premium': true}),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });
  });
}
