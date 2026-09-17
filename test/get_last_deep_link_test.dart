import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getLastDeepLink', () {
    test('returns the model when native returns a map', () async {
      const channel = MethodChannel('test.revnix/get-last-deep-link');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getLastDeepLink') {
          return <Object?, Object?>{
            'url': 'com.voigu.app://promo?utm_source=email',
            'receivedAt': 1700000000000,
          };
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final last = await client.getLastDeepLink();

      expect(last, isNotNull);
      expect(last!.url, 'com.voigu.app://promo?utm_source=email');
      expect(
        last.receivedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('returns null when native returns null', () async {
      const channel = MethodChannel('test.revnix/get-last-deep-link-null');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final last = await client.getLastDeepLink();

      expect(last, isNull);
    });

    test('returns null when the channel throws', () async {
      const channel = MethodChannel('test.revnix/get-last-deep-link-error');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getLastDeepLink') {
          throw PlatformException(code: 'network', message: 'offline');
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final last = await client.getLastDeepLink();

      expect(last, isNull);
    });
  });
}
