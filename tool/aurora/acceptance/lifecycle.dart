import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_aurora/apptracer_flutter_aurora.dart';

Future<void> verifyConsentRecovery(String token) async {
  final path =
      "${Platform.environment['HOME']}/.local/share/ru.apptracer/apptracer_flutter_aurora_example/apptracer-native-v2/consent";
  final lease = File(path);
  final options = TracerOptions(
    appToken: token,
    nativeInitialization: TracerNativeInitialization.deferred,
  );
  if (!(await Tracer.startCollection(options)).isEnabled ||
      jsonDecode(await lease.readAsString())['scoped'] != false) {
    throw StateError('unscoped_session_not_isolated');
  }
  final next = await AuroraTracer.startCollection(
    appToken: token,
    accountScope: 'no-replay',
    versionName: '2.0.0',
    versionCode: 1,
    preservePreviousReports: true,
  );
  if (next != 'started') throw StateError('anonymous_session_reused');

  // A nonempty directory forces removal of this fixture's consent file to fail.
  await lease.delete();
  final blocked = Directory(path);
  await blocked.create();
  final sentinel = File('$path/test-only');
  await sentinel.writeAsString('fixture');
  try {
    final result = await Tracer.stopAndClearCollection();
    final prctl = DynamicLibrary.process()
        .lookupFunction<
          Int32 Function(
            Int32,
            UnsignedLong,
            UnsignedLong,
            UnsignedLong,
            UnsignedLong,
          ),
          int Function(int, int, int, int, int)
        >('prctl');
    if (result.state != TracerCollectionState.error ||
        prctl(3, 0, 0, 0, 0) != 0) {
      throw StateError('dump_enabled_after_failed_withdrawal');
    }
    // Even while the filesystem remains unavailable a new grant must stay off.
    if ((await Tracer.startCollection(options)).isEnabled)
      throw StateError('failed_cleanup_bypassed');
  } finally {
    await sentinel.delete();
    await blocked.delete();
  }
  if (!(await Tracer.startCollection(options)).isEnabled ||
      (await Tracer.stopAndClearCollection()).state !=
          TracerCollectionState.disabled) {
    throw StateError('cleanup_recovery_failed');
  }
}

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
    await verifyConsentRecovery(token);
  } finally {
    await server.close(force: true);
  }
}
