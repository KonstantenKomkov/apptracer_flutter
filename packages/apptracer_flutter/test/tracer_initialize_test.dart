import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
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
