import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setAttribution', () {
    test('forwards the channel method and argument map, omitting null optionals',
        () async {
      const channel = MethodChannel('test.revnix/set-attribution');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'setAttribution') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.setAttribution(provider: 'adjust', network: 'facebook');

      expect(call, isNotNull);
      expect(call!.method, 'setAttribution');
      expect(call!.arguments, <Object?, Object?>{
        'provider': 'adjust',
        'network': 'facebook',
      });
    });

    test('carries the optional fields when provided', () async {
      const channel = MethodChannel('test.revnix/set-attribution-full');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'setAttribution') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.setAttribution(
        provider: 'appsflyer',
        network: 'facebook',
        campaign: 'summer_sale',
        adGroup: 'lookalike_1',
        creative: 'video_a',
      );

      expect(call!.arguments, <Object?, Object?>{
        'provider': 'appsflyer',
        'network': 'facebook',
        'campaign': 'summer_sale',
        'adGroup': 'lookalike_1',
        'creative': 'video_a',
      });
    });
  });
}
