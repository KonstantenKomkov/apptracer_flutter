import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:web/web.dart' as web;

/// [TracerClientFacts] read from the live browser.
class WindowBrowserFacts extends TracerClientFacts {
  /// Reads what it can, once, at construction.
  WindowBrowserFacts()
      : deviceId = _readOrCreateDeviceId(),
        sessionUuid = randomUuid();

  /// Key the device identifier is stored under.
  ///
  /// Namespaced so it cannot collide with the host application's own storage,
  /// and left readable so anyone auditing what the page keeps can find it.
  static const String deviceIdKey = 'apptracer_flutter.deviceId';

  @override
  final String deviceId;

  @override
  final String sessionUuid;

  @override
  String get host => web.window.location.host;

  @override
  int get screenWidth => web.window.screen.width;

  @override
  int get screenHeight => web.window.screen.height;

  @override
  int get screenOrientationAngle {
    try {
      return web.window.screen.orientation.angle;
    } catch (_) {
      // Not every browser exposes the orientation, and a crash reporter has no
      // business failing over a screen angle.
      return 0;
    }
  }

  @override
  String get documentVisibilityState => web.document.visibilityState;

  /// Returns the stored device identifier, creating one when there is none.
  ///
  /// Storage can throw outright — private windows, blocked site data — so a
  /// failure degrades to an identifier that lives as long as the page.
  static String _readOrCreateDeviceId() {
    try {
      final String? stored = web.window.localStorage.getItem(deviceIdKey);
      if (stored != null && stored.isNotEmpty) {
        return stored;
      }
      final String created = randomUuid();
      web.window.localStorage.setItem(deviceIdKey, created);
      return created;
    } catch (_) {
      return randomUuid();
    }
  }
}
