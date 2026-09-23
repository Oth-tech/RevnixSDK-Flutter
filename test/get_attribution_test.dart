import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getAttribution', () {
    test('returns the model when native returns a map', () async {
      const channel = MethodChannel('test.revnix/get-attribution');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAttribution') {
          return <Object?, Object?>{
            'installMatch': 'exact',
            'attributedAt': 1700000000000,
            'reattributedAt': 1700000500000,
            'linkToken': 'lt_abc',
            'referrerSource': 'play',
            'matchSignals': <Object?>['ip', 'timing'],
            'source': 'google',
            'medium': 'cpc',
            'campaign': 'summer50',
            'term': null,
            'content': null,
          };
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final attribution = await client.getAttribution();

      expect(attribution, isNotNull);
      expect(attribution!.installMatch, 'exact');
      expect(attribution.attributedAt, 1700000000000);
      expect(attribution.reattributedAt, 1700000500000);
      expect(attribution.linkToken, 'lt_abc');
      expect(attribution.referrerSource, 'play');
      expect(attribution.matchSignals, ['ip', 'timing']);
      expect(attribution.source, 'google');
      expect(attribution.medium, 'cpc');
      expect(attribution.campaign, 'summer50');
      expect(attribution.term, isNull);
      expect(attribution.content, isNull);
    });

    test('returns null when native returns null', () async {
      const channel = MethodChannel('test.revnix/get-attribution-null');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final attribution = await client.getAttribution();

      expect(attribution, isNull);
    });

    test('returns null when the channel throws', () async {
      const channel = MethodChannel('test.revnix/get-attribution-error');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAttribution') {
          throw PlatformException(code: 'network', message: 'offline');
        }
        return null;
      });

      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );
      final attribution = await client.getAttribution();

      expect(attribution, isNull);
    });
  });

  group('onAttribution', () {
    const eventChannel = EventChannel('com.revnix/revnix_flutter/attribution');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    test('delivers a verdict from the native message', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{
              'installMatch': 'probabilistic',
              'attributedAt': 1700000000000,
            });
          },
        ),
      );

      const channel = MethodChannel('test.revnix/on-attribution');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      final attribution = await client.onAttribution.first;
      expect(attribution.installMatch, 'probabilistic');
      expect(attribution.attributedAt, 1700000000000);
    });

    test('a missing or empty installMatch is ignored, not delivered', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{'installMatch': ''});
            events.success(<Object?, Object?>{'attributedAt': 1700000000000});
            events.success(<Object?, Object?>{
              'installMatch': 'exact',
              'attributedAt': 1700000000000,
            });
          },
        ),
      );

      const channel = MethodChannel('test.revnix/on-attribution-skip');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final client = await RevnixClient.configure(
        apiKey: 'rvx_pk_test',
        baseUrl: 'https://x.convex.site',
        channel: channel,
      );

      final attribution = await client.onAttribution.first;
      expect(attribution.installMatch, 'exact');
    });
  });
}
