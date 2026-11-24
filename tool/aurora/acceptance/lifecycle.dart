import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';

/// The first receiver withholds its HTTP response until collection is revoked.
Future<void> exerciseLifecycle(String token) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final received = Completer<void>();
  final disconnected = Completer<void>();
  final accepted = Completer<Map>();
  var count = 0;
  server.listen((request) async {
    try {
      final bytes = await request.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );
      final body = request.headers.value('content-encoding') == 'gzip'
          ? gzip.decode(bytes)
          : bytes;
      final event = const LineSplitter()
          .convert(utf8.decode(body))
          .map(jsonDecode)
          .whereType<Map>()
          .firstWhere((line) => line['exception'] is Map);
      if (++count == 1) {
        final peer = await request.response.detachSocket(writeHeaders: false);
        peer.listen(
          (_) {},
          onDone: () {
            peer.destroy();
            disconnected.complete();
          },
          onError: (Object error) => disconnected.completeError(error),
        );
        received.complete();
      } else {
        request.response.write(jsonEncode({'id': event['event_id']}));
        await request.response.close();
        if (!accepted.isCompleted) accepted.complete(event);
      }
    } catch (error, stack) {
      if (!received.isCompleted) {
        received.completeError(error, stack);
      } else if (!accepted.isCompleted) {
        accepted.completeError(error, stack);
      }
    }
  });
  const limit = Duration(seconds: 10);
  final a = TracerOptions(
    appToken: token,
    dsn: 'http://fixture@127.0.0.1:${server.port}/1',
    auroraAccountScope: 'lifecycle-A',
    nativeInitialization: TracerNativeInitialization.deferred,
    captureFlutterErrors: false,
    capturePlatformDispatcherErrors: false,
    captureZoneErrors: false,
  );
  final b = a.copyWith(auroraAccountScope: 'lifecycle-B');
  Future<void> send(String value) =>
      Tracer.recordError(StateError(value), StackTrace.current);
  Future<void> requireDisabled() async {
    if (Tracer.isEnabled ||
        (await Tracer.getCollectionState()).state !=
            TracerCollectionState.disabled) {
      throw StateError('expected_disabled');
    }
  }

  try {
    await Tracer.initialize(options: a, appRunner: () {});
    await requireDisabled();
    await send('disabled');
    if (!(await Tracer.startCollection(a)).isEnabled ||
        !(await Tracer.startCollection(a)).isEnabled)
      throw StateError('start_failed');
    await Tracer.setUserId('previous-user');
    await Tracer.setCustomKey(key: 'previous_key', value: 'account-A');
    Tracer.log('previous-account-log');
    final sending = send('pending-A');
    await received.future.timeout(limit);
    if ((await Tracer.stopAndClearCollection().timeout(limit)).state !=
        TracerCollectionState.disabled) {
      throw StateError('withdraw_failed');
    }
    await disconnected.future.timeout(limit);
    await sending.timeout(limit);
    await requireDisabled();
    await send('revoked');
    final pending = Tracer.startCollection(a);
    await Future<void>.delayed(Duration.zero);
    await Tracer.stopAndClearCollection().timeout(limit);
    await pending.timeout(limit);
    await requireDisabled();
    if (!(await Tracer.startCollection(b)).isEnabled)
      throw StateError('restart_failed');
    await Tracer.setUserId('current-user');
    await Tracer.setCustomKey(key: 'current_key', value: 'account-B');
    await send('current-B').timeout(limit);
    final event = await accepted.future.timeout(limit);
    final encoded = jsonEncode(event);
    if (count != 2 ||
        event['user']?['id'] != 'current-user' ||
        event['tags']?['current_key'] != 'account-B' ||
        [
          'previous-user',
          'previous_key',
          'previous-account-log',
          'pending-A',
        ].any(encoded.contains)) {
      throw StateError('account_context_leaked');
    }
    await Tracer.initialize(options: b, appRunner: () {});
    await requireDisabled();
    if (!(await Tracer.startCollection()).isEnabled)
      throw StateError('deferred_restart_failed');
    await Tracer.stopCollection();
    await Tracer.stopCollection();
    await requireDisabled();
  } finally {
    await server.close(force: true);
  }
}
