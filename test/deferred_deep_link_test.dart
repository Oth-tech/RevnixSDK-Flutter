import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannel = EventChannel('com.revnix/revnix_flutter/deferred_deep_link');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  group('onDeferredDeepLink', () {
    Future<RevnixClient> configuredClient() async {
      const channel = MethodChannel('test.revnix/deferred-deep-link-config');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      return RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
    }

    test('parses a matched link from the native message', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{
              'url': 'https://example.com/promo?ref=ad',
              'match': 'exact',
            });
          },
        ),
      );

      final client = await configuredClient();
      final event = await client.onDeferredDeepLink.first;
      expect(event.$1, 'https://example.com/promo?ref=ad');
      expect(event.$2, DeferredDeepLinkMatch.exact);
    });

    test('an unknown match is ignored, not delivered', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{
              'url': 'https://example.com/unknown',
              'match': 'quantum',
            });
            events.success(<Object?, Object?>{
              'url': 'https://example.com/promo',
              'match': 'probabilistic',
            });
          },
        ),
      );

      final client = await configuredClient();
      final event = await client.onDeferredDeepLink.first;
      expect(event.$1, 'https://example.com/promo');
      expect(event.$2, DeferredDeepLinkMatch.probabilistic);
    });

    test('a missing or empty url is ignored, not delivered', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{'url': '', 'match': 'exact'});
            events.success(<Object?, Object?>{'match': 'exact'});
            events.success(<Object?, Object?>{
              'url': 'https://example.com/promo',
              'match': 'exact',
            });
          },
        ),
      );

      final client = await configuredClient();
      final event = await client.onDeferredDeepLink.first;
      expect(event.$1, 'https://example.com/promo');
    });

    test('every listener sees the same one-shot event', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{
              'url': 'https://example.com/promo',
              'match': 'exact',
            });
          },
        ),
      );

      final client = await configuredClient();
      final first = client.onDeferredDeepLink.first;
      final second = client.onDeferredDeepLink.first;
      expect(await first, (
        'https://example.com/promo',
        DeferredDeepLinkMatch.exact,
      ));
      expect(await second, (
        'https://example.com/promo',
        DeferredDeepLinkMatch.exact,
      ));
    });
  });

  group('handleInstallReferrer', () {
    test('sends the referrer verbatim on the method channel', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('test.revnix/deferred-deep-link');
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
      await client.handleInstallReferrer('utm_source=google-play&utm_medium=cpc');

      final call = calls.last;
      expect(call.method, 'handleInstallReferrer');
      expect(
        (call.arguments as Map<Object?, Object?>)['referrer'],
        'utm_source=google-play&utm_medium=cpc',
      );
    });
  });
}
