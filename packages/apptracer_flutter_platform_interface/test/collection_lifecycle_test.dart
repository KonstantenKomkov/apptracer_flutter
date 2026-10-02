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
