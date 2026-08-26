import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

FlutterErrorDetails _details(Object error) =>
    FlutterErrorDetails(exception: error, stack: StackTrace.current);

void main() {
  group('ErrorHandlerChain', () {
    test('keeps the previously installed FlutterError handler in the chain',
        () {
      final seenByApp = <Object>[];
      final seenByTracer = <Object>[];
      final bindings = FakeErrorHandlerBindings(
        flutterOnError: (FlutterErrorDetails d) => seenByApp.add(d.exception),
      );

      ErrorHandlerChain(
        onFlutterError: (FlutterErrorDetails d) =>
            seenByTracer.add(d.exception),
        onPlatformError: (_, __) {},
        bindings: bindings,
      ).install(
        captureFlutterErrors: true,
        capturePlatformDispatcherErrors: false,
      );

      final error = StateError('boom');
      bindings.flutterOnError!(_details(error));

      expect(seenByTracer, <Object>[error]);
      expect(seenByApp, <Object>[error],
          reason: "the application's own handler must keep running");
    });

    test('keeps the previous PlatformDispatcher handler and its return value',
        () {
      var appHandlerCalls = 0;
      final bindings = FakeErrorHandlerBindings(
        platformOnError: (Object error, StackTrace stack) {
          appHandlerCalls++;
          return true;
        },
      );

      ErrorHandlerChain(
        onFlutterError: (_) {},
        onPlatformError: (_, __) {},
        bindings: bindings,
      ).install(
        captureFlutterErrors: false,
        capturePlatformDispatcherErrors: true,
      );

      final handled =
          bindings.platformOnError!(StateError('x'), StackTrace.current);

      expect(appHandlerCalls, 1);
      expect(handled, isTrue,
          reason: 'the previous handler decided the result');
    });

    test('reports "not handled" when there was no previous handler', () {
      final bindings = FakeErrorHandlerBindings();

      ErrorHandlerChain(
        onFlutterError: (_) {},
        onPlatformError: (_, __) {},
        bindings: bindings,
      ).install(
        captureFlutterErrors: false,
        capturePlatformDispatcherErrors: true,
      );

      // `false` keeps Flutter's own reporting alive, so adding Tracer does not
      // silently stop errors appearing in the console.
      expect(
        bindings.platformOnError!(StateError('x'), StackTrace.current),
        isFalse,
      );
    });

    test('installing twice does not grow the chain', () {
      var appHandlerCalls = 0;
      var tracerCalls = 0;
      final bindings = FakeErrorHandlerBindings(
        flutterOnError: (_) => appHandlerCalls++,
      );

      final chain = ErrorHandlerChain(
        onFlutterError: (_) => tracerCalls++,
        onPlatformError: (_, __) {},
        bindings: bindings,
      );
      chain.install(
        captureFlutterErrors: true,
        capturePlatformDispatcherErrors: false,
      );
      chain.install(
        captureFlutterErrors: true,
        capturePlatformDispatcherErrors: false,
      );

      bindings.flutterOnError!(_details(StateError('boom')));

      expect(tracerCalls, 1);
      expect(appHandlerCalls, 1);
    });

    test('restore puts the original handlers back', () {
      void appHandler(FlutterErrorDetails details) {}
      bool appPlatformHandler(Object error, StackTrace stack) => true;

      final bindings = FakeErrorHandlerBindings(
        flutterOnError: appHandler,
        platformOnError: appPlatformHandler,
      );

      final chain = ErrorHandlerChain(
        onFlutterError: (_) {},
        onPlatformError: (_, __) {},
        bindings: bindings,
      )..install(
          captureFlutterErrors: true,
          capturePlatformDispatcherErrors: true,
        );

      expect(bindings.flutterOnError, isNot(same(appHandler)));

      expect(chain.restore(), isTrue);
      expect(bindings.flutterOnError, same(appHandler));
      expect(bindings.platformOnError, same(appPlatformHandler));
      expect(chain.isInstalled, isFalse);
    });

    test('restore leaves a third-party handler installed after us alone', () {
      void appHandler(FlutterErrorDetails details) {}
      void thirdPartyHandler(FlutterErrorDetails details) {}

      final bindings = FakeErrorHandlerBindings(flutterOnError: appHandler);
      final chain = ErrorHandlerChain(
        onFlutterError: (_) {},
        onPlatformError: (_, __) {},
        bindings: bindings,
      )..install(
          captureFlutterErrors: true,
          capturePlatformDispatcherErrors: false,
        );

      // Something else takes over after Tracer installed its handler.
      bindings.flutterOnError = thirdPartyHandler;

      expect(chain.restore(), isFalse,
          reason: 'restore reports that it could not run cleanly');
      expect(bindings.flutterOnError, same(thirdPartyHandler),
          reason: 'deleting a third-party handler would be worse than leaking');
    });

    test('restore is safe when nothing was installed', () {
      final bindings = FakeErrorHandlerBindings();
      final chain = ErrorHandlerChain(
        onFlutterError: (_) {},
        onPlatformError: (_, __) {},
        bindings: bindings,
      );

      expect(chain.restore(), isTrue);
      expect(bindings.flutterOnError, isNull);
    });
  });
}
