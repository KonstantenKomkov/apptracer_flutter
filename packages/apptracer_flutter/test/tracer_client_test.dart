import 'dart:async';
import 'dart:convert';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

TracerClient _client(
  FakeTracerPlatform platform, {
  FakeErrorHandlerBindings? bindings,
  EventDeduplicator? deduplicator,
}) {
  return TracerClient(
    platform: platform,
    bindings: bindings ?? FakeErrorHandlerBindings(),
    deduplicator: deduplicator,
  );
}

void main() {
  group('TracerClient.start', () {
    test('does not start the platform when collection is disabled', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);

      await client.start(const TracerOptions(isCollectionEnabled: false));

      expect(platform.initializeCalls, 0);
      expect(client.isEnabled, isFalse);
      expect(client.hasInstalledHandlers, isFalse);
    });

    test('survives a platform SDK that throws while starting', () async {
      final platform = FakeTracerPlatform(failOnInitialize: true);
      final client = _client(platform);

      await client.start(const TracerOptions());

      expect(client.isEnabled, isFalse);
      expect(client.hasInstalledHandlers, isFalse,
          reason: 'a failed start must not leave handlers behind');
    });

    test('installs handlers and applies initial custom keys', () async {
      final platform = FakeTracerPlatform();
      final bindings = FakeErrorHandlerBindings();
      final client = _client(platform, bindings: bindings);

      await client.start(
        const TracerOptions(
            initialCustomKeys: <String, String>{'flavor': 'dev'}),
      );

      expect(client.isEnabled, isTrue);
      expect(client.hasInstalledHandlers, isTrue);
      expect(bindings.flutterOnError, isNotNull);
      expect(bindings.platformOnError, isNotNull);
      expect(platform.keys['flavor'], 'dev');
    });

    test('honours captureFlutterErrors and capturePlatformDispatcherErrors',
        () async {
      final platform = FakeTracerPlatform();
      final bindings = FakeErrorHandlerBindings();
      final client = _client(platform, bindings: bindings);

      await client.start(
        const TracerOptions(
          captureFlutterErrors: false,
          capturePlatformDispatcherErrors: false,
        ),
      );

      expect(bindings.flutterOnError, isNull);
      expect(bindings.platformOnError, isNull);
    });
  });

  group('TracerClient.stop', () {
    test('restores handlers so a second start does not stack them', () async {
      void appHandler(FlutterErrorDetails details) {}
      final bindings = FakeErrorHandlerBindings(flutterOnError: appHandler);
      final platform = FakeTracerPlatform();
      final client = _client(platform, bindings: bindings);

      await client.start(const TracerOptions());
      await client.stop();

      expect(bindings.flutterOnError, same(appHandler));
      expect(client.isEnabled, isFalse);
      expect(platform.stopCalls, 1);

      await client.start(const TracerOptions());
      await client.stop();

      expect(bindings.flutterOnError, same(appHandler));
      expect(platform.stopCalls, 2);
    });

    test('is safe before start', () async {
      final platform = FakeTracerPlatform();
      await _client(platform).stop();
      expect(platform.stopCalls, 0);
    });
  });

  group('TracerClient.recordError', () {
    test('does nothing while collection is off', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events, isEmpty);
    });

    test('sends the parsed event with severity and custom keys', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      await client.setCustomKey(key: 'screen', value: 'home');
      await client.recordError(
        const FormatException('bad input'),
        StackTrace.current,
        severity: TracerSeverity.warning,
        issueKey: 'ISSUE-1',
        customKeys: const <String, String>{'retry': '2'},
      );

      expect(platform.events, hasLength(1));
      final event = platform.events.single;
      expect(event.exceptionType, 'FormatException');
      expect(event.message, 'bad input');
      expect(event.severity, TracerSeverity.warning);
      expect(event.issueKey, 'ISSUE-1');
      expect(event.customKeys['screen'], 'home');
      expect(event.customKeys['retry'], '2');
      expect(event.stackTrace.frames, isNotEmpty);
    });

    test('synthesises an issueKey for a backend that needs one', () async {
      // Найдено живьём 26.08.2026: Tracer группирует на Android только по
      // классу и методу верхнего кадра, поэтому StateError и TimeoutException
      // из двух замыканий одного build попадали в одну группу.
      final platform = FakeTracerPlatform(needsIssueKey: true);
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      // Один и тот же кадр, разные типы ошибок — ровно тот случай, который
      // Tracer схлопнул в одну группу.
      final StackTrace stack = StackTrace.current;
      await client.recordError(StateError('boom'), stack);
      await client.recordError(TimeoutException('slow'), stack);

      final List<String?> keys =
          platform.events.map((TracerEvent event) => event.issueKey).toList();
      expect(keys, hasLength(2));
      expect(keys.first, isNotNull);
      expect(
        keys.first!.length,
        lessThanOrEqualTo(SyntheticIssueKey.maxLength),
      );
      expect(keys.first, isNot(keys.last));
    });

    test('leaves the issueKey alone when the caller supplied one', () async {
      final platform = FakeTracerPlatform(needsIssueKey: true);
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      await client.recordError(
        StateError('boom'),
        StackTrace.current,
        issueKey: 'ISSUE-1',
      );

      expect(platform.events.single.issueKey, 'ISSUE-1');
    });

    test('leaves the issueKey alone when beforeSend set one', () async {
      final platform = FakeTracerPlatform(needsIssueKey: true);
      final client = _client(platform);
      await client.start(
        TracerOptions(
          attachRawStackTraceAsLog: false,
          beforeSend: (TracerEvent event) =>
              event.copyWith(issueKey: 'FROM-HOOK'),
        ),
      );

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events.single.issueKey, 'FROM-HOOK');
    });

    test('does not synthesise for a backend that groups on its own', () async {
      // Транспорт по протоколу Sentry несёт и тип, и полный список кадров,
      // так что ключ ему не нужен.
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events.single.issueKey, isNull);
    });

    test('rewrites Dart frame numbers so the console can render the entry',
        () async {
      // Консоль ищет следующий по порядку номер записи и пытается разобрать
      // найденное как «#N timestamp | text». Кадры Dart нумерованы так же,
      // поэтому трейс внутри записи #2 подсовывает парсеру собственный #3.
      const String symbolic = '#0      main (package:example/main.dart:1:2)\n'
          '#1      _rootRun (dart:async/zone.dart:1525:13)\n'
          '<asynchronous suspension>\n';

      final String defused = TracerClient.defuseFrameNumbers(symbolic);

      expect(
          defused,
          '[0]      main (package:example/main.dart:1:2)\n'
          '[1]      _rootRun (dart:async/zone.dart:1525:13)\n'
          '<asynchronous suspension>\n');
      expect(defused, isNot(contains('#')));
    });

    test('rewrites a frame number even when the line is indented', () async {
      expect(TracerClient.defuseFrameNumbers('    #12     foo\n'),
          '    [12]     foo\n');
    });

    test('sends an obfuscated trace byte for byte', () async {
      // Его обязан принять flutter symbolize, а консоль его и так рисует:
      // кадры пронумерованы #00, #01, и парсер их не ловит.
      const String obfuscated = '*** *** ***\n'
          "build_id: 'dbcf9df9345bddd07e98f3eed8cdf4d4'\n"
          '    #00 abs 000000783c89ccc7 virt 00000000002a1cc7 '
          '_kDartIsolateSnapshotInstructions+0x1db387\n';

      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions());

      await client.recordError(
          StateError('boom'), StackTrace.fromString(obfuscated));

      expect(platform.logs.single, contains(obfuscated));
    });

    test('attaches the verbatim stack trace as a log by default', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions());

      final stack = StackTrace.current;
      await client.recordError(StateError('boom'), stack);

      expect(platform.logs, hasLength(1));
      // Номера кадров переписаны в [N], чтобы консоль не приняла их за
      // начало записи, — см. defuseFrameNumbers. Остальное дословно.
      expect(
        platform.logs.single,
        contains(TracerClient.defuseFrameNumbers(stack.toString())),
      );
    });

    test('bounds the verbatim trace so it cannot flush the log buffer',
        () async {
      // Android's log buffer is a circular 64 KiB buffer. An unbounded trace
      // would evict every breadcrumb before it and the report would arrive
      // with a stack trace and no context.
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(maxRawStackTraceLogBytes: 512));

      final huge = List<String>.generate(
        5000,
        (int i) => '#$i      deep.frame$i (package:example/deep.dart:$i:1)',
      ).join('\n');

      await client.recordError(StateError('boom'), huge);

      final log = platform.logs.single;
      expect(utf8.encode(log).length, lessThanOrEqualTo(512));
      expect(log, contains('[0]      deep.frame0'),
          reason: 'the frames nearest the throw must survive');
      expect(log, contains('truncated'));
      expect(log, contains('more line(s)'));
    });

    test('leaves a trace that fits well alone', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions());

      final stack = StackTrace.current;
      await client.recordError(StateError('boom'), stack);

      expect(
        platform.logs.single,
        contains(TracerClient.defuseFrameNumbers(stack.toString())),
      );
      expect(platform.logs.single, isNot(contains('truncated')));
    });

    test('caps the frames forwarded to the platform', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        const TracerOptions(maxStackFrames: 3, attachRawStackTraceAsLog: false),
      );

      final many = List<String>.generate(
        50,
        (int i) => '#$i      deep.frame$i (package:example/deep.dart:$i:1)',
      ).join('\n');

      await client.recordError(StateError('boom'), many);

      final event = platform.events.single;
      expect(event.stackTrace.frames, hasLength(3));
      expect(event.stackTrace.frames.first.member, 'deep.frame0');
      expect(
        event.stackTrace.raw.split('\n'),
        hasLength(50),
        reason: 'the verbatim text stays whole; only the parsed frames are '
            'capped, or an obfuscated trace would stop being decodable',
      );
    });

    test('deduplicates the same error object arriving twice', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      final error = StateError('boom');
      final stack = StackTrace.current;

      await client.recordError(error, stack);
      await client.recordError(error, stack);

      expect(platform.events, hasLength(1));
    });

    test('still reports two separate errors that look alike', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      await client.recordError(StateError('boom'), StackTrace.current);
      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events, hasLength(2));
    });

    test('handles a thrown String, which has no type of its own', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      await client.recordError('plain string failure', StackTrace.current);

      expect(platform.events.single.exceptionType, 'String');
      expect(platform.events.single.message, 'plain string failure');
    });
  });

  group('beforeSend', () {
    test('can drop an event', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(TracerOptions(beforeSend: (_) => null));

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events, isEmpty);
    });

    test('can rewrite an event', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        TracerOptions(
          attachRawStackTraceAsLog: false,
          beforeSend: (TracerEvent event) =>
              event.copyWith(message: '[redacted]'),
        ),
      );

      await client.recordError(
        const FormatException('user@example.com'),
        StackTrace.current,
      );

      expect(platform.events.single.message, '[redacted]');
    });

    test('a throwing hook does not lose the event', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        TracerOptions(
          attachRawStackTraceAsLog: false,
          beforeSend: (_) => throw StateError('hook is broken'),
        ),
      );

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events, hasLength(1));
    });
  });

  group('breadcrumbs', () {
    test('are bounded and mirrored into the platform log buffer', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(maxBreadcrumbs: 2));

      for (var i = 0; i < 4; i++) {
        client.addBreadcrumb(TracerBreadcrumb(message: 'step $i'));
      }
      await Future<void>.delayed(Duration.zero);

      expect(client.breadcrumbs.map((b) => b.message),
          <String>['step 2', 'step 3']);
      expect(platform.logs, hasLength(4),
          reason: 'every breadcrumb reaches the native log as it happens, so a '
              'native crash still carries the trail');
    });

    test('are not mirrored when the backend carries them structurally',
        () async {
      // Duplicating them into the log buffer as well would send every
      // breadcrumb twice on a Sentry-protocol backend.
      final platform = FakeTracerPlatform(mirrorsBreadcrumbs: false);
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      client.addBreadcrumb(TracerBreadcrumb(message: 'step'));
      await Future<void>.delayed(Duration.zero);

      expect(client.breadcrumbs, hasLength(1));
      expect(platform.logs, isEmpty);
    });

    test('beforeBreadcrumb can drop a breadcrumb', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        TracerOptions(
          beforeBreadcrumb: (TracerBreadcrumb b) =>
              b.category == 'secret' ? null : b,
        ),
      );

      client
        ..addBreadcrumb(TracerBreadcrumb(message: 'ok'))
        ..addBreadcrumb(TracerBreadcrumb(message: 'no', category: 'secret'));

      expect(client.breadcrumbs, hasLength(1));
    });

    test('are attached to the next event', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions(attachRawStackTraceAsLog: false));

      client.addBreadcrumb(TracerBreadcrumb(message: 'tapped save'));
      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events.single.breadcrumbs.single.message, 'tapped save');
    });
  });

  group('custom keys', () {
    test('are remembered before start and applied on start', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);

      await client.setCustomKey(key: 'flavor', value: 'beta');
      expect(platform.keys, isEmpty);

      await client.start(
        const TracerOptions(initialCustomKeys: <String, String>{'a': 'b'}),
      );

      expect(platform.keys['a'], 'b');
    });

    test('removeCustomKey clears it locally and on the platform', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions());

      await client.setCustomKey(key: 'k', value: 'v');
      expect(platform.keys['k'], 'v');

      await client.removeCustomKey('k');
      expect(platform.keys.containsKey('k'), isFalse);
      expect(client.customKeys.containsKey('k'), isFalse);
    });

    test('an empty key is ignored', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(const TracerOptions());

      await client.setCustomKey(key: '', value: 'v');

      expect(platform.keys, isEmpty);
    });
  });
}
