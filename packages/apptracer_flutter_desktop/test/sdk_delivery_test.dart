import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('official SDK preserves filtered payload and owns no Dart handlers',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()..install();
    final adapter = SentryDesktopTracer();
    final originalHandler = FlutterError.onError;
    final client = TracerClient(platform: adapter);
    await client.start(TracerOptions(
      dsn: 'https://public@tracer.invalid/42',
      release: '1.2.3',
      environment: 'test',
      dist: '7',
      captureFlutterErrors: false,
      capturePlatformDispatcherErrors: false,
      captureZoneErrors: false,
      beforeBreadcrumb: (crumb) => crumb.message == 'secret' ? null : crumb,
      beforeSend: (event) => event.message == 'drop'
          ? null
          : event.copyWith(
              message: 'redacted', customKeys: {}, removeBreadcrumbs: true),
    ));
    expect(client.isEnabled, isTrue);
    // ignore: invalid_use_of_internal_member
    final sdkOptions = Sentry.currentHub.options;
    expect(
        sdkOptions.integrations.map((i) => i.runtimeType.toString()),
        unorderedEquals([
          'WidgetsFlutterBindingIntegration',
          'LoadReleaseIntegration',
          'NativeSdkIntegration',
          'LoadNativeDebugImagesIntegration'
        ]));
    expect(sdkOptions.enableLogs, false);
    expect(sdkOptions.enableMetrics, false);
    expect(FlutterError.onError, same(originalHandler));
    final init =
        probe.calls.singleWhere((call) => call.method == 'initNativeSdk');
    final settings = init.arguments as Map<dynamic, dynamic>;
    expect(settings['dsn'], 'https://public@tracer.invalid/42');
    expect(settings['release'], '1.2.3');
    expect(settings['enableAutoSessionTracking'], false);
    expect(settings['enableAutoPerformanceTracing'], false);
    expect(settings['enableAutoNativeBreadcrumbs'], false);
    await client.setCustomKey(key: 'private-key', value: 'do-not-resurrect');
    await client.setUserId('account-1');
    client.addBreadcrumb(TracerBreadcrumb(message: 'secret'));
    client.addBreadcrumb(TracerBreadcrumb(message: 'visible'));
    const raw = '#0      run (package:example/main.dart:10:3)\n'
        '#1      main (package:example/main.dart:20:4)';
    await client.recordError(
        StateError('sensitive'), StackTrace.fromString(raw),
        fatal: true, issueKey: 'group-1');
    expect(probe.events, hasLength(1));
    final event = probe.events.single;
    expect(event['sdk'], containsPair('name', 'sentry.dart.flutter'));
    expect(event['tags'] ?? <String, dynamic>{}, isEmpty);
    expect(event['breadcrumbs'] ?? <dynamic>[], isEmpty);
    expect(event['user'], containsPair('id', 'account-1'));
    expect(event['level'], 'fatal');
    expect(event['fingerprint'], ['group-1']);
    final exception = (event['exception'] as Map)['values'][0] as Map;
    expect(exception['type'], 'StateError');
    expect(exception['value'], 'redacted');
    final frames = (exception['stacktrace'] as Map)['frames'] as List;
    expect((frames.first as Map)['function'], 'main');
    expect((frames.last as Map)['lineno'], 10);
    expect(((event['contexts'] as Map)['apptracer'] as Map)['dart_stack_trace'],
        raw);
    expect(event.toString(), isNot(contains('do-not-resurrect')));
    expect(event.toString(), isNot(contains('sensitive')));
    await client.recordError('drop', StackTrace.fromString(raw));
    // An unrelated direct Sentry call must not bypass Tracer filtering.
    await Sentry.captureMessage('bypass');
    expect(probe.events, hasLength(1));
    expect(
        probe.calls
            .where((c) => c.method == 'addBreadcrumb')
            .any((c) => c.arguments.toString().contains('secret')),
        isFalse);

    final other = SentryDesktopTracer();
    final refused = await other.startCollection(
        const TracerOptions(dsn: 'https://other@another.invalid/2'));
    expect(refused.reason, 'sentry_already_owned');
    await other.stopCollection();
    expect(Sentry.isEnabled, true);
    await client.stop();
    expect(client.isEnabled, false);
    expect((await adapter.getCollectionState()).state,
        TracerCollectionState.restartRequired);
    await client.recordError('after stop', StackTrace.current);
    expect(probe.events, hasLength(1));
    expect((await adapter.stopAndClearCollection()).state,
        TracerCollectionState.unsupported);
    expect(
        (await adapter.startCollection(
                const TracerOptions(dsn: 'https://public@tracer.invalid/42')))
            .state,
        TracerCollectionState.restartRequired);
  });
}
