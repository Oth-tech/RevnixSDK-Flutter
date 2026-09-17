import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveDeepLink', () {
    test('invokes resolveDeepLink with the url and returns the native result',
        () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('test.revnix/resolve-deep-link');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'resolveDeepLink') {
          return 'com.voigu.app://promo?utm_source=email';
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final resolved =
          await client.resolveDeepLink('https://click.mailchimp.com/track/abc');

      expect(resolved, 'com.voigu.app://promo?utm_source=email');
      final call = calls.last;
      expect(call.method, 'resolveDeepLink');
      expect(
        (call.arguments as Map<Object?, Object?>)['url'],
        'https://click.mailchimp.com/track/abc',
      );
    });

    test('a PlatformException from the native side returns the input url',
        () async {
      const channel = MethodChannel('test.revnix/resolve-deep-link-error');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'resolveDeepLink') {
          throw PlatformException(code: 'network', message: 'offline');
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final resolved =
          await client.resolveDeepLink('https://click.mailchimp.com/track/abc');

      expect(resolved, 'https://click.mailchimp.com/track/abc');
    });

    test('a blank input is returned without invoking the channel', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('test.revnix/resolve-deep-link-blank');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final resolved = await client.resolveDeepLink('');

      expect(resolved, '');
      expect(calls.any((call) => call.method == 'resolveDeepLink'), isFalse);
    });
  });
}
