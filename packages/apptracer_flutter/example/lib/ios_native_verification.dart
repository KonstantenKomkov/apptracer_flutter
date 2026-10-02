// Standalone release entrypoint for physical-device acceptance. Launch with
// APPTRACER_VERIFY_SCENARIO via devicectl; default launch never starts the SDK.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _native = MethodChannel('ru.apptracer.flutter.example/native');

@pragma('vm:entry-point')
Future<void> secondaryConsentProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  const tracer = MethodChannel('ru.apptracer.flutter/tracer');
  const result = MethodChannel('ru.apptracer.flutter.example/secondary');
  final before =
      await tracer.invokeMapMethod<String, dynamic>('getCollectionState');
  final initialized = await tracer.invokeMethod<bool>('initialize', {
    'appToken': const String.fromEnvironment('TRACER_APP_TOKEN'),
  });
  await tracer
      .invokeMethod<void>('recordLog', {'message': 'secondary-engine-probe'});
  await result.invokeMethod<void>(
      'result', {'before': before, 'initialized': initialized});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final context =
      await _native.invokeMapMethod<String, String>('verificationContext');
  final scenario = context!['scenario']!;
  final library = Directory(context['libraryPath']!);
  final results = Directory('${library.path}/ApptracerVerification');
  await results.create(recursive: true);
  final output = File('${results.path}/$scenario.json');
  final status = ValueNotifier<String>('Preparing $scenario');
  runApp(MaterialApp(
      home: Scaffold(
          body: Center(
              child: ValueListenableBuilder<String>(
    valueListenable: status,
    builder: (_, value, __) => Text(value, textAlign: TextAlign.center),
  )))));
  Future<void> save(Map<String, Object?> value) async {
    await output.writeAsString(
        jsonEncode(<String, Object?>{
          'scenario': scenario,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          ...value,
        }),
        flush: true);
    status.value = '$scenario\n${value['stage']}';
  }

  if (scenario == 'inspect') {
    status.value = 'Acceptance app idle. SDK not initialized.';
    return;
  }
  const scenarios = <String>{
    'native-enabled',
    'native-revoked',
    'deferred-recovery',
    'recovery',
    'dart-errors',
    'new-consent',
    'multi-engine',
    'cleanup-failure',
    'missing-token',
    'account-a',
    'account-b'
  };
  if (!scenarios.contains(scenario)) {
    await save(<String, Object?>{'stage': 'invalid-scenario'});
    return;
  }
  HttpServer? sink;
  var requests = 0;
  // Native crash/stop probes stay on the phone. Only explicit recovery and
  // Dart delivery scenarios use the actual vendor endpoint.
  if (scenario == 'native-enabled' ||
      scenario == 'native-revoked' ||
      scenario == 'new-consent' ||
      scenario == 'multi-engine' ||
      scenario == 'cleanup-failure' ||
      scenario == 'missing-token' ||
      scenario == 'account-a' ||
      scenario == 'account-b') {
    sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sink.listen((request) async {
      final body = <int>[];
      await for (final chunk in request) {
        if (scenario.startsWith('account-')) body.addAll(chunk);
      }
      requests++;
      if (scenario.startsWith('account-')) {
        // Test-only local request capture; never print its body or app token.
        await File('${results.path}/$scenario-$requests.body')
            .writeAsBytes(body);
        await File('${results.path}/$scenario-$requests.headers').writeAsString(
            'Content-Type: ${request.headers.contentType}\r\n'
            'Content-Encoding: ${request.headers.value('content-encoding') ?? ''}\r\n');
      }
      if (scenario == 'account-a') request.response.statusCode = 503;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"success":true}');
      await request.response.close();
    });
  }
  final deferred = scenario == 'deferred-recovery';
  const token = String.fromEnvironment('TRACER_APP_TOKEN');
  final options = TracerOptions(
    iosAppToken: scenario == 'missing-token' ? null : token,
    // Even a request to preserve reports must not override a prior revocation.
    preservePreviousReports:
        scenario == 'new-consent' || scenario == 'account-b',
    apiUrl: sink == null ? null : 'http://127.0.0.1:${sink.port}',
    nativeInitialization: deferred || sink != null
        ? TracerNativeInitialization.deferred
        : TracerNativeInitialization.automatic,
    captureZoneErrors: false,
    debug: true,
  );
  if (scenario == 'cleanup-failure') {
    // The test app's SDK paths are sealed by the preceding stop. Inject only
    // at that known empty guard file; never replace an existing data directory.
    final guard = File('${library.path}/TracerStorage');
    final sentinel = File('${results.path}/must-survive-cleanup');
    final link = Link(guard.path);
    if (FileSystemEntity.typeSync(guard.path, followLinks: false) !=
            FileSystemEntityType.file ||
        guard.lengthSync() != 0) {
      await save({
        'stage': 'error',
        'error': 'Run a successful stop before cleanup-failure'
      });
      return;
    }
    await sentinel.writeAsString('unrelated-data');
    await guard.delete();
    await link.create(results.path);
    try {
      await Tracer.initialize(options: options, appRunner: () {});
      final failed = await Tracer.startCollection(options);
      final again = await Tracer.startCollection(options);
      if (failed.reason != 'native_cleanup_failed' ||
          again.isEnabled ||
          Tracer.isEnabled ||
          !await sentinel.exists() ||
          requests != 0) {
        throw StateError('Cleanup failure did not keep collection off');
      }
      await save({
        'stage': 'complete',
        'enabled': false,
        'state': failed.state.name,
        'reason': failed.reason,
        'unrelatedFilePreserved': true,
        'requests': requests
      });
    } catch (error) {
      await save({'stage': 'error', 'error': '$error'});
    } finally {
      await link.delete();
      await guard.writeAsBytes([]);
      await sentinel.delete();
    }
    return;
  }
  try {
    await Tracer.initialize(options: options, appRunner: () {});
    final initial = sink == null
        ? await Tracer.getCollectionState()
        : await Tracer.startCollection(options);
    await save(<String, Object?>{
      'stage': 'initialized',
      'enabled': Tracer.isEnabled,
      'state': initial.state.name,
      'reason': initial.reason
    });
    if (scenario == 'missing-token') {
      if (initial.reason != 'app_token_missing' ||
          Tracer.isEnabled ||
          requests != 0) {
        throw StateError('Missing token did not keep collection off');
      }
      await save({
        'stage': 'complete',
        'enabled': false,
        'state': initial.state.name,
        'reason': initial.reason,
        'requests': requests
      });
      return;
    }
    if (deferred) {
      final start = await Tracer.getCollectionState();
      await Tracer.recordError(
          StateError('deferred-must-not-send'), StackTrace.current);
      await Future<void>.delayed(const Duration(seconds: 10));
      await save(<String, Object?>{
        'stage': 'complete',
        'enabled': Tracer.isEnabled,
        'state': start.state.name,
        'reason': start.reason
      });
      return;
    }
    if (!Tracer.isEnabled) {
      throw StateError('Native start failed: ${initial.reason}');
    }
    if (scenario == 'multi-engine') {
      final active = await _native
          .invokeMapMethod<String, dynamic>('checkSecondaryEngine');
      if (active?['initialized'] != true ||
          active?['before']['state'] != 'enabled') {
        throw StateError('Second engine did not share active state: $active');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      final stopped = await Tracer.stopAndClearCollection();
      for (var i = 0; i < 2; i++) {
        final off = await _native
            .invokeMapMethod<String, dynamic>('checkSecondaryEngine');
        if (off?['initialized'] != false ||
            off?['before']['state'] != 'restartRequired') {
          throw StateError('Engine recreation bypassed revoke: $off');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (requests != 0) {
        throw StateError('Unexpected engine upload: $requests');
      }
      await save({
        'stage': 'complete',
        'enabled': Tracer.isEnabled,
        'state': stopped.state.name,
        'secondaryEngines': 3,
        'requests': requests
      });
      return;
    }
    if (scenario.startsWith('account-')) {
      if (scenario == 'account-b') {
        await Future<void>.delayed(const Duration(seconds: 20));
        if (requests != 0) throw StateError('Old account reports replayed');
      }
      final marker = scenario == 'account-a'
          ? 'CONSENT_ACCOUNT_A_821'
          : 'CONSENT_ACCOUNT_B_927';
      await Tracer.setUserId(marker);
      await Tracer.setCustomKey(key: marker, value: marker);
      await Tracer.recordLog(marker);
      await Tracer.recordError(StateError(marker), StackTrace.current);
      for (var i = 0; i < 30 && requests == 0; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (requests == 0) throw StateError('No account probe request');
      final beforeStop = requests;
      final stopped = await Tracer.stopAndClearCollection();
      await Future<void>.delayed(const Duration(seconds: 10));
      if (requests != beforeStop) {
        throw StateError('Upload after account revoke');
      }
      await save({
        'stage': 'complete',
        'state': stopped.state.name,
        'enabled': Tracer.isEnabled,
        'requests': requests,
        'oldReportsReplayed': false,
      });
      return;
    }
    await Tracer.setUserId('ios-acceptance-$scenario');
    if (scenario == 'dart-errors') {
      await Tracer.recordError(
          FormatException('ios-release-delivery-probe'), StackTrace.current);
    }
    await Future<void>.delayed(const Duration(seconds: 20));
    if (scenario == 'new-consent') {
      if (requests != 0) throw StateError('Old reports replayed: $requests');
      await Tracer.recordError(
          StateError('fresh-after-new-consent'), StackTrace.current);
      await Future<void>.delayed(const Duration(seconds: 10));
      if (requests != 1) throw StateError('Fresh delivery count: $requests');
    }
    if (scenario == 'native-enabled') {
      await save(<String, Object?>{
        'stage': 'crashing-enabled',
        'requests': requests,
        'enabled': Tracer.isEnabled
      });
      await _native.invokeMethod<void>('crashForConsentVerification');
      return;
    }
    final stopped = await Tracer.stopAndClearCollection();
    await Tracer.recordError(
        StateError('ios-release-after-revoke'), StackTrace.current);
    await save(<String, Object?>{
      'stage': 'stopped',
      'enabled': Tracer.isEnabled,
      'state': stopped.state.name,
      'reason': stopped.reason,
      'requests': requests
    });
    if (scenario == 'native-revoked') {
      await Future<void>.delayed(const Duration(seconds: 3));
      await save(<String, Object?>{
        'stage': 'crashing-revoked',
        'enabled': Tracer.isEnabled,
        'state': stopped.state.name,
        'reason': stopped.reason,
        'requests': requests
      });
      await _native.invokeMethod<void>('crashForConsentVerification');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 10));
    await save(<String, Object?>{
      'stage': 'complete',
      'enabled': Tracer.isEnabled,
      'state': stopped.state.name,
      'reason': stopped.reason,
      'requests': requests
    });
  } catch (error) {
    await save(<String, Object?>{'stage': 'error', 'error': '$error'});
  }
}
