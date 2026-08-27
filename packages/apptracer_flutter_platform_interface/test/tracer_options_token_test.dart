import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TracerOptions.resolvedAppToken', () {
    // The tests run on the Dart VM, so kIsWeb is false and the platform is
    // whatever debugDefaultTargetPlatformOverride says.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('a single token covers an application that ships on one platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const TracerOptions options = TracerOptions(appToken: 'one');

      expect(options.resolvedAppToken, 'one');
    });

    test('the iOS token wins on iOS, and does not leak elsewhere', () {
      const TracerOptions options = TracerOptions(
        appToken: 'fallback',
        iosAppToken: 'ios',
        webAppToken: 'web',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(options.resolvedAppToken, 'ios');

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(options.resolvedAppToken, 'fallback');
    });

    test('a platform with no token of its own falls back', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const TracerOptions options =
          TracerOptions(appToken: 'fallback', webAppToken: 'web');

      expect(options.resolvedAppToken, 'fallback');
    });

    test('nothing set resolves to nothing', () {
      expect(const TracerOptions().resolvedAppToken, isNull);
    });

    test('only the resolved token crosses the channel', () {
      // The native side has no use for the other projects' tokens, and sending
      // them would put credentials of unrelated projects on the wire.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final Map<String, Object?> map = const TracerOptions(
        appToken: 'fallback',
        iosAppToken: 'ios',
        webAppToken: 'web',
      ).toMap();

      expect(map['appToken'], 'ios');
      expect(map.containsKey('iosAppToken'), isFalse);
      expect(map.containsKey('webAppToken'), isFalse);
    });

    test('copyWith carries the per-platform tokens', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const TracerOptions options = TracerOptions(iosAppToken: 'ios');

      expect(options.copyWith(release: '1.0.0').resolvedAppToken, 'ios');
    });
  });
}
