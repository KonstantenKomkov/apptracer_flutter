import 'dart:async';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_aurora/apptracer_flutter_aurora.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Future<void> waitForUpload() async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (await AuroraTracer.isUploading()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('upload_timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final dir =
      '${Platform.environment['HOME']}/.local/share/ru.apptracer/apptracer_flutter_aurora_example';
  final input = File('$dir/explicit-test-input');
  if (!await input.exists()) return;
  final lines = await input.readAsLines();
  await input.delete();
  final mode = lines.first;
  if (mode.startsWith('facade-')) {
    try {
      await exerciseFacade(lines);
      stdout.writeln('Acceptance $mode, worker exit 0');
      await stdout.flush();
      if (mode == 'facade-crash')
        Process.killPid(pid, ProcessSignal.sigabrt);
      else
        exit(0);
    } catch (error) {
      if (error is StateError)
        stderr.writeln('Acceptance failed: ${error.message}');
      exit(3);
    }
    return;
  }
  final network = File('$dir/fixture-network');
  final attempted = File('$dir/fixture-attempt');
  if (await network.exists()) await network.delete();
  if (await attempted.exists()) await attempted.delete();
  ServerSocket? server;
  final hello = Completer<void>();
  final closed = Completer<void>();
  if (mode == 'offline') {
    await network.writeAsString('-1', flush: true);
  } else if (mode == 'hold') {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await network.writeAsString('${server.port}', flush: true);
    server.listen((socket) {
      socket.listen(
        (bytes) {
          if (bytes.isNotEmpty && bytes.first == 0x16 && !hello.isCompleted)
            hello.complete();
        },
        onDone: () {
          if (hello.isCompleted && !closed.isCompleted) closed.complete();
          socket.destroy();
        },
        onError: (Object _) {
          socket.destroy();
        },
      );
    });
  }
  try {
    final start = AuroraTracer.startCollection(
      appToken: lines[1],
      accountScope: mode == 'switch' ? 'fixture-B' : 'fixture-A',
      versionName: '2.0.0',
      versionCode: 202,
      preservePreviousReports: mode != 'arm' && mode != 'revoke',
    );
    if (mode == 'cancel') {
      final cancelled = start.then(
        (_) => false,
        onError: (Object error) =>
            error is PlatformException && error.code == 'start_superseded',
      );
      await AuroraTracer.stopAndClearCollection();
      if (!await cancelled) throw StateError('start_survived_revocation');
      stdout.writeln('Acceptance cancel, worker exit 0');
      await stdout.flush();
      exit(0);
    }
    final result = await start;
    stdout.writeln('Acceptance state $result');
    if (const {'upload', 'offline', 'hold'}.contains(mode) &&
        result != 'replayed')
      throw StateError('missing_replay');
    if (const {'retry', 'switch', 'fresh'}.contains(mode) &&
        result != 'started')
      throw StateError('stale_account_replay');
    if (mode == 'arm') {
      await AuroraTracer.setKey('aurora_runner', 'consent-adapter');
      await AuroraTracer.log(
        'Разрешённое падение Flutter runner через адаптер Авроры',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } else if (mode == 'hold') {
      await hello.future.timeout(const Duration(seconds: 15));
      if (!await AuroraTracer.isUploading())
        throw StateError('expected_active_upload');
      await AuroraTracer.stopAndClearCollection();
      await closed.future.timeout(const Duration(seconds: 5));
      stdout.writeln('Acceptance state cancelled');
    } else if (mode == 'switch') {
      final back = await AuroraTracer.startCollection(
        appToken: lines[1],
        accountScope: 'fixture-A',
        versionName: '2.0.0',
        versionCode: 202,
        preservePreviousReports: true,
      );
      if (back != 'started') throw StateError('stale_account_restored');
      await AuroraTracer.stopAndClearCollection();
    } else if (mode == 'revoke') {
      await AuroraTracer.stopAndClearCollection();
    } else {
      await waitForUpload();
      if (mode == 'offline' && !await attempted.exists())
        throw StateError('network_failure_missing');
    }
    if (mode == 'hold' || mode == 'revoke' || mode == 'switch') {
      if (await File('$dir/apptracer-native-v2/consent').exists() ||
          await Directory('$dir/apptracer-native-v2/sessions').exists())
        throw StateError('queue_not_cleared');
      try {
        await AuroraTracer.log('disabled fixture');
        throw StateError('writer_after_revoke');
      } on PlatformException catch (error) {
        if (error.code != 'collection_disabled') rethrow;
      }
    }
    if (await network.exists()) await network.delete();
    await server?.close();
    stdout.writeln('Acceptance $mode, worker exit 0');
    await stdout.flush();
    if (mode == 'arm' || mode == 'revoke') {
      Process.killPid(pid, ProcessSignal.sigabrt);
    } else {
      exit(0);
    }
  } on PlatformException catch (error) {
    stderr.writeln('Acceptance failed: ${error.code}');
    exit(2);
  } catch (error) {
    stderr.writeln('Acceptance failed: ${error.runtimeType}');
    exit(3);
  }
}

@pragma('vm:never-inline')
void throwFacadeError() => throw StateError('Аврора 2.0.0 facade acceptance');

Future<void> exerciseFacade(List<String> lines) async {
  final mode = lines.first;
  final diagnostics = <TracerDeliveryDiagnostic>[];
  final options = TracerOptions(
    appToken: lines[1],
    dsn: mode == 'facade-dart' ? lines[2] : null,
    release: '2.0.0',
    dist: '203',
    auroraAccountScope: 'facade-fixture',
    nativeInitialization: TracerNativeInitialization.deferred,
    captureFlutterErrors: false,
    capturePlatformDispatcherErrors: false,
    captureZoneErrors: false,
    preservePreviousReports: mode == 'facade-replay',
    deliveryListener: diagnostics.add,
  );
  var runs = 0;
  await Tracer.initialize(
    options: options,
    appRunner: () {
      runs++;
    },
  );
  if (runs != 1 || Tracer.isEnabled)
    throw StateError('deferred_bootstrap_failed');
  final result = await Tracer.startCollection(options);
  if (!result.isEnabled)
    throw StateError(result.reason ?? 'platform_unavailable');
  if (mode == 'facade-replay') {
    await waitForUpload();
    return;
  }
  if (mode == 'facade-dart') {
    // The subsequent identity transition discards the large native log.
    await Tracer.recordLog('ю𐍈' * 24000);
  }
  await Tracer.setCustomKey(key: 'removed_key', value: 'old');
  await Tracer.setUserId('fixture-previous-user');
  await Tracer.removeCustomKey('removed_key');
  await Tracer.setUserId(null);
  await Tracer.setCustomKey(key: 'aurora_public_api', value: 'проверено');
  await Tracer.setCustomKey(key: 'aurora_public_api', value: 'проверено');
  Tracer.log('Контрольный шаг через публичный API', category: 'аврора');
  if (mode == 'facade-dart') {
    try {
      throwFacadeError();
    } catch (error, stack) {
      await Tracer.recordError(error, stack);
    }
    if (!diagnostics.any(
      (d) =>
          d.operation == 'recordError' && d.state == TracerDeliveryState.sent,
    ))
      throw StateError('no_dart_delivery_receipt');
    if ((await Tracer.stopAndClearCollection()).state ==
            TracerCollectionState.disabled &&
        !Tracer.isEnabled)
      return;
    throw StateError('facade_stop_failed');
  }
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (diagnostics.any((d) => d.state == TracerDeliveryState.failed))
    throw StateError('facade_operation_failed');
}
