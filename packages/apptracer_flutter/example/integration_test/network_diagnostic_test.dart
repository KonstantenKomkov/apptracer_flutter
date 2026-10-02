// Run on a physical phone with --no-uninstall so network permissions survive.
// No Tracer initialization, credentials, or event submission is involved.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device resolves and reaches the public Tracer host',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFFFFFFF),
        child: Center(
          child: Text('Network diagnostic\nAllow wireless data if iOS asks.',
              style: TextStyle(color: Color(0xFF000000), fontSize: 22)),
        ),
      ),
    ));

    const host = 'sdk-api.apptracer.ru';
    Object? lastError;
    var reachedServer = false;
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 120)) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final addresses = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 8));
        // ignore: avoid_print
        print(
            'NETWORK DNS: ${addresses.map((address) => address.address).join(", ")}');
        final request = await client.getUrl(Uri.https(host, '/'));
        final response =
            await request.close().timeout(const Duration(seconds: 8));
        // A 404 at the API root proves DNS, TCP and TLS completed.
        // ignore: avoid_print
        print('NETWORK HTTPS: ${response.statusCode}');
        await response.drain<void>();
        reachedServer = true;
        break;
      } catch (error) {
        lastError = error;
        // ignore: avoid_print
        print('NETWORK retry at ${elapsed.elapsed.inSeconds}s: $error');
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.pump();
    }
    expect(reachedServer, isTrue, reason: 'Device network failure: $lastError');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
