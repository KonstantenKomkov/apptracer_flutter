import 'dart:async';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('consent-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelTracer platform;
  setUp(() {
    platform = MethodChannelTracer(channel: channel, backendName: 'test');
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('pause and resume use public channel methods', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return {
        'state': call.method == 'pauseCollection' ? 'disabled' : 'enabled'
      };
    });
    await platform.startCollection(const TracerOptions());
    final pause = platform.pauseCollection();
    expect(platform.isEnabled, isFalse);
    await pause;
    expect((await platform.resumeCollection()).isEnabled, isTrue);
    expect(platform.isEnabled, isTrue);
    expect(methods, ['startCollection', 'pauseCollection', 'resumeCollection']);
  });

  test('late resume answer cannot enable after clear', () async {
    final reply = Completer<Map<String, String>>();
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'resumeCollection'
            ? reply.future
            : {'state': 'disabled'});
    final resume = platform.resumeCollection();
    await Future<void>.delayed(Duration.zero);
    await platform.stopAndClearCollection();
    reply.complete({'state': 'enabled'});
    expect((await resume).reason, 'superseded');
    expect(platform.isEnabled, isFalse);
  });

  test(
      'optional commands preserve arguments and distinguish invocation from delivery',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'state': call.method == 'startCollection' ? 'enabled' : 'invoked'
      };
    });
    expect(
        (await platform.runDiskUsage()).state, TracerDiagnosticState.disabled);
    expect(calls, isEmpty);
    await platform.startCollection(const TracerOptions());
    expect((await platform.runHeapDump(tag: 'manual')).state,
        TracerDiagnosticState.invoked);
    expect(calls.last.arguments, {'tag': 'manual'});
    await platform.runDiskUsage();
    expect(calls.last.method, 'runDiskUsage');
    await platform.setHeapDumpEnabled(true);
    expect(calls.last.arguments, {'enabled': true});
  });

  test('missing optional commands and malformed replies fail explicitly',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'state': 'enabled'});
    await platform.startCollection(const TracerOptions());
    expect((await platform.runDiskUsage()).reason, 'invalid_native_result');
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    expect((await platform.runDiskUsage()).state,
        TracerDiagnosticState.unsupported);
  });

  test('native state and reason survive the channel', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'state': 'restartRequired',
              'reason': 'one_way_disable',
            });
    final result = await platform.startCollection(const TracerOptions());
    expect(result.state, TracerCollectionState.restartRequired);
    expect(result.reason, 'one_way_disable');
    expect(platform.isEnabled, isFalse);
  });

  test('missing operation is unsupported without guessing purge success',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    final result = await platform.stopAndClearCollection();
    expect(result.state, TracerCollectionState.unsupported);
  });

  test('native cleanup errors are visible and revoke events immediately',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startCollection') return {'state': 'enabled'};
      throw PlatformException(code: 'cleanup_failed');
    });
    await platform.startCollection(const TracerOptions());
    final pending = platform.stopAndClearCollection();
    expect(platform.isEnabled, isFalse);
    expect((await pending).state, TracerCollectionState.error);
  });

  test('late initialize answer cannot enable after stop', () async {
    final reply = Completer<bool>();
    messenger.setMockMethodCallHandler(channel,
        (call) async => call.method == 'initialize' ? reply.future : null);
    final start = platform.initialize(const TracerOptions());
    await Future<void>.delayed(Duration.zero);
    await platform.stopCollection();
    reply.complete(true);
    await start;
    expect(platform.isEnabled, isFalse);
  });

  test('querying native enabled state does not grant Dart permission',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'state': 'enabled'});
    expect((await platform.getCollectionState()).isEnabled, isTrue);
    expect(platform.isEnabled, isFalse);
  });
}
