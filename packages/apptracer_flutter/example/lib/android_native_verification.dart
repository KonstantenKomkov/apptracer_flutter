// Release/R8 acceptance harness. Default launch leaves the SDK disabled.
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
  final before =
      await tracer.invokeMapMethod<String, dynamic>('getCollectionState');
  final initialized = await tracer.invokeMethod<bool>('initialize', {});
  await tracer
      .invokeMethod<void>('recordLog', {'message': 'secondary-engine-probe'});
  await const MethodChannel('ru.apptracer.flutter.example/secondary')
      .invokeMethod<void>(
          'result', {'before': before, 'initialized': initialized});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final context =
      (await _native.invokeMapMethod<String, String>('verificationContext'))!;
  final scenario = context['scenario']!;
  final output = Directory(context['outputPath']!);
  await output.create(recursive: true);
  final status = ValueNotifier<String>('Preparing $scenario');
  runApp(MaterialApp(
      home: Scaffold(
          body: Center(
              child: ValueListenableBuilder<String>(
    valueListenable: status,
    builder: (_, value, __) => Text(value, textAlign: TextAlign.center),
  )))));
  Future<Map<String, Object>> files() async {
    final found = <String, Object>{};
    for (final root in ['cachePath', 'filesPath']) {
      final dir = Directory('${context[root]}/tracer');
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is File) {
            found['$root/${f.path.substring(dir.path.length + 1)}'] =
                await f.length();
          }
        }
      }
    }
    return found;
  }

  Future<void> save(String stage,
      [Map<String, Object?> extra = const {}]) async {
    final data = <String, Object?>{
      'scenario': scenario,
      'stage': stage,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'enabled': Tracer.isEnabled,
      'files': await files(),
      ...extra,
    };
    await File('${output.path}/$scenario.json')
        .writeAsString(jsonEncode(data), flush: true);
    status.value = '$scenario\n$stage';
  }

  if (scenario == 'inspect') {
    await save('idle');
    return;
  }
  final vendor = scenario == 'vendor-recovery' || scenario == 'vendor-dart';
  var online = !scenario.startsWith('offline') &&
      scenario != 'account-a' &&
      !scenario.endsWith('-enabled');
  var hold = scenario == 'inflight';
  final held = <HttpRequest>[];
  final requests = <String>[];
  HttpServer? sink;
  Future<void> respond(HttpRequest request) async {
    request.response.statusCode = online ? 200 : 503;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"success":$online}');
    await request.response.close();
  }

  if (!vendor) {
    sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sink.listen((request) async {
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
      }
      requests.add(request.uri.path);
      // Synthetic local probes only; bodies may contain SDK credentials.
      await File('${output.path}/$scenario-${requests.length}.body')
          .writeAsBytes(bytes);
      await File('${output.path}/$scenario-${requests.length}.headers')
          .writeAsString(
              'Content-Type: ${request.headers.contentType}\r\nContent-Encoding: ${request.headers.value('content-encoding') ?? ''}\r\n');
      if (hold) {
        held.add(request);
      } else {
        await respond(request);
      }
    });
  }
  try {
    await _native.invokeMethod<void>('configureVerification',
        {'apiUrl': sink == null ? null : 'http://127.0.0.1:${sink.port}'});
    final options = TracerOptions(
      nativeInitialization: TracerNativeInitialization.deferred,
      preservePreviousReports:
          scenario.contains('recovery') || scenario == 'account-b',
      captureZoneErrors: false,
      debug: true,
    );
    await Tracer.initialize(options: options, appRunner: () {});
    final cold = await Tracer.getCollectionState();
    if (Tracer.isEnabled) throw StateError('Cold bootstrap enabled the SDK');
    await save('cold', {'state': cold.state.name});
    if (scenario == 'missing-sdk' || scenario == 'missing-token') {
      final expected = scenario == 'missing-sdk'
          ? TracerCollectionState.unsupported
          : TracerCollectionState.error;
      final reason =
          scenario == 'missing-sdk' ? 'sdk_missing' : 'app_token_missing';
      final result = await Tracer.startCollection(options);
      if (result.state != expected ||
          result.reason != reason ||
          Tracer.isEnabled) {
        throw StateError(
            'Unexpected missing dependency result: ${result.state.name}/${result.reason}');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      if (requests.isNotEmpty || (await files()).isNotEmpty) {
        throw StateError('Missing dependency created diagnostics');
      }
      await save('complete', {
        'state': result.state.name,
        'reason': result.reason,
        'requests': requests
      });
      return;
    }
    if (scenario == 'initial-cleanup-failure') {
      final sentinel = File('${context['cachePath']}/verification-sentinel');
      await sentinel.writeAsString('keep');
      try {
        await _native
            .invokeMethod<void>('cleanupFailureFixture', {'enabled': true});
        for (var i = 0; i < 2; i++) {
          final result = await Tracer.startCollection(options);
          if (result.state != TracerCollectionState.error || Tracer.isEnabled) {
            throw StateError('Cleanup failure permitted start');
          }
        }
        if (requests.isNotEmpty || await sentinel.readAsString() != 'keep') {
          throw StateError(
              'Cleanup failure sent data or removed unrelated file');
        }
      } finally {
        await _native
            .invokeMethod<void>('cleanupFailureFixture', {'enabled': false});
        await Tracer.stopAndClearCollection();
        await sentinel.delete();
      }
      await save('complete', {'requests': requests, 'failedStarts': 2});
      return;
    }
    if (scenario.startsWith('cold')) {
      await Tracer.recordError(StateError('off-probe'), StackTrace.current);
      await Future<void>.delayed(const Duration(seconds: 10));
      if (requests.isNotEmpty) throw StateError('Cold HTTP requests');
      await save('complete', {'requests': requests, 'state': cold.state.name});
      return;
    }
    final started = await Tracer.startCollection(options);
    if (!started.isEnabled) {
      throw StateError('Start: ${started.state.name}/${started.reason}');
    }
    await save('started', {'state': started.state.name});
    if (scenario == 'stop-cleanup-failure') {
      try {
        await _native
            .invokeMethod<void>('cleanupFailureFixture', {'enabled': true});
        final stopped = await Tracer.stopAndClearCollection();
        if (stopped.state != TracerCollectionState.error || Tracer.isEnabled) {
          throw StateError('Cleanup failure falsely succeeded');
        }
        final count = requests.length;
        await Tracer.recordError(
            StateError('after-failed-cleanup'), StackTrace.current);
        final restarted = await Tracer.startCollection(options);
        if (restarted.isEnabled) {
          throw StateError('Failed cleanup allowed restart');
        }
        await Future<void>.delayed(const Duration(seconds: 35));
        if (requests.length != count) {
          throw StateError('Request after failed cleanup');
        }
        await save('failure-observed', {
          'state': stopped.state.name,
          'reason': stopped.reason,
          'requestsAfterStop': requests.length - count
        });
      } finally {
        await _native
            .invokeMethod<void>('cleanupFailureFixture', {'enabled': false});
        await Tracer.stopAndClearCollection();
      }
      await save('complete', {'requests': requests});
      return;
    }
    if (scenario.contains('recovery') || scenario == 'account-b') {
      await Future<void>.delayed(const Duration(seconds: 20));
      await save('recovery-observed', {
        'requests': requests,
        'exitInfo': await _native.invokeMethod<Object>('exitInfo')
      });
      if ((scenario == 'revoked-recovery' || scenario == 'account-b') &&
          requests.any((p) => p.contains('/crash/upload'))) {
        throw StateError('Revoked report replayed');
      }
    }
    if (scenario == 'multi-engine') {
      final active = await _native
          .invokeMapMethod<String, dynamic>('checkSecondaryEngine');
      if (active?['before']['state'] != 'enabled' ||
          active?['initialized'] != true) {
        throw StateError('Second engine did not share active service');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      final stopped = await Tracer.stopAndClearCollection();
      final beforeStop = requests.length;
      for (var i = 0; i < 2; i++) {
        final off = await _native
            .invokeMapMethod<String, dynamic>('checkSecondaryEngine');
        if (off?['before']['state'] != 'restartRequired' ||
            off?['initialized'] != false) {
          throw StateError('Secondary engine bypassed revocation');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (requests.length != beforeStop) {
        throw StateError('Engine sent after revoke');
      }
      await save('complete', {
        'state': stopped.state.name,
        'secondaryEngines': 3,
        'requestsAfterStop': requests.length - beforeStop
      });
      return;
    }
    final marker = scenario == 'account-a'
        ? 'ANDROID_ACCOUNT_A_821'
        : scenario == 'account-b'
            ? 'ANDROID_ACCOUNT_B_927'
            : 'android-$scenario';
    await Tracer.setUserId(marker);
    await Tracer.setCustomKey(key: marker, value: marker);
    await Tracer.recordLog(marker);
    final fatal = scenario.contains('jvm') ||
        scenario.contains('native') ||
        scenario.contains('anr');
    if (!fatal && !scenario.contains('recovery')) {
      await Tracer.recordError(StateError(marker), StackTrace.current,
          issueKey: 'android-consent-probe');
      if (!vendor) {
        for (var i = 0;
            i < 40 && !requests.any((p) => p.contains('/crash/upload'));
            i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!requests.any((p) => p.contains('/crash/upload'))) {
          throw StateError('No crash request reached loopback');
        }
      } else {
        await Future<void>.delayed(const Duration(seconds: 20));
      }
    }
    if (scenario.endsWith('-enabled')) {
      await save('crashing-enabled', {'requests': requests});
      await _native.invokeMethod<void>(scenario.startsWith('jvm')
          ? 'crashJvm'
          : scenario.startsWith('native')
              ? 'crashNatively'
              : 'blockMainThread');
      return;
    }
    final before = requests.length;
    final stopping = Tracer.stopAndClearCollection();
    if (Tracer.isEnabled) {
      throw StateError('Dart collection stayed enabled during stop');
    }
    hold = false;
    for (final r in held) {
      await respond(r);
    }
    final stopped = await stopping;
    if (stopped.state != TracerCollectionState.restartRequired) {
      throw StateError('Stop: ${stopped.state.name}/${stopped.reason}');
    }
    online = true;
    await Tracer.recordError(
        StateError('after-revoke-must-not-send'), StackTrace.current);
    await Tracer.recordLog('after-revoke');
    await save('stopped', {'state': stopped.state.name, 'requests': requests});
    if (scenario == 'activity') {
      await save('recreating', {'state': stopped.state.name});
      await _native.invokeMethod<void>('recreateForVerification');
      return;
    }
    if (fatal) {
      await save('crashing-revoked',
          {'requests': requests, 'state': stopped.state.name});
      await _native.invokeMethod<void>(scenario.startsWith('jvm')
          ? 'crashJvm'
          : scenario.startsWith('native')
              ? 'crashNatively'
              : 'blockMainThread');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 35));
    if (requests.length != before) {
      throw StateError('New HTTP request after revoke');
    }
    if ((await files()).isNotEmpty) {
      throw StateError('Diagnostic files remained after stop');
    }
    if ((await Tracer.startCollection(options)).isEnabled) {
      throw StateError('Restarted in revoked process');
    }
    await save('complete', {
      'state': stopped.state.name,
      'requests': requests,
      'requestsAfterStop': requests.length - before
    });
  } catch (error) {
    await Tracer.stopAndClearCollection();
    await save('error', {'error': '$error', 'requests': requests});
  }
}
