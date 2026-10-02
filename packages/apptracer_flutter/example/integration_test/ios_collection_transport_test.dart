// Physical iOS only: run with flutter drive --profile (no LLDB attached).
// A loopback server observes real SDK requests without sending probe data out.
import 'dart:async';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS stops new requests and offline retries after revocation',
      (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var accept = true;
    var completed = 0;
    const holdFailure = bool.fromEnvironment('TRACER_TEST_INFLIGHT');
    // ignore: avoid_print
    print('IOS TRANSPORT: holdFailure=$holdFailure');
    final releaseFailure = Completer<void>();
    final requests = <int>[];
    final subscription = server.listen((request) async {
      final bytes =
          await request.fold<int>(0, (total, data) => total + data.length);
      requests.add(bytes);
      final accepted = accept;
      if (!accepted && holdFailure) await releaseFailure.future;
      request.response.statusCode = accepted ? 200 : 503;
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(accepted ? '{"success":true}' : '{"success":false}');
      await request.response.close();
      completed++;
      // Only counts/statuses: never log credentials, URLs, or report contents.
      // ignore: avoid_print
      print(
          'IOS TRANSPORT: request=$completed bytes=$bytes accepted=$accepted');
    });
    addTearDown(() async {
      if (!releaseFailure.isCompleted) releaseFailure.complete();
      await subscription.cancel();
      await server.close(force: true);
    });

    const token = String.fromEnvironment('TRACER_APP_TOKEN');
    expect(token, isNotEmpty);
    final options = TracerOptions(
      iosAppToken: token,
      apiUrl: 'http://127.0.0.1:${server.port}',
      nativeInitialization: TracerNativeInitialization.deferred,
      captureZoneErrors: false,
      debug: true,
    );
    await Tracer.initialize(
      options: options,
      appRunner: () => runApp(const SizedBox.shrink()),
    );
    final started = await Tracer.startCollection(options);
    expect(Tracer.isEnabled, isTrue,
        reason: '${started.state.name}: ${started.reason}');
    await Tracer.recordError(
        StateError('ios-online-before-revoke'), StackTrace.current);
    await _waitFor(() => completed > 0);
    expect(requests.any((bytes) => bytes > 0), isTrue);
    await Future<void>.delayed(const Duration(seconds: 4));

    accept = false;
    final beforeOffline = requests.length;
    await Tracer.recordError(
        StateError('ios-offline-before-revoke'), StackTrace.current);
    await _waitFor(() => requests.length > beforeOffline);
    if (!holdFailure) await _waitFor(() => completed == requests.length);
    await Future<void>.delayed(const Duration(seconds: 1));

    final stopping = Tracer.stopAndClearCollection();
    expect(Tracer.isEnabled, isFalse);
    final stopped = await stopping;
    expect(stopped.state, TracerCollectionState.restartRequired);
    final atStop = requests.length;
    accept = true;
    releaseFailure.complete();

    await Tracer.recordError(
        StateError('ios-dart-after-revoke'), StackTrace.current);
    await Tracer.recordLog('after-revoke');
    await Tracer.setUserId('after-revoke');
    await Tracer.setCustomKey(key: 'after-revoke', value: 'discard');
    Tracer.log('after-revoke');
    // Bypass Dart guards to exercise the Swift plugin's own disabled guards.
    const native = MethodChannel('ru.apptracer.flutter/tracer');
    await native.invokeMethod<void>('recordError', <String, Object>{
      'exceptionType': 'StateError',
      'message': 'ios-native-channel-after-revoke',
    });
    await native.invokeMethod<void>(
        'recordLog', <String, String>{'message': 'discard'});
    await native
        .invokeMethod<void>('setUserId', <String, String>{'userId': 'discard'});
    final restart = await Tracer.startCollection(options);
    expect(restart.isEnabled, isFalse);
    expect(Tracer.isEnabled, isFalse);
    expect(Tracer.breadcrumbs, isEmpty);
    expect(Tracer.client.customKeys, isEmpty);
    await Future<void>.delayed(const Duration(seconds: 35));
    expect(requests.length, atStop,
        reason:
            'SDK sent a new request after revocation and endpoint recovery.');
    // ignore: avoid_print
    print('IOS TRANSPORT: no post-revocation requests in 35s; restart refused');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _waitFor(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition() && elapsed.elapsed < const Duration(seconds: 30)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue,
      reason: 'SDK request did not reach the loopback server.');
}
