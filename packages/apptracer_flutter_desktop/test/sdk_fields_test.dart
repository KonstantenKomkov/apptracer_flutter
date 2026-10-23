import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'official SDK carries structured breadcrumbs, keys, user and AOT raw stack',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()..install();
    final adapter = SentryDesktopTracer();
    final client = TracerClient(platform: adapter);
    await client.start(const TracerOptions(
        dsn: 'https://public@tracer.invalid/42',
        release: '2.0.0',
        dist: '42',
        captureFlutterErrors: false,
        capturePlatformDispatcherErrors: false));
    await client.setCustomKey(key: 'ключ', value: 'значение');
    await client.setUserId('one');
    client.addBreadcrumb(TracerBreadcrumb(
        message: 'нажатие',
        category: 'ui',
        level: TracerSeverity.warning,
        data: const {'button': 'send'}));
    const raw = "build_id: 'abc123'\nisolate_dso_base: 1000\n"
        '#00 abs 00001234 virt 00000234 _kDartIsolateSnapshotInstructions+0x234';
    await client.recordError('AOT', StackTrace.fromString(raw),
        severity: TracerSeverity.warning);
    var event = probe.events.last;
    expect(event['tags'], {'ключ': 'значение'});
    final crumb = (event['breadcrumbs'] as List).single as Map;
    expect(crumb['message'], 'нажатие');
    expect(crumb['category'], 'ui');
    expect(crumb['level'], 'warning');
    expect(crumb['data'], {'button': 'send'});
    expect(event['level'], 'warning');
    expect(event['dist'], '42');
    final exception = (event['exception'] as Map)['values'][0] as Map;
    final frame =
        ((exception['stacktrace'] as Map)['frames'] as List).single as Map;
    expect(frame['instruction_addr'], '0x00001234');
    expect(frame['platform'], 'native');
    expect(((event['contexts'] as Map)['apptracer'] as Map)['dart_stack_trace'],
        raw);
    await client.removeCustomKey('ключ');
    await client.setUserId(null);
    await client.recordError('second', StackTrace.empty);
    event = probe.events.last;
    expect(event['tags'] ?? <String, dynamic>{}, isEmpty);
    expect(event['user'], isNull);
    await client.stop();
  });
}
