import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart' hide TracerClient;
import 'package:apptracer_flutter/src/tracer_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTracerPlatform platform;
  late FakeErrorHandlerBindings bindings;

  setUp(() {
    platform = FakeTracerPlatform();
    bindings = FakeErrorHandlerBindings();
    Tracer.client = TracerClient(platform: platform, bindings: bindings);
  });

  tearDown(() async {
    await Tracer.stopCollection();
  });

  group('Tracer.initialize calls appRunner exactly once', () {
    test('on a normal start', () async {
      var calls = 0;

      await Tracer.initialize(
        options: const TracerOptions(),
        appRunner: () => calls++,
      );

      expect(calls, 1);
      expect(Tracer.isEnabled, isTrue);
    });

    test('when collection is disabled by policy', () async {
      var calls = 0;

      await Tracer.initialize(
        options: const TracerOptions(isCollectionEnabled: false),
        appRunner: () => calls++,
      );

      expect(calls, 1);
      expect(Tracer.isEnabled, isFalse);
      expect(platform.initializeCalls, 0);
    });

    test('when the platform SDK throws while starting', () async {
      Tracer.client = TracerClient(
        platform: FakeTracerPlatform(failOnInitialize: true),
        bindings: bindings,
      );
      var calls = 0;

      await Tracer.initialize(
        options: const TracerOptions(),
        appRunner: () => calls++,
      );

      expect(calls, 1);
      expect(Tracer.isEnabled, isFalse);
    });

    test('when no implementation exists for the platform', () async {
      Tracer.client = TracerClient(
        platform: UnsupportedTracerPlatform(),
        bindings: bindings,
      );
      var calls = 0;

      await Tracer.initialize(
        options: const TracerOptions(),
        appRunner: () => calls++,
      );

      expect(calls, 1);
      expect(Tracer.isEnabled, isFalse);
    });

    for (final mode in TracerNativeInitialization.values) {
      for (final (limits, reason) in const [
        (TracerOptions(maxBreadcrumbs: -1), 'invalid_max_breadcrumbs'),
        (
          TracerOptions(maxRawStackTraceLogBytes: -1),
          'invalid_max_raw_stack_trace_log_bytes',
        ),
        (TracerOptions(maxStackFrames: -1), 'invalid_max_stack_frames'),
      ]) {
        test('$mode with $reason runs appRunner once and rejects startup',
            () async {
          var calls = 0;
          await Tracer.initialize(
            options: limits.copyWith(nativeInitialization: mode),
            appRunner: () => calls++,
          );
          expect(calls, 1);
          expect(Tracer.isEnabled, isFalse);
          expect(platform.startCalls, 0);

          final result = await Tracer.startCollection();
          expect(result.state, TracerCollectionState.error);
          expect(result.reason, reason);
          expect(calls, 1);
          expect(platform.startCalls, 0);
          expect(Tracer.client.hasInstalledHandlers, isFalse);
        });
      }
    }

    test('with the guarded zone switched off', () async {
      var calls = 0;

      await Tracer.initialize(
        options: const TracerOptions(captureZoneErrors: false),
        appRunner: () => calls++,
      );

      expect(calls, 1);
    });

    test('with an asynchronous appRunner', () async {
      var calls = 0;

      await Tracer.initialize(
        options: const TracerOptions(),
        appRunner: () async {
          await Future<void>.delayed(Duration.zero);
          calls++;
        },
      );

      expect(calls, 1);
    });
  });

  group('Tracer.initialize error handling', () {
    test('reports an error thrown by appRunner and surfaces it', () async {
      final failure = StateError('runApp exploded');

      await expectLater(
        Tracer.initialize(
          options: const TracerOptions(attachRawStackTraceAsLog: false),
          appRunner: () => throw failure,
        ),
        throwsA(same(failure)),
      );

      expect(platform.events, hasLength(1));
      expect(platform.events.single.exceptionType, 'StateError');
      expect(
        platform.events.single.fatal,
        isFalse,
        reason: 'an uncaught Dart error does not terminate the process, so it '
            'must not count against the crash-free metric by default',
      );
    });

    test('captures an uncaught asynchronous error from the guarded zone',
        () async {
      await Tracer.initialize(
        options: const TracerOptions(attachRawStackTraceAsLog: false),
        appRunner: () {
          Timer.run(() => throw const FormatException('late async failure'));
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(platform.events, hasLength(1));
      expect(platform.events.single.exceptionType, 'FormatException');
      expect(platform.events.single.message, 'late async failure');
    });

    test('an error after startup does not disturb the returned future',
        () async {
      final future = Tracer.initialize(
        options: const TracerOptions(attachRawStackTraceAsLog: false),
        appRunner: () {
          Timer.run(() => throw StateError('later'));
        },
      );

      await expectLater(future, completes);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(platform.events, hasLength(1));
    });

    test('routes FlutterError.onError through the chain', () async {
      await Tracer.initialize(
        options: const TracerOptions(attachRawStackTraceAsLog: false),
        appRunner: () {},
      );

      bindings.flutterOnError!(
        FlutterErrorDetails(
          exception: ArgumentError('bad widget'),
          stack: StackTrace.current,
          library: 'widgets library',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.events, hasLength(1));
      expect(platform.events.single.library, 'widgets library');
      expect(platform.events.single.fatal, isFalse,
          reason: 'a framework error does not end the process, so marking it '
              'fatal would distort the crash-free metric');
    });

    test('an uncaught async error is not fatal by default', () async {
      await Tracer.initialize(
        options: const TracerOptions(attachRawStackTraceAsLog: false),
        appRunner: () {
          Timer.run(() => throw StateError('nobody caught this'));
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(platform.events.single.severity, TracerSeverity.error);
      expect(platform.events.single.fatal, isFalse);
    });

    test('reportUnhandledErrorsAsFatal promotes a zone error too', () async {
      await Tracer.initialize(
        options: const TracerOptions(
          attachRawStackTraceAsLog: false,
          reportUnhandledErrorsAsFatal: true,
        ),
        appRunner: () {
          Timer.run(() => throw StateError('nobody caught this either'));
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(platform.events.single.severity, TracerSeverity.fatal);
      expect(platform.events.single.fatal, isTrue);
    });

    test('reportUnhandledErrorsAsFatal promotes automatically captured errors',
        () async {
      await Tracer.initialize(
        options: const TracerOptions(
          attachRawStackTraceAsLog: false,
          reportUnhandledErrorsAsFatal: true,
        ),
        appRunner: () {},
      );

      bindings.flutterOnError!(
        FlutterErrorDetails(
          exception: ArgumentError('bad widget'),
          stack: StackTrace.current,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.events.single.severity, TracerSeverity.fatal);
      expect(platform.events.single.fatal, isTrue);
    });
  });

  group('Tracer.initialize without a guarded zone', () {
    test('still reports an appRunner failure', () async {
      final failure = StateError('runApp exploded');

      await expectLater(
        Tracer.initialize(
          options: const TracerOptions(
            captureZoneErrors: false,
            attachRawStackTraceAsLog: false,
          ),
          appRunner: () => throw failure,
        ),
        throwsA(same(failure)),
      );

      expect(platform.events, hasLength(1),
          reason: 'the app failing to start is the one error that must not go '
              'missing');
      expect(platform.events.single.exceptionType, 'StateError');
    });
  });

  for (final breadcrumb in [false, true]) {
    final hook = breadcrumb ? 'beforeBreadcrumb' : 'beforeSend';
    test('$hook keeps its drop policy across reentrant initialization',
        () async {
      late Future<void> restarted;
      Never reinitializeAndThrow() {
        restarted = Tracer.initialize(
          options: const TracerOptions(),
          appRunner: () {},
        );
        throw StateError('private filter failure');
      }

      await Tracer.initialize(
        options: TracerOptions(
          filterErrorPolicy: TracerFilterErrorPolicy.drop,
          beforeSend: (_) => reinitializeAndThrow(),
          beforeBreadcrumb: (_) => reinitializeAndThrow(),
        ),
        appRunner: () {},
      );

      if (breadcrumb) {
        Tracer.log('private breadcrumb');
      } else {
        await Tracer.recordError('private event', StackTrace.current);
      }
      await restarted;

      expect(Tracer.breadcrumbs, isEmpty);
      expect(platform.logs, isEmpty);
      expect(platform.events, isEmpty);
    });
  }

  group('filter error policy for automatic capture', () {
    late List<TracerEvent> filtered;
    setUp(() => filtered = []);

    TracerOptions droppingOptions() => TracerOptions(
          filterErrorPolicy: TracerFilterErrorPolicy.drop,
          beforeSend: (event) {
            filtered.add(event);
            throw StateError('private automatic filter error');
          },
        );

    void expectNoLeakedEvent(String message) {
      expect(filtered.single.message, contains(message));
      expect(filtered.single.stackTrace.raw, isNotEmpty);
      expect(platform.events, isEmpty);
      expect(platform.logs, isEmpty);
      expect(Tracer.isEnabled, isTrue);
    }

    test('drops FlutterError events without writing their raw stacks',
        () async {
      await Tracer.initialize(options: droppingOptions(), appRunner: () {});

      bindings.flutterOnError!(
        FlutterErrorDetails(
          exception: StateError('private FlutterError'),
          stack: StackTrace.current,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expectNoLeakedEvent('private FlutterError');
    });

    test('drops PlatformDispatcher errors without writing their raw stacks',
        () async {
      await Tracer.initialize(options: droppingOptions(), appRunner: () {});

      bindings.platformOnError!(
        StateError('private dispatcher error'),
        StackTrace.current,
      );
      await Future<void>.delayed(Duration.zero);

      expectNoLeakedEvent('private dispatcher error');
    });

    test('drops guarded-zone errors without writing their raw stacks',
        () async {
      await Tracer.initialize(
        options: droppingOptions(),
        appRunner: () {
          Timer.run(() => throw StateError('private zone error'));
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expectNoLeakedEvent('private zone error');
    });
  });

  group('Tracer.stopCollection', () {
    test('stops reporting and allows a clean restart', () async {
      await Tracer.initialize(
        options: const TracerOptions(attachRawStackTraceAsLog: false),
        appRunner: () {},
      );

      await Tracer.stopCollection();
      expect(Tracer.isEnabled, isFalse);
      expect(bindings.flutterOnError, isNull);
      expect(bindings.platformOnError, isNull);

      await Tracer.recordError(StateError('after stop'), StackTrace.current);
      expect(platform.events, isEmpty);

      await Tracer.initialize(
        options: const TracerOptions(attachRawStackTraceAsLog: false),
        appRunner: () {},
      );
      expect(Tracer.isEnabled, isTrue);

      await Tracer.recordError(StateError('after restart'), StackTrace.current);
      expect(platform.events, hasLength(1));
    });
  });
}
