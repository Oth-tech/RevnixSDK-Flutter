import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('track', () {
    test('forwards the channel method and argument map, omitting null optionals',
        () async {
      const channel = MethodChannel('test.revnix/track');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'track') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.track('level_up');

      expect(call, isNotNull);
      expect(call!.method, 'track');
      expect(call!.arguments, <Object?, Object?>{
        'event': 'level_up',
      });
    });

    test('carries the optional fields when provided', () async {
      const channel = MethodChannel('test.revnix/track-full');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'track') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.track(
        'level_up',
        properties: {'level': 5, 'premium': true},
        eventId: 'evt_1',
      );

      expect(call!.arguments, <Object?, Object?>{
        'event': 'level_up',
        'properties': {'level': 5, 'premium': true},
        'eventId': 'evt_1',
      });
    });
  });
}
