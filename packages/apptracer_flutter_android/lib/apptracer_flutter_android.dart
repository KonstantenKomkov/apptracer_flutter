/// Android implementation of `apptracer_flutter`.
///
/// Bridges Dart errors to the `ru.ok.tracer` Android SDK, which handles native
/// crashes, ANRs and the crash-free metric on its own but never sees anything
/// that happens inside Dart.
library;

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';

/// The Android [TracerPlatform] implementation.
class AppTracerAndroid extends MethodChannelTracer {
  /// Creates the Android implementation.
  AppTracerAndroid() : super(backendName: 'android-native');

  /// Registers this class as the implementation for Android.
  ///
  /// Called by the Flutter plugin registrant; there is no need to call it
  /// from application code.
  static void registerWith() {
    TracerPlatform.instance = AppTracerAndroid();
  }
}
