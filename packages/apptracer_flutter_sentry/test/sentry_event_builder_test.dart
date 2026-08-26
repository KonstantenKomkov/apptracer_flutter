import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_sentry/apptracer_flutter_sentry.dart';
import 'package:flutter_test/flutter_test.dart';

TracerEvent _event({
  TracerSeverity severity = TracerSeverity.error,
  bool fatal = false,
  String? issueKey,
  List<TracerBreadcrumb> breadcrumbs = const <TracerBreadcrumb>[],
  Map<String, String> customKeys = const <String, String>{},
}) =>
    TracerEvent(
      exceptionType: 'FormatException',
      message: 'could not parse the response',
      stackTrace: DartStackTrace.parse(
        '#0      _HomePageState.build (package:example/main.dart:10:3)\n'
        '#1      handleTap (package:flutter/src/material/ink_well.dart:1204:21)',
      ),
      severity: severity,
      fatal: fatal,
      issueKey: issueKey,
      breadcrumbs: breadcrumbs,
      customKeys: customKeys,
      timestamp: DateTime.utc(2026, 8, 26, 21, 0),
    );

Map<String, Object?> _build(TracerEvent event) => buildSentryEvent(
      event: event,
      eventId: '0123456789abcdef0123456789abcdef',
      release: 'my_app@1.2.3',
      environment: 'prod',
    );

void main() {
  group('buildSentryEvent', () {
    test('carries the exception, release and environment', () {
      final Map<String, Object?> body = _build(_event());

      expect(body['event_id'], '0123456789abcdef0123456789abcdef');
      expect(body['platform'], 'other');
      expect(body['level'], 'error');
      expect(body['release'], 'my_app@1.2.3');
      expect(body['environment'], 'prod');

      final Map<String, Object?> exception =
          (body['exception']! as Map<String, Object?>);
      final List<Object?> values = exception['values']! as List<Object?>;
      final Map<String, Object?> first = values.single! as Map<String, Object?>;
      expect(first['type'], 'FormatException');
      expect(first['value'], 'could not parse the response');
    });

    test('orders frames oldest first, as Sentry renders them', () {
      final Map<String, Object?> body = _build(_event());
      final Map<String, Object?> stack = ((body['exception']!
              as Map<String, Object?>)['values']! as List<Object?>)
          .single! as Map<String, Object?>;
      final List<Object?> frames = (stack['stacktrace']!
          as Map<String, Object?>)['frames']! as List<Object?>;

      // Dart prints the throw site first; Sentry wants it last.
      expect((frames.first! as Map<String, Object?>)['function'], 'handleTap');
      expect(
        (frames.last! as Map<String, Object?>)['function'],
        '_HomePageState.build',
      );
    });

    test('marks application frames as in_app and framework ones as not', () {
      final Map<String, Object?> body = _build(_event());
      final Map<String, Object?> stack = ((body['exception']!
              as Map<String, Object?>)['values']! as List<Object?>)
          .single! as Map<String, Object?>;
      final List<Object?> frames = (stack['stacktrace']!
          as Map<String, Object?>)['frames']! as List<Object?>;

      expect((frames.first! as Map<String, Object?>)['in_app'], isFalse);
      expect((frames.last! as Map<String, Object?>)['in_app'], isTrue);
    });

    test('an explicit issueKey becomes the fingerprint', () {
      expect(_build(_event(issueKey: 'ISSUE-1'))['fingerprint'],
          <String>['ISSUE-1']);
      expect(_build(_event())['fingerprint'], isNull);
    });

    test('keeps the verbatim trace, the one thing symbolize needs', () {
      final Map<String, Object?> extra =
          _build(_event())['extra']! as Map<String, Object?>;

      expect(
          extra['dart.stack_trace'], contains('#0      _HomePageState.build'));
    });

    test('maps severity, and a fatal event outranks its severity', () {
      expect(
          _build(_event(severity: TracerSeverity.warning))['level'], 'warning');
      expect(_build(_event(severity: TracerSeverity.notice))['level'], 'info');
      expect(_build(_event(severity: TracerSeverity.debug))['level'], 'debug');
      expect(
        _build(_event(severity: TracerSeverity.warning, fatal: true))['level'],
        'fatal',
      );
    });

    test('carries breadcrumbs and custom keys', () {
      final Map<String, Object?> body = _build(_event(
        breadcrumbs: <TracerBreadcrumb>[
          TracerBreadcrumb(
            message: 'user tapped',
            category: 'ui',
            data: const <String, String>{'screen': 'home'},
            timestamp: DateTime.utc(2026, 8, 26, 20, 59),
          ),
        ],
        customKeys: const <String, String>{'checkout_step': '3'},
      ));

      final List<Object?> crumbs = (body['breadcrumbs']!
          as Map<String, Object?>)['values']! as List<Object?>;
      final Map<String, Object?> crumb = crumbs.single! as Map<String, Object?>;
      expect(crumb['message'], 'user tapped');
      expect(crumb['category'], 'ui');
      expect(crumb['data'], <String, String>{'screen': 'home'});

      expect(body['tags'], <String, String>{'checkout_step': '3'});
    });
  });
}
