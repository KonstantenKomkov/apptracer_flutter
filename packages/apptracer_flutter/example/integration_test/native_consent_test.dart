// Android device-channel lifecycle check. Files/network/fatal recovery require
// the separate acceptance steps in docs/native-collection-consent.md.
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_example/consent_main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _expectSdk =
    bool.fromEnvironment('TRACER_EXPECT_SDK', defaultValue: true);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('deferred native start and purge use one bootstrap',
      (tester) async {
    var runners = 0;
    const options = TracerOptions(
      nativeInitialization: TracerNativeInitialization.deferred,
      // The test binding already owns its zone. Normal consent_main uses the
      // default guarded bootstrap, which creates the binding inside its zone.
      captureZoneErrors: false,
    );
    await Tracer.initialize(
      options: options,
      appRunner: () {
        runners++;
        runApp(const ConsentVerificationApp());
      },
    );
    await tester.pumpAndSettle();
    expect(runners, 1);
    expect(Tracer.isEnabled, isFalse);
    final cold = await Tracer.getCollectionState();
    expect(
        cold.state,
        _expectSdk
            ? TracerCollectionState.disabled
            : TracerCollectionState.unsupported);
    if (!_expectSdk) expect(cold.reason, 'sdk_missing');

    Tracer.log('off-before-start');
    await Tracer.setUserId('off-user');
    await Tracer.setCustomKey(key: 'off-key', value: 'discard');
    await Tracer.recordLog('off-log');
    await Tracer.recordError(StateError('off-error'), StackTrace.current);
    expect(Tracer.breadcrumbs, isEmpty);
    expect(Tracer.client.customKeys, isEmpty);

    // Cleanup must reach native even before a successful Dart start.
    final before = await Tracer.stopAndClearCollection();
    expect(
        before.state,
        _expectSdk
            ? TracerCollectionState.disabled
            : TracerCollectionState.unsupported);
    final started = await Tracer.startCollection(options);
    expect(
        started.state,
        _expectSdk
            ? TracerCollectionState.enabled
            : TracerCollectionState.unsupported);
    expect(Tracer.isEnabled, _expectSdk);
    expect(runners, 1);
    if (_expectSdk) {
      await Tracer.setUserId('consent-integration-A');
      await Tracer.setCustomKey(key: 'consent_case', value: 'device_lifecycle');
      Tracer.log('allowed device lifecycle breadcrumb');
      await Tracer.recordError(
          StateError('Consent device lifecycle probe'), StackTrace.current);
      expect(Tracer.breadcrumbs, isNotEmpty);
    }

    final stopping = Tracer.stopAndClearCollection();
    expect(Tracer.isEnabled, isFalse); // Before the native reply.
    expect(Tracer.breadcrumbs, isEmpty);
    expect(Tracer.client.customKeys, isEmpty);
    final stopped = await stopping;
    expect(
        stopped.state,
        _expectSdk
            ? TracerCollectionState.restartRequired
            : TracerCollectionState.unsupported);
    await Tracer.recordLog('off-after-stop');
    await Tracer.setUserId('consent-integration-B-off');
    await Tracer.setCustomKey(key: 'old-key', value: 'must-not-queue');
    Tracer.log('off-after-stop');
    expect(Tracer.breadcrumbs, isEmpty);
    expect(Tracer.client.customKeys, isEmpty);
    final restarted = await Tracer.startCollection(options);
    expect(
        restarted.state,
        _expectSdk
            ? TracerCollectionState.restartRequired
            : TracerCollectionState.unsupported);
    expect(Tracer.isEnabled, isFalse);
    expect(runners, 1);
  }, skip: kIsWeb || defaultTargetPlatform != TargetPlatform.android);

  testWidgets('iOS deferred start, revocation and process restart requirement',
      (tester) async {
    const token = String.fromEnvironment('TRACER_IOS_APP_TOKEN');
    expect(token, isNotEmpty);
    const options = TracerOptions(
      nativeInitialization: TracerNativeInitialization.deferred,
      captureZoneErrors: false,
      iosAppToken: token,
    );
    var runners = 0;
    await Tracer.initialize(
      options: options,
      appRunner: () {
        runners++;
        runApp(const ConsentVerificationApp());
      },
    );
    await tester.pumpAndSettle();
    expect(runners, 1);
    expect(Tracer.isEnabled, isFalse);
    expect((await Tracer.getCollectionState()).state,
        TracerCollectionState.disabled);
    final coldStop = await Tracer.stopAndClearCollection();
    expect(coldStop.state, TracerCollectionState.disabled);
    final started = await Tracer.startCollection(options);
    expect(started.state, TracerCollectionState.enabled);
    expect(Tracer.isEnabled, isTrue);
    final stopping = Tracer.stopAndClearCollection();
    expect(Tracer.isEnabled, isFalse);
    expect((await stopping).state, TracerCollectionState.restartRequired);
    expect((await Tracer.stopAndClearCollection()).state,
        TracerCollectionState.restartRequired);
    await Future<void>.delayed(const Duration(seconds: 5));
    await Tracer.setUserId('ios-deferred-off');
    await Tracer.setCustomKey(key: 'off-key', value: 'discard');
    Tracer.log('ios-off-breadcrumb');
    await Tracer.recordLog('ios-off-log');
    await Tracer.recordError(StateError('ios-off-error'), StackTrace.current);
    expect(Tracer.breadcrumbs, isEmpty);
    expect(Tracer.client.customKeys, isEmpty);
    final restarted = await Tracer.startCollection(options);
    expect(restarted.state, TracerCollectionState.restartRequired);
    expect(Tracer.isEnabled, isFalse);
    expect(runners, 1);
  }, skip: kIsWeb || defaultTargetPlatform != TargetPlatform.iOS);
}
