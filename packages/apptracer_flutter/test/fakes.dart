import 'dart:ui' show ErrorCallback;

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/foundation.dart';

/// A [TracerPlatform] that records what it was asked to do.
class FakeTracerPlatform extends TracerPlatform {
  FakeTracerPlatform({
    this.failOnInitialize = false,
    this.startsSuccessfully = true,
    this.mirrorsBreadcrumbs = true,
    this.needsIssueKey = false,
  });

  /// Stands in for a backend whose own grouping cannot tell two Dart errors
  /// apart, which is both native SDKs.
  final bool needsIssueKey;

  @override
  bool get needsSyntheticIssueKey => needsIssueKey;

  /// Stands in for a backend that carries breadcrumbs as structured data.
  final bool mirrorsBreadcrumbs;

  @override
  bool get mirrorsBreadcrumbsToLog => mirrorsBreadcrumbs;

  /// Makes [initialize] throw, simulating an SDK that blows up while starting.
  final bool failOnInitialize;

  /// Makes [initialize] complete without enabling collection.
  final bool startsSuccessfully;

  final List<TracerEvent> events = <TracerEvent>[];
  final List<String> logs = <String>[];
  final Map<String, String> keys = <String, String>{};
  final List<String?> userIds = <String?>[];

  int initializeCalls = 0;
  int stopCalls = 0;
  bool _enabled = false;

  @override
  bool get isEnabled => _enabled;

  @override
  String get backendName => 'fake';

  @override
  Future<void> initialize(TracerOptions options) async {
    initializeCalls++;
    if (failOnInitialize) {
      throw StateError('platform SDK refused to start');
    }
    _enabled = options.isCollectionEnabled && startsSuccessfully;
  }

  @override
  Future<void> stopCollection() async {
    stopCalls++;
    _enabled = false;
  }

  @override
  Future<void> recordError(TracerEvent event) async => events.add(event);

  @override
  Future<void> recordLog(String message) async => logs.add(message);

  @override
  Future<void> setCustomKey({
    required String key,
    required String value,
  }) async =>
      keys[key] = value;

  @override
  Future<void> removeCustomKey(String key) async => keys.remove(key);

  @override
  Future<void> setUserId(String? userId) async => userIds.add(userId);
}

/// In-memory stand-ins for `FlutterError.onError` and
/// `PlatformDispatcher.instance.onError`, so handler chaining can be tested
/// without touching process-wide state.
class FakeErrorHandlerBindings extends ErrorHandlerBindings {
  FakeErrorHandlerBindings({
    FlutterExceptionHandler? flutterOnError,
    ErrorCallback? platformOnError,
  })  : _flutterOnError = flutterOnError,
        _platformOnError = platformOnError;

  FlutterExceptionHandler? _flutterOnError;
  ErrorCallback? _platformOnError;

  @override
  FlutterExceptionHandler? get flutterOnError => _flutterOnError;

  @override
  set flutterOnError(FlutterExceptionHandler? handler) =>
      _flutterOnError = handler;

  @override
  ErrorCallback? get platformOnError => _platformOnError;

  @override
  set platformOnError(ErrorCallback? handler) => _platformOnError = handler;
}
