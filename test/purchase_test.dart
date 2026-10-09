import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.revnix/purchase');

  Future<RevnixClient> clientAnswering(
    Future<Object?> Function(MethodCall call) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'configure') return null;
      return handler(call);
    });
    return RevnixClient.configure(
      apiKey: 'rvx_pk_test',
      baseUrl: 'https://x.convex.site',
      channel: channel,
    );
  }

  test('purchase forwards productId and decodes the result', () async {
    MethodCall? received;
    final client = await clientAnswering((call) async {
      received = call;
      return {
        'eventId': 'evt_1',
        'seq': 42,
        'duplicate': false,
        'customerId': 'cus_1',
      };
    });

    final result = await client.purchase('pro.monthly');

    expect(received!.method, 'purchase');
    expect(received!.arguments, {'productId': 'pro.monthly'});
    expect(result!.seq, 42);
    expect(result.customerId, 'cus_1');
  });

  test('purchase returns null when native returns null', () async {
    final client = await clientAnswering((_) async => null);

    expect(await client.purchase('pro.monthly'), isNull);
  });

  test('product_not_found surfaces as a non-retryable RevnixException',
      () async {
    final client = await clientAnswering((_) async => throw PlatformException(
          code: 'product_not_found',
          message: 'No store product "nope"',
          details: {'isRetryable': false},
        ));

    expect(
      () => client.purchase('nope'),
      throwsA(isA<RevnixException>()
          .having((e) => e.code, 'code', 'product_not_found')
          .having((e) => e.isRetryable, 'isRetryable', false)),
    );
  });

  test('restore returns the registered count', () async {
    MethodCall? received;
    final client = await clientAnswering((call) async {
      received = call;
      return 3;
    });

    expect(await client.restore(), 3);
    expect(received!.method, 'restore');
  });
}
