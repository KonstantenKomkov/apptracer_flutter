/// iOS implementation of `apptracer_flutter`.
///
/// Bridges Dart errors to the OKTracer iOS SDK, which handles native crashes,
/// hangs and MetricKit reports on its own but never sees anything that happens
/// inside Dart.
library;

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';

/// The iOS [TracerPlatform] implementation.
class AppTracerIos extends MethodChannelTracer {
  /// Creates the iOS implementation.
  AppTracerIos() : super(backendName: 'ios-native');

  /// Registers this class as the implementation for iOS.
  ///
  /// Called by the Flutter plugin registrant; there is no need to call it from
  /// application code.
  static void registerWith() {
    TracerPlatform.instance = AppTracerIos();
  }
}
