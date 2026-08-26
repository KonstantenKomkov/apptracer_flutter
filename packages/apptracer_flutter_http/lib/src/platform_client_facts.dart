import 'dart:io';

import 'tracer_client_facts.dart';

/// [TracerClientFacts] for a target that is not a browser: desktop and
/// Aurora OS.
///
/// The fields Tracer expects were shaped for the web, and there is no way to
/// know what it does with them off it. Rather than invent values, this fills
/// each with the nearest honest equivalent and leaves the screen fields at
/// zero, which reads as "not applicable" rather than as a lie.
class PlatformClientFacts extends TracerClientFacts {
  /// Creates facts for the current process.
  ///
  /// [deviceId] should be persisted by the application if a stable
  /// per-installation identity matters; without one a fresh identifier is
  /// generated per run, and Tracer will count every run as a new device.
  PlatformClientFacts({String? deviceId})
      : deviceId = deviceId ?? randomUuid(),
        sessionUuid = randomUuid();

  @override
  final String deviceId;

  @override
  final String sessionUuid;

  @override
  String get host => Platform.operatingSystem;

  @override
  int get screenWidth => 0;

  @override
  int get screenHeight => 0;

  @override
  int get screenOrientationAngle => 0;

  @override
  String get documentVisibilityState => 'visible';
}
