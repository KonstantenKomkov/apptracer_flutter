import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_platform_interface/delivery_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void _deliveryListener(TracerDeliveryDiagnostic diagnostic) {}

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

    test('filter error policy is const-compatible and preserved by copyWith',
        () {
      const options = TracerOptions(
        filterErrorPolicy: TracerFilterErrorPolicy.drop,
      );

      expect(const TracerOptions().filterErrorPolicy,
          TracerFilterErrorPolicy.sendOriginal);
      expect(options.copyWith(release: '1.0.0').filterErrorPolicy,
          TracerFilterErrorPolicy.drop);
      expect(
          options
              .copyWith(filterErrorPolicy: TracerFilterErrorPolicy.sendOriginal)
              .filterErrorPolicy,
          TracerFilterErrorPolicy.sendOriginal);
      expect(options.toMap().containsKey('filterErrorPolicy'), isFalse);
    });

    test('delivery listener and diagnostic metadata preserve compatibility',
        () {
      const options = TracerOptions(deliveryListener: _deliveryListener);

      expect(options.copyWith(release: '1.0.0').deliveryListener,
          same(_deliveryListener));
      expect(options.toMap().containsKey('deliveryListener'), isFalse);
      const diagnostic = TracerDeliveryDiagnostic(
        TracerDeliveryState.sent,
        reason: 'http_200',
      );
      expect(diagnostic.backend, 'tracer-http');
      expect(diagnostic.operation, 'delivery');
      expect(diagnostic.attempt, 0);
    });
  });
}
