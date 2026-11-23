import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart' show Tracer;
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_platform_interface/delivery_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'official SDK preserves filtered payload and owns no Dart handlers',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final probe = NativeSdkProbe()..install();
      final adapter = SentryDesktopTracer();
      final originalHandler = FlutterError.onError;
      final previousPlatform = TracerPlatform.instance;
      addTearDown(() => TracerPlatform.instance = previousPlatform);
      TracerPlatform.instance = adapter;
      final diagnostics = <TracerDeliveryDiagnostic>[];
      await Tracer.startCollection(
        TracerOptions(
          deliveryListener: diagnostics.add,
          dsn: 'https://public@tracer.invalid/42',
          release: '1.2.3',
          environment: 'test',
          dist: '7',
          captureFlutterErrors: false,
          capturePlatformDispatcherErrors: false,
          captureZoneErrors: false,
          beforeBreadcrumb: (crumb) => crumb.message == 'secret' ? null : crumb,
          beforeSend: (event) => event.message == 'drop'
              ? null
              : event.copyWith(
                  message: 'redacted',
                  customKeys: {},
                  removeBreadcrumbs: true,
                ),
        ),
      );
      expect(Tracer.isEnabled, isTrue);
      // ignore: invalid_use_of_internal_member
      final sdkOptions = Sentry.currentHub.options;
      expect(
        sdkOptions.integrations.map((i) => i.runtimeType.toString()),
        unorderedEquals([
          'WidgetsFlutterBindingIntegration',
          'LoadReleaseIntegration',
          'MacOSLifecycleIntegration',
          'LoadNativeDebugImagesIntegration',
        ]),
      );
      expect(FlutterError.onError, same(originalHandler));
      final init = probe.calls.singleWhere(
        (call) => call.method == 'initNativeSdk',
      );
      final settings = init.arguments as Map<dynamic, dynamic>;
      expect(settings['dsn'], 'https://public@tracer.invalid/42');
      expect(settings['release'], '1.2.3');
      expect(settings['preservePreviousReports'], false);
      await Tracer.setCustomKey(key: 'private-key', value: 'do-not-resurrect');
      await Tracer.setUserId('account-1');
      Tracer.addBreadcrumb(TracerBreadcrumb(message: 'secret'));
      Tracer.addBreadcrumb(TracerBreadcrumb(message: 'visible'));
      const raw =
          '#0      run (package:example/main.dart:10:3)\n'
          '#1      main (package:example/main.dart:20:4)';
      await Tracer.recordError(
        StateError('sensitive'),
        StackTrace.fromString(raw),
        fatal: true,
        issueKey: 'group-1',
      );
      expect(probe.events, hasLength(1));
      final event = probe.events.single;
      expect(event['sdk'], containsPair('name', 'sentry.dart.flutter'));
      expect(event['tags'] ?? <String, dynamic>{}, isEmpty);
      expect(event['breadcrumbs'] ?? <dynamic>[], isEmpty);
      expect(event['user'], containsPair('id', 'account-1'));
      expect(event['level'], 'fatal');
      expect(event['fingerprint'], ['group-1']);
      final exception = (event['exception'] as Map)['values'][0] as Map;
      expect(exception['type'], 'StateError');
      expect(exception['value'], 'redacted');
      final frames = (exception['stacktrace'] as Map)['frames'] as List;
      expect((frames.first as Map)['function'], 'main');
      expect((frames.last as Map)['lineno'], 10);
      expect(
        ((event['contexts'] as Map)['apptracer'] as Map)['dart_stack_trace'],
        raw,
      );
      expect(event.toString(), isNot(contains('do-not-resurrect')));
      expect(event.toString(), isNot(contains('sensitive')));
      await Tracer.recordError('drop', StackTrace.fromString(raw));
      // An unrelated direct Sentry call must not bypass Tracer filtering.
      Sentry.logger.error('unfiltered SDK log');
      Sentry.metrics.count('unfiltered.sdk.metric', 1);
      await Sentry.captureMessage('bypass');
      expect(probe.events, hasLength(1));
      expect(
        probe.calls
            .where((c) => c.method == 'addBreadcrumb')
            .any((c) => c.arguments.toString().contains('secret')),
        isFalse,
      );

      expect(diagnostics, isEmpty);
      probe.onCall = (call) async {
        if (call.method == 'captureEnvelope') {
          throw PlatformException(code: 'private-sdk-error');
        }
        return null;
      };
      await Tracer.recordError('failed capture', StackTrace.current);
      expect(diagnostics.single.backend, 'sentry-sdk');
      expect(diagnostics.single.operation, 'recordError');
      expect(diagnostics.single.reason, 'operation_error');
      expect(diagnostics.single.state, TracerDeliveryState.failed);
      probe.onCall = null;

      // An SDK callback can drop deliberately or fail before the transport.
      // Only the exception belongs to delivery diagnostics.
      final processor = _ProbeProcessor();
      sdkOptions.addEventProcessor(processor);
      await Tracer.recordError('processor drop', StackTrace.current);
      expect(diagnostics, hasLength(1));
      processor.fail = true;
      await Tracer.recordError('processor failure', StackTrace.current);
      expect(diagnostics, hasLength(2));
      expect(diagnostics.last.operation, 'recordError');
      expect(diagnostics.last.reason, 'operation_error');
      sdkOptions.removeEventProcessor(processor);

      final other = SentryDesktopTracer();
      final refused = await other.startCollection(
        const TracerOptions(dsn: 'https://other@another.invalid/2'),
      );
      expect(refused.reason, 'sentry_already_owned');
      await other.stopCollection();
      expect(Sentry.isEnabled, true);
      await Tracer.stopCollection();
      expect(Tracer.isEnabled, false);
      expect(
        (await adapter.getCollectionState()).state,
        TracerCollectionState.restartRequired,
      );
      await Tracer.recordError('after stop', StackTrace.current);
      expect(probe.events, hasLength(2));
      expect(
        (await adapter.stopAndClearCollection()).state,
        TracerCollectionState.restartRequired,
      );
      expect(
        probe.calls.where((c) => c.method == 'clearNativeSdk'),
        hasLength(1),
      );
      expect(
        (await adapter.startCollection(
          const TracerOptions(dsn: 'https://public@tracer.invalid/42'),
        )).state,
        TracerCollectionState.restartRequired,
      );
      // Sentry selects Cocoa envelope transport from the host OS, independently of
      // Flutter's target override. Linux delivery is covered by the release probe.
    },
    skip: !Platform.isMacOS,
  );
}

class _ProbeProcessor implements EventProcessor {
  bool fail = false;

  @override
  Future<SentryEvent?> apply(SentryEvent event, Hint hint) async {
    if (fail) throw StateError('private processor failure');
    return null;
  }
}
