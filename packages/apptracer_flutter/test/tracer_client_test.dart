import 'dart:async';
import 'dart:convert';

import 'package:apptracer_flutter/apptracer_flutter.dart'
    hide EventDeduplicator, TracerClient;
import 'package:apptracer_flutter/src/deduplicator.dart';
import 'package:apptracer_flutter/src/tracer_client.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart'
    show MethodChannelTracer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

class _FailingPlatform extends FakeTracerPlatform {
  bool failEvents = false;
  bool failCleanup = false;
  bool startThrows = false;
  bool startReturnsError = false;
  bool startUnconfirmed = false;
  bool failState = false;
  bool stateReturnsError = false;
  bool resumeUnconfirmed = false;
  bool resumeThrows = false;
  bool pauseReturnsError = false;
  final eventEntered = Completer<void>();
  Completer<void>? eventResult;
  bool failPause = false;
  bool failResume = false;
  bool failStop = false;
  bool cleanupThrows = false;
  bool diagnosticReturnsError = false;

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) async {
    if (startThrows) throw StateError('private start exception');
    if (startUnconfirmed) {
      return const TracerCollectionResult(TracerCollectionState.enabled);
    }
    if (startReturnsError) {
      return const TracerCollectionResult(
        TracerCollectionState.error,
        reason: 'private start result',
      );
    }
    await initialize(options);
    return getCollectionState();
  }

  @override
  Future<TracerCollectionResult> getCollectionState() async {
    if (failState) throw StateError('private state exception');
    if (stateReturnsError) {
      return const TracerCollectionResult(TracerCollectionState.error,
          reason: 'private state');
    }
    return super.getCollectionState();
  }

  @override
  Future<TracerCollectionResult> pauseCollection() async {
    if (failPause) throw StateError('private pause exception');
    if (pauseReturnsError) {
      return const TracerCollectionResult(TracerCollectionState.error,
          reason: 'private pause');
    }
    return super.pauseCollection();
  }

  @override
  Future<TracerCollectionResult> resumeCollection() async {
    if (resumeThrows) throw StateError('private resume');
    if (resumeUnconfirmed) {
      await super.stopCollection();
      return const TracerCollectionResult(TracerCollectionState.enabled);
    }
    if (failResume) {
      return const TracerCollectionResult(
        TracerCollectionState.error,
        reason: 'private resume result',
      );
    }
    return super.resumeCollection();
  }

  @override
  Future<void> stopCollection() async {
    if (failStop) throw StateError('private stop exception');
    await super.stopCollection();
  }

  @override
  Future<TracerDiagnosticResult> runHeapDump({required String tag}) async {
    if (diagnosticReturnsError) {
      return const TracerDiagnosticResult(
        TracerDiagnosticState.error,
        reason: 'private diagnostic result',
      );
    }
    return super.runHeapDump(tag: tag);
  }

  @override
  Future<TracerDiagnosticResult> runDiskUsage() async =>
      throw StateError('private diagnostic');

  @override
  Future<TracerDiagnosticResult> setHeapDumpEnabled(bool enabled) async =>
      const TracerDiagnosticResult(TracerDiagnosticState.error,
          reason: 'private diagnostic result');

  @override
  Future<void> recordError(TracerEvent event) async {
    if (!eventEntered.isCompleted) eventEntered.complete();
    await eventResult?.future;
    if (failEvents) throw StateError('private platform exception');
    await super.recordError(event);
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() async {
    if (cleanupThrows) throw StateError('private cleanup exception');
    if (failCleanup) {
      return const TracerCollectionResult(
        TracerCollectionState.error,
        reason: 'private native result',
      );
    }
    return super.stopAndClearCollection();
  }
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

  group('invalid limits', () {
    for (final entry in <({TracerOptions options, String reason})>[
      (
        options: const TracerOptions(maxBreadcrumbs: -1),
        reason: 'invalid_max_breadcrumbs',
      ),
      (
        options: const TracerOptions(maxRawStackTraceLogBytes: -1),
        reason: 'invalid_max_raw_stack_trace_log_bytes',
      ),
      (
        options: const TracerOptions(maxStackFrames: -1),
        reason: 'invalid_max_stack_frames',
      ),
    ]) {
      test('${entry.reason} rejects start before backend initialization',
          () async {
        final platform = FakeTracerPlatform();
        final client = _client(platform);

        final result = await client.startCollection(entry.options);

        expect(result.state, TracerCollectionState.error);
        expect(result.reason, entry.reason);
        expect(platform.startCalls, 0);
        expect(platform.initializeCalls, 0);
        expect(client.isEnabled, isFalse);
        expect(client.hasInstalledHandlers, isFalse);
      });
    }
  });

  test('zero limits preserve breadcrumb mirroring and the full stack',
      () async {
    final platform = FakeTracerPlatform();
    final client = _client(platform);
    const options = TracerOptions(
      maxBreadcrumbs: 0,
      maxRawStackTraceLogBytes: 0,
      maxStackFrames: 0,
    );
    expect((await client.startCollection(options)).isEnabled, isTrue);
    client.addBreadcrumb(TracerBreadcrumb(message: 'mirrored'));
    final stack = List.generate(
      250,
      (i) => '#$i      deep.frame$i (package:example/deep.dart:$i:1)',
    ).join('\n');
    await client.recordError('test', stack);

    final event = platform.events.single;
    expect(event.breadcrumbs, isEmpty);
    expect(platform.logs.first, contains('mirrored'));
    expect(event.stackTrace.frames, hasLength(250));
    expect(
        platform.logs.last, endsWith(TracerClient.defuseFrameNumbers(stack)));
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
      expect(platform.stopCalls, 1);
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

    test('a throwing hook delivers the original event and raw stack by default',
        () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        TracerOptions(
          beforeSend: (_) => throw StateError('hook is broken'),
        ),
      );

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(platform.events.single.error, isA<StateError>());
      expect(platform.events.single.message, contains('boom'));
      expect(platform.logs.single, contains('boom'));
    });

    test('drop policy blocks the original event and its raw stack', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      var calls = 0;
      await client.start(
        TracerOptions(
          filterErrorPolicy: TracerFilterErrorPolicy.drop,
          beforeSend: (_) {
            calls++;
            throw StateError('private filter failure');
          },
        ),
      );

      await client.recordError(StateError('private event'), StackTrace.current);

      expect(calls, 1);
      expect(platform.events, isEmpty);
      expect(platform.logs, isEmpty);
    });

    test('a failing debug printer cannot change a null filter result',
        () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(TracerOptions(debug: true, beforeSend: (_) => null));
      final previous = debugPrint;
      addTearDown(() => debugPrint = previous);
      var writes = 0;
      debugPrint = (message, {wrapWidth}) {
        if (++writes == 1) throw StateError('debug sink unavailable');
      };

      await client.recordError('private event', StackTrace.current);

      expect(platform.events, isEmpty);
      expect(platform.logs, isEmpty);
    });

    test('debug filter diagnostics do not expose event or callback data',
        () async {
      final previousDebugPrint = debugPrint;
      final messages = <String>[];
      debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
      addTearDown(() => debugPrint = previousDebugPrint);
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        TracerOptions(
          debug: true,
          filterErrorPolicy: TracerFilterErrorPolicy.drop,
          beforeSend: (_) => throw StateError('private event filter error'),
          beforeBreadcrumb: (_) =>
              throw StateError('private breadcrumb filter error'),
        ),
      );

      client.addBreadcrumb(TracerBreadcrumb(message: 'private breadcrumb'));
      await client.recordError(StateError('private event'), StackTrace.current);

      expect(
          messages,
          containsAll(<String>[
            'apptracer_flutter: beforeBreadcrumb threw; '
                'breadcrumb dropped by filter error policy',
            'apptracer_flutter: beforeSend threw; '
                'event dropped by filter error policy',
          ]));
      expect(messages.join('\n'), isNot(contains('private')));
      expect(platform.events, isEmpty);
      expect(platform.logs, isEmpty);
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

    test('a throwing beforeBreadcrumb keeps the original by default', () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      await client.start(
        TracerOptions(
          beforeBreadcrumb: (_) => throw StateError('hook is broken'),
        ),
      );

      client.addBreadcrumb(TracerBreadcrumb(message: 'original'));
      await Future<void>.delayed(Duration.zero);

      expect(client.breadcrumbs.single.message, 'original');
      expect(platform.logs.single, contains('original'));
    });

    test('drop policy blocks the native mirror and preserves earlier entries',
        () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);
      var calls = 0;
      await client.start(
        TracerOptions(
          filterErrorPolicy: TracerFilterErrorPolicy.drop,
          beforeBreadcrumb: (breadcrumb) {
            calls++;
            if (breadcrumb.category == 'secret') {
              throw StateError('private filter failure');
            }
            return breadcrumb;
          },
        ),
      );

      client
        ..addBreadcrumb(TracerBreadcrumb(message: 'safe'))
        ..addBreadcrumb(
          TracerBreadcrumb(message: 'private', category: 'secret'),
        );
      await Future<void>.delayed(Duration.zero);

      expect(calls, 2);
      expect(client.breadcrumbs.map((entry) => entry.message), ['safe']);
      expect(platform.logs, hasLength(1));
      expect(platform.logs.single, contains('safe'));
      expect(platform.logs.single, isNot(contains('private')));
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

  group('delivery diagnostics', () {
    test('platform exceptions have stable metadata and no exception text',
        () async {
      final platform = _FailingPlatform()..failEvents = true;
      final client = _client(platform);
      final diagnostics = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(
        attachRawStackTraceAsLog: false,
        deliveryListener: diagnostics.add,
      ));

      await client.recordError(StateError('private event'), StackTrace.current);

      expect(diagnostics.single.state, TracerDeliveryState.failed);
      expect(diagnostics.single.operation, 'recordError');
      expect(diagnostics.single.reason, 'platform_exception');
      expect(diagnostics.single.backend, 'fake');
    });

    test('listener exceptions do not change delivery', () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      var calls = 0;
      await client.start(TracerOptions(
        attachRawStackTraceAsLog: false,
        deliveryListener: (_) {
          calls++;
          throw StateError('private listener failure');
        },
      ));
      platform.failEvents = true;

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(calls, 1);
      expect(platform.events, isEmpty);
      expect(client.isEnabled, isTrue);
    });

    test('typed lifecycle errors use a fixed reason instead of result text',
        () async {
      final platform = _FailingPlatform()..failCleanup = true;
      final client = _client(platform);
      final diagnostics = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: diagnostics.add));

      final result = await client.stopAndClearCollection();

      expect(result.state, TracerCollectionState.error);
      expect(diagnostics.single.operation, 'stopAndClearCollection');
      expect(diagnostics.single.reason, 'operation_error');
    });

    test('reinitialization replaces the previous session listener', () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      final previous = <TracerDeliveryDiagnostic>[];
      final current = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: previous.add));
      await client.start(TracerOptions(deliveryListener: current.add));
      platform.failEvents = true;

      await client.recordError(StateError('boom'), StackTrace.current);

      expect(previous, isEmpty);
      expect(current.single.operation, 'recordError');
    });

    test(
        'mobile legacy stop reports channel failure once and never calls purge',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test/task34/legacy');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'stopCollection') {
          throw PlatformException(code: 'private stop');
        }
        return {
          'state': call.method == 'startCollection' ? 'enabled' : 'error',
          'reason': 'private state'
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final client = TracerClient(
          platform:
              MethodChannelTracer(channel: channel, backendName: 'ios-native'),
          bindings: FakeErrorHandlerBindings());
      final failures = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: failures.add));
      final Future<void> stopped = client.stop();
      await stopped;
      expect(calls, ['startCollection', 'stopCollection']);
      expect(failures.single.backend, 'ios-native');
      expect(failures.single.operation, 'stopCollection');
      expect(failures.single.reason, 'platform_exception');
    });

    test(
        'legacy stop observes typed status and disabled start uses the requested listener',
        () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      final first = <TracerDeliveryDiagnostic>[];
      final second = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: first.add));
      platform.stateReturnsError = true;
      await client.stop();
      expect(first.single.operation, 'stopCollection');
      expect(first.single.reason, 'operation_error');
      final result = await client.startCollection(TracerOptions(
          isCollectionEnabled: false, deliveryListener: second.add));
      expect(result.state, TracerCollectionState.error);
      expect(second.single.operation, 'stopCollection');
      expect(second.single.reason, 'operation_error');
      expect(first, hasLength(1));
      expect(platform.stopCalls, 2);
    });

    test('invalid opt-out preserves the stop failure and its listener',
        () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      final failures = <TracerDeliveryDiagnostic>[];
      final rejected = <TracerDeliveryDiagnostic>[];
      await client.start(const TracerOptions());
      platform.stateReturnsError = true;
      final stop = client.startCollection(TracerOptions(
        isCollectionEnabled: false,
        maxBreadcrumbs: -1,
        deliveryListener: failures.add,
      ));
      await client.start(TracerOptions(
        maxStackFrames: -1,
        deliveryListener: rejected.add,
      ));

      final result = await stop;
      expect(result.state, TracerCollectionState.error);
      expect(result.reason, 'private state');
      expect(failures.single.operation, 'stopCollection');
      expect(failures.single.reason, 'operation_error');
      expect(rejected, isEmpty);
      expect(
          (await client.startCollection()).reason, 'invalid_max_stack_frames');
      expect(platform.stopCalls, 1);
    });

    test('active start observes state errors and preserves exception semantics',
        () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      final failures = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: failures.add));
      platform.stateReturnsError = true;
      expect(
          (await client.startCollection()).state, TracerCollectionState.error);
      expect(failures.map((event) => event.operation),
          ['getCollectionState', 'startCollection']);
      platform.stateReturnsError = false;
      await client.startCollection();
      platform.failState = true;
      final starts = platform.initializeCalls;
      expect(
          (await client.startCollection()).state, TracerCollectionState.error);
      expect(platform.initializeCalls, starts);
      expect(failures.last.operation, 'getCollectionState');
      expect(failures.last.reason, 'platform_exception');
    });

    test('pause result, resume exception and unconfirmed resume are diagnosed',
        () async {
      final platform = _FailingPlatform()..pauseReturnsError = true;
      final client = _client(platform);
      final failures = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: failures.add));
      expect(
          (await client.pauseCollection()).state, TracerCollectionState.error);
      platform.resumeThrows = true;
      await client.resumeCollection();
      platform
        ..resumeThrows = false
        ..resumeUnconfirmed = true;
      expect((await client.resumeCollection()).reason,
          'enabled_state_not_confirmed');
      expect(failures.map((d) => [d.operation, d.reason]), [
        ['pauseCollection', 'operation_error'],
        ['resumeCollection', 'platform_exception'],
        ['resumeCollection', 'operation_error'],
      ]);
    });

    test('recordError awaits the platform Future and suppresses stale failures',
        () async {
      final platform = _FailingPlatform()..eventResult = Completer<void>();
      final client = _client(platform);
      final previous = <TracerDeliveryDiagnostic>[];
      final current = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: previous.add));
      var completed = false;
      final recording = client
          .recordError('private', StackTrace.current)
          .then((_) => completed = true);
      await platform.eventEntered.future;
      await client
          .startCollection(TracerOptions(deliveryListener: current.add));
      expect(completed, isFalse);
      platform.eventResult!.completeError(StateError('private failure'));
      await recording;
      expect(previous, isEmpty);
      expect(current, isEmpty);
    });

    test('unconfirmed start and both forms of native diagnostic failure',
        () async {
      final platform = _FailingPlatform()..startUnconfirmed = true;
      final client = _client(platform);
      final failures = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: failures.add));
      expect(client.isEnabled, isFalse);
      platform.startUnconfirmed = false;
      await client.startCollection();
      await client.runDiskUsage();
      await client.setHeapDumpEnabled(false);
      expect(failures.map((event) => [event.operation, event.reason]), [
        ['startCollection', 'operation_error'],
        ['runDiskUsage', 'platform_exception'],
        ['setHeapDumpEnabled', 'operation_error'],
      ]);
    });

    test('updating diagnostics on a live start preserves its data filters',
        () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      final first = <TracerDeliveryDiagnostic>[];
      final second = <TracerDeliveryDiagnostic>[];
      await client.start(
          TracerOptions(beforeSend: (_) => null, deliveryListener: first.add));
      await client.startCollection(TracerOptions(deliveryListener: second.add));
      await client.recordError('private event', StackTrace.current);
      expect(platform.events, isEmpty);
      platform.failState = true;
      await client.getCollectionState();
      expect(second.single.operation, 'getCollectionState');
      platform.failState = false;
      await client.startCollection(const TracerOptions());
      platform.failState = true;
      await client.getCollectionState();
      expect(client.options.deliveryListener, isNull);
      expect(second, hasLength(1));
      expect(first, isEmpty);
      expect(platform.initializeCalls, 1);
    });

    test('start reports typed errors and exceptions without their text',
        () async {
      final platform = _FailingPlatform()..startReturnsError = true;
      final client = _client(platform);
      final diagnostics = <TracerDeliveryDiagnostic>[];
      final options = TracerOptions(deliveryListener: diagnostics.add);

      var result = await client.startCollection(options);
      expect(result.state, TracerCollectionState.error);
      platform
        ..startReturnsError = false
        ..startThrows = true;
      result = await client.startCollection(options);

      expect(result.state, TracerCollectionState.error);
      expect(diagnostics.map((event) => event.reason),
          ['operation_error', 'platform_exception']);
      expect(diagnostics.map((event) => event.operation).toSet(),
          {'startCollection'});
    });

    test('state and lifecycle failures are observable with stable operations',
        () async {
      final platform = _FailingPlatform();
      final client = _client(platform);
      final diagnostics = <TracerDeliveryDiagnostic>[];
      await client.start(TracerOptions(deliveryListener: diagnostics.add));

      platform.failState = true;
      await client.getCollectionState();
      platform.diagnosticReturnsError = true;
      await client.runHeapDump(tag: 'test');
      platform.failPause = true;
      await client.pauseCollection();
      platform.failResume = true;
      await client.resumeCollection();
      platform.failStop = true;
      await client.stop();
      platform.cleanupThrows = true;
      await client.stopAndClearCollection();

      expect(diagnostics.map((event) => event.operation), [
        'getCollectionState',
        'runHeapDump',
        'pauseCollection',
        'resumeCollection',
        'stopCollection',
        'stopAndClearCollection',
      ]);
      expect(diagnostics.map((event) => event.reason).toSet(),
          {'platform_exception', 'operation_error'});
    });
  });

  group('custom keys', () {
    test('discard values before start; apply only explicit initial keys',
        () async {
      final platform = FakeTracerPlatform();
      final client = _client(platform);

      await client.setCustomKey(key: 'flavor', value: 'beta');
      expect(platform.keys, isEmpty);
      expect(client.customKeys, isEmpty);

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
