import 'package:flutter/material.dart';
import 'package:revnix_flutter/revnix_flutter.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  String _customerId = '…';
  bool _isPro = false;
  bool _stale = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final revnix = await RevnixClient.configure(
        apiKey: 'rvx_pk_test_…',
        baseUrl: 'https://your-deployment.convex.site',
      );

      // Drain anything that failed to register while offline, then report the
      // install. Both are safe to call on every launch.
      await revnix.retryPendingPurchases();
      await revnix.registerInstall();

      final id = await revnix.customerId();

      // Instant, offline-safe first paint from the cache…
      final cached = await revnix.cachedEntitlements();
      if (cached != null && mounted) {
        setState(() {
          _isPro = cached.isEntitled('pro');
          _stale = true;
        });
      }

      // …then revalidate over the network.
      final fresh = await revnix.entitlements();
      if (!mounted) return;
      setState(() {
        _customerId = id;
        _isPro = fresh.isEntitled('pro');
        _stale = fresh.stale ?? false;
      });
    } on RevnixException catch (err) {
      // A deliberate rejection (revoked key, unknown placement) is worth
      // surfacing; transient ones are already handled by the cache.
      if (!mounted) return;
      setState(() => _error = '${err.code}: ${err.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Revnix example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Customer: $_customerId'),
              const SizedBox(height: 8),
              Text(_isPro ? 'Pro unlocked' : 'Locked'),
              if (_stale)
                const Text('(served from the offline cache)'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
