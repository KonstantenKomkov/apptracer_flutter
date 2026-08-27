import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed facts, so a test asserts on the payload rather than on the browser.
class _FakeFacts extends TracerClientFacts {
  const _FakeFacts();

  @override
  String get deviceId => 'device-1';
  @override
  String get sessionUuid => 'session-1';
  @override
  String get host => 'example.test';
  @override
  int get screenWidth => 1280;
  @override
  int get screenHeight => 720;
  @override
  int get screenOrientationAngle => 0;
  @override
  String get documentVisibilityState => 'visible';
}

TracerEvent _event({
  bool fatal = false,
  String? issueKey,
  Map<String, String> customKeys = const <String, String>{},
}) =>
    TracerEvent(
      exceptionType: 'FormatException',
      message: 'could not parse the response',
      stackTrace: DartStackTrace.parse('#0      main (package:x/x.dart:1:2)'),
      fatal: fatal,
      issueKey: issueKey,
      customKeys: customKeys,
      timestamp: DateTime.utc(2026, 8, 26, 19, 1, 15),
    );

Map<String, Object?> _build(TracerEvent event) => buildBatchItem(
      event: event,
      facts: const _FakeFacts(),
      versionName: '1.0.0',
      versionCode: 10000,
      environment: 'dev',
      sdkVersion: '0.1.0',
    );

void main() {
  group('buildBatchItem', () {
    test('matches the shape captured from the vendor SDK', () {
      final Map<String, Object?> item = _build(_event());

      expect(item['type'], 'NON_FATAL');
      expect(item['format'], 'JS_STACKTRACE');
      expect(item['severity'], 'NON_FATAL');

      final Map<String, Object?> bean =
          item['uploadBean']! as Map<String, Object?>;
      expect(bean['environment'], 'dev');
      expect(bean['deviceId'], 'device-1');
      expect(bean['sessionUuid'], 'session-1');
      expect(bean['versionName'], '1.0.0');
      expect(bean['versionCode'], 10000);

      final Map<String, Object?> properties =
          bean['properties']! as Map<String, Object?>;
      expect(properties['host'], 'example.test');
      expect(properties['screenWidth'], 1280);
      expect(properties['screenHeight'], 720);
      expect(properties['documentVisibilityState'], 'visible');
      expect(properties['tracerSdkVersion'], '0.1.0');
      expect(properties['errorEventType'], 'manual');
      expect(properties['timestamp'], isA<int>());
      expect(properties['date'], startsWith('2026-08-26'));
    });

    test('a fatal event is a CRASH, as the vendor labels one', () {
      final Map<String, Object?> item = _build(_event(fatal: true));

      expect(item['type'], 'CRASH');
      expect(item['severity'], 'CRASH');
      final Map<String, Object?> bean =
          item['uploadBean']! as Map<String, Object?>;
      final Map<String, Object?> properties =
          bean['properties']! as Map<String, Object?>;
      expect(properties['errorEventType'], 'error');
    });

    test('custom keys go out as properties and as tags, both on purpose', () {
      // The console renders `properties` and ignores `tags`; the vendor's own
      // SDK sends `tags`. Measured 2026-08-27 by sending one event each way,
      // so neither half of this is a guess and neither can be dropped.
      final Map<String, Object?> item = _build(
        _event(issueKey: 'ISSUE-1', customKeys: const <String, String>{
          'checkout_step': '3',
        }),
      );

      final Map<String, Object?> bean =
          item['uploadBean']! as Map<String, Object?>;
      final Map<String, Object?> properties =
          bean['properties']! as Map<String, Object?>;
      expect(properties['issueKey'], 'ISSUE-1');
      expect(properties['checkout_step'], '3');
      expect(bean['tags'], <String>['checkout_step=3']);
    });

    test('an event key overrides a global one of the same name', () {
      final Map<String, Object?> item = buildBatchItem(
        event: _event(customKeys: const <String, String>{'screen': 'checkout'}),
        facts: const _FakeFacts(),
        versionName: '1.0.0',
        versionCode: 10000,
        environment: 'prod',
        sdkVersion: '0.1.0',
        customKeys: const <String, String>{'screen': 'home', 'tier': 'gold'},
      );

      final Map<String, Object?> bean =
          item['uploadBean']! as Map<String, Object?>;
      final Map<String, Object?> properties =
          bean['properties']! as Map<String, Object?>;
      expect(
        (bean['tags']! as List<Object?>).toSet(),
        <String>{'screen=checkout', 'tier=gold'},
      );
      expect(properties['screen'], 'checkout');
      expect(properties['tier'], 'gold');
    });

    test('no keys means no tags field at all, as the vendor omits it', () {
      final Map<String, Object?> item = _build(_event());
      final Map<String, Object?> bean =
          item['uploadBean']! as Map<String, Object?>;
      expect(bean.containsKey('tags'), isFalse);
      expect(item.containsKey('logsFile'), isFalse);
    });

    test('the user id is a property, and the log is a top-level field', () {
      final Map<String, Object?> item = buildBatchItem(
        event: _event(),
        facts: const _FakeFacts(),
        versionName: '1.0.0',
        versionCode: 10000,
        environment: 'prod',
        sdkVersion: '0.1.0',
        userId: 'u-42',
        logsFile: 'BASE64',
      );

      final Map<String, Object?> bean =
          item['uploadBean']! as Map<String, Object?>;
      final Map<String, Object?> properties =
          bean['properties']! as Map<String, Object?>;
      expect(properties['userId'], 'u-42');
      expect(item['logsFile'], 'BASE64');
    });

    test('the stack trace reads as type, message, then the verbatim frames',
        () {
      final Map<String, Object?> item = _build(_event());

      expect(
        item['stackTrace'],
        'FormatException: could not parse the response\n'
        '#0      main (package:x/x.dart:1:2)',
      );
    });
  });
}
