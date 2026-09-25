import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('logAdRevenue', () {
    test('forwards the channel method and argument map, omitting null optionals',
        () async {
      const channel = MethodChannel('test.revnix/log-ad-revenue');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'logAdRevenue') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.logAdRevenue(revenue: 0.0032, currency: 'USD');

      expect(call, isNotNull);
      expect(call!.method, 'logAdRevenue');
      expect(call!.arguments, <Object?, Object?>{
        'revenue': 0.0032,
        'currency': 'USD',
      });
    });

    test('carries the optional fields when provided', () async {
      const channel = MethodChannel('test.revnix/log-ad-revenue-full');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (received) async {
        if (received.method == 'logAdRevenue') call = received;
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      await client.logAdRevenue(
        revenue: 0.0032,
        currency: 'USD',
        network: 'admob',
        mediation: 'applovin_max',
        adUnit: 'unit_1',
        placement: 'home_banner',
        format: 'banner',
        eventId: 'evt_1',
      );

      expect(call!.arguments, <Object?, Object?>{
        'revenue': 0.0032,
        'currency': 'USD',
        'network': 'admob',
        'mediation': 'applovin_max',
        'adUnit': 'unit_1',
        'placement': 'home_banner',
        'format': 'banner',
        'eventId': 'evt_1',
      });
    });
  });
}
