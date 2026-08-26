import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// The globals the error-handler chain reads and writes.
///
/// Extracted behind an interface so the chaining and restore rules can be
/// tested without mutating process-wide state.
abstract class ErrorHandlerBindings {
  /// Creates bindings.
  const ErrorHandlerBindings();

  /// Bindings backed by the real `FlutterError` and `PlatformDispatcher`.
  const factory ErrorHandlerBindings.live() = _LiveErrorHandlerBindings;

  /// Current value of `FlutterError.onError`.
  FlutterExceptionHandler? get flutterOnError;
  set flutterOnError(FlutterExceptionHandler? handler);

  /// Current value of `PlatformDispatcher.instance.onError`.
  ErrorCallback? get platformOnError;
  set platformOnError(ErrorCallback? handler);
}

class _LiveErrorHandlerBindings extends ErrorHandlerBindings {
  const _LiveErrorHandlerBindings();

  @override
  FlutterExceptionHandler? get flutterOnError => FlutterError.onError;

  @override
  set flutterOnError(FlutterExceptionHandler? handler) =>
      FlutterError.onError = handler;

  @override
  ErrorCallback? get platformOnError => PlatformDispatcher.instance.onError;

  @override
  set platformOnError(ErrorCallback? handler) =>
      PlatformDispatcher.instance.onError = handler;
}

/// Installs and removes the Flutter and platform-dispatcher error handlers.
///
/// Two rules drive the implementation:
///
/// * **Chain, never replace.** Whatever handler the application had installed
///   keeps running. For `FlutterError.onError` that is normally
///   `FlutterError.presentError`, which is what prints the red error box; an
///   integration that silently drops it would make development miserable.
/// * **Restore only what is still ours.** [restore] puts the previous handler
///   back only when the currently installed handler is the exact closure this
///   chain installed. If something else installed a handler afterwards,
///   restoring would delete that third party's handler and resurrect a stale
///   one, so the chain leaves it alone and reports that it did.
class ErrorHandlerChain {
  /// Creates a chain that forwards to [onFlutterError] and [onPlatformError].
  ErrorHandlerChain({
    required this.onFlutterError,
    required this.onPlatformError,
    ErrorHandlerBindings bindings = const ErrorHandlerBindings.live(),
    this.debug = false,
  }) : _bindings = bindings;

  /// Called for every error seen by `FlutterError.onError`.
  final void Function(FlutterErrorDetails details) onFlutterError;

  /// Called for every error seen by `PlatformDispatcher.instance.onError`.
  final void Function(Object error, StackTrace stackTrace) onPlatformError;

  /// Whether to print diagnostics about unexpected handler churn.
  final bool debug;

  final ErrorHandlerBindings _bindings;

  FlutterExceptionHandler? _previousFlutterOnError;
  ErrorCallback? _previousPlatformOnError;

  FlutterExceptionHandler? _installedFlutterOnError;
  ErrorCallback? _installedPlatformOnError;

  bool _flutterInstalled = false;
  bool _platformInstalled = false;

  /// Whether either handler is currently installed by this chain.
  bool get isInstalled => _flutterInstalled || _platformInstalled;

  /// Installs the requested handlers.
  ///
  /// Calling this twice without an intervening [restore] is a no-op for the
  /// handlers that are already installed, so a repeated `initialize` cannot
  /// grow the chain.
  void install({
    required bool captureFlutterErrors,
    required bool capturePlatformDispatcherErrors,
  }) {
    if (captureFlutterErrors && !_flutterInstalled) {
      final previous = _bindings.flutterOnError;
      _previousFlutterOnError = previous;
      void handler(FlutterErrorDetails details) {
        onFlutterError(details);
        previous?.call(details);
      }

      _installedFlutterOnError = handler;
      _bindings.flutterOnError = handler;
      _flutterInstalled = true;
    }

    if (capturePlatformDispatcherErrors && !_platformInstalled) {
      final previous = _bindings.platformOnError;
      _previousPlatformOnError = previous;
      bool handler(Object error, StackTrace stackTrace) {
        onPlatformError(error, stackTrace);
        // `false` means "not handled", which keeps Flutter's own reporting —
        // normally printing the error — intact. Returning `true` here would
        // make errors vanish from the console the moment the integration is
        // added, which is a change nobody asked for.
        return previous?.call(error, stackTrace) ?? false;
      }

      _installedPlatformOnError = handler;
      _bindings.platformOnError = handler;
      _platformInstalled = true;
    }
  }

  /// Removes the handlers this chain installed and restores the previous ones.
  ///
  /// Returns `true` when every installed handler was restored cleanly.
  bool restore() {
    var clean = true;

    if (_flutterInstalled) {
      if (identical(_bindings.flutterOnError, _installedFlutterOnError)) {
        _bindings.flutterOnError = _previousFlutterOnError;
      } else {
        clean = false;
        _warn('FlutterError.onError');
      }
      _flutterInstalled = false;
      _installedFlutterOnError = null;
      _previousFlutterOnError = null;
    }

    if (_platformInstalled) {
      if (identical(_bindings.platformOnError, _installedPlatformOnError)) {
        _bindings.platformOnError = _previousPlatformOnError;
      } else {
        clean = false;
        _warn('PlatformDispatcher.instance.onError');
      }
      _platformInstalled = false;
      _installedPlatformOnError = null;
      _previousPlatformOnError = null;
    }

    return clean;
  }

  void _warn(String name) {
    if (!debug) {
      return;
    }
    debugPrint(
      'apptracer_flutter: $name was replaced after Tracer installed its '
      'handler, so the previous handler was left in place. Tracer no longer '
      'receives errors from it.',
    );
  }
}
