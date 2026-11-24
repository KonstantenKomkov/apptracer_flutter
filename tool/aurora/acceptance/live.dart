import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:never-inline')
void manualFailure() => throw StateError('Aurora 2.0.0 matrix manual');

@pragma('vm:never-inline')
void frameworkFailure() => throw FlutterError('Aurora 2.0.0 matrix framework');

@pragma('vm:never-inline')
void asyncFailure() => throw ArgumentError('Aurora 2.0.0 matrix async');

Future<void> exerciseLive(String token, String dsn) async {
  var sent = 0;
  var dropped = 0;
  var frameworkCallbacks = 0;
  var dispatcherCallbacks = 0;
  FlutterError.onError = (_) => frameworkCallbacks++;
  PlatformDispatcher.instance.onError = (_, _) {
    dispatcherCallbacks++;
    return true;
  };
  final a = TracerOptions(
    appToken: token,
    dsn: dsn,
    release: 'aurora@2.0.0',
    dist: '204',
    environment: 'aurora-release-matrix',
    auroraAccountScope: 'matrix-A',
    captureZoneErrors: false,
    nativeInitialization: TracerNativeInitialization.deferred,
    beforeSend: (event) {
      if (event.message.contains('drop-fixture')) {
        dropped++;
        return null;
      }
      return event.copyWith(
        issueKey: event.issueKey ?? 'aurora-matrix-${event.exceptionType}',
      );
    },
    deliveryListener: (event) {
      if (event.operation == 'recordError' &&
          event.state == TracerDeliveryState.sent)
        sent++;
    },
  );
  Future<void> manual(String key) async {
    try {
      manualFailure();
    } catch (error, stack) {
      await Tracer.recordError(error, stack, issueKey: key);
      await Tracer.recordError(error, stack, issueKey: key);
    }
  }

  Future<void> waitForCount(int target) async {
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (sent < target && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (sent != target) throw StateError('unexpected_delivery_count');
  }

  await Tracer.initialize(options: a, appRunner: () {});
  if (!(await Tracer.startCollection(a)).isEnabled)
    throw StateError('matrix_start_failed');
  await Tracer.setUserId('aurora-matrix-A');
  await Tracer.setCustomKey(key: 'matrix_account', value: 'A');
  Tracer.log('Контекст Аврора A', category: 'приёмка');
  await Tracer.recordError(StateError('drop-fixture'), StackTrace.current);
  await manual('aurora-matrix-same');
  await manual('aurora-matrix-same');
  await manual('aurora-matrix-different');
  try {
    frameworkFailure();
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'matrix'),
    );
  }
  await waitForCount(4);
  scheduleMicrotask(asyncFailure);
  await waitForCount(5);
  if ((await Tracer.stopAndClearCollection()).state !=
      TracerCollectionState.disabled) {
    throw StateError('matrix_withdraw_failed');
  }
  await manual('aurora-matrix-disabled');
  if (!(await Tracer.startCollection(
    a.copyWith(auroraAccountScope: 'matrix-B'),
  )).isEnabled) {
    throw StateError('matrix_restart_failed');
  }
  await Tracer.setUserId('aurora-matrix-B');
  await Tracer.setCustomKey(key: 'matrix_account', value: 'B');
  Tracer.log('Контекст Аврора B', category: 'приёмка');
  await manual('aurora-matrix-same');
  await waitForCount(6);
  if (dropped != 1 || frameworkCallbacks != 1 || dispatcherCallbacks != 1) {
    throw StateError('matrix_handler_count');
  }
  await Tracer.stopAndClearCollection();
}
