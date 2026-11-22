import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = TracerNativeApi.pigeonChannelCodec;

  test('Pigeon codec round-trips all event fields including Unicode and AOT',
      () {
    final event = NativeEvent(
      exceptionType: 'StateError',
      message: 'Ошибка 😀',
      severity: 'warning',
      fatal: false,
      timestamp: '2026-11-21T00:00:00.000Z',
      issueKey: 'issue-1',
      library: 'flutter',
      context: 'context',
      customKeys: const {'endpoint': '/orders', 'unicode': 'значение'},
      stackTrace: NativeStackTrace(
        raw: "build_id: 'abcdef'\n#00 abs 00001234 virt 00005678",
        needsSymbolication: true,
        buildId: 'abcdef',
        os: 'android',
        architecture: 'arm64',
        isolateDsoBase: '1000',
        vmDsoBase: '2000',
        isolateInstructions: '3000',
        vmInstructions: '4000',
        frames: <NativeStackFrame>[
          NativeStackFrame(
            raw: '#00 abs 00001234 virt 00005678',
            index: 0,
            absoluteAddress: '00001234',
            virtualAddress: '00005678',
            symbol: '_kDartIsolateSnapshotInstructions+0x1234',
            isAsynchronousSuspension: false,
          ),
        ],
      ),
      breadcrumbs: <NativeBreadcrumb>[
        NativeBreadcrumb(
          message: 'Хлебная крошка',
          category: 'test',
          level: 'info',
          timestamp: '2026-11-21T00:00:00.000Z',
          data: const {'answer': 42, 'nullable': null},
        ),
      ],
    );

    final bytes = codec.encodeMessage(<Object?>[event])!.buffer.asUint8List();
    final fixture = File('test/fixtures/pigeon_event_v1.base64');
    expect(bytes, base64Decode(fixture.readAsStringSync().trim()));
    final reply = codec.decodeMessage(codec.encodeMessage(<Object?>[event]))!
        as List<Object?>;
    final decoded = reply.single! as NativeEvent;
    expect(decoded.message, event.message);
    expect(decoded.customKeys, event.customKeys);
    expect(decoded.stackTrace.frames.single.encode(),
        event.stackTrace.frames.single.encode());
    expect(
        decoded.breadcrumbs.single.encode(), event.breadcrumbs.single.encode());
    expect(decoded.stackTrace.frames.single.absoluteAddress, '00001234');
    expect(decoded.breadcrumbs.single.data['answer'], 42);
  });

  test('Pigeon codec supports empty frames, nullable userId and initial keys',
      () {
    final options = NativeOptions(
      appToken: null,
      environment: 'prod',
      isCollectionEnabled: true,
      nativeInitialization: 'deferred',
      preservePreviousReports: false,
      maxBreadcrumbs: 100,
      attachRawStackTraceAsLog: true,
      maxRawStackTraceLogBytes: 0,
      maxStackFrames: 0,
      debug: false,
      initialCustomKeys: const {'tenant': 'global'},
    );
    final decodedOptions = NativeOptions.decode(options.encode());
    expect(decodedOptions.encode(), options.encode());

    final empty =
        NativeStackTrace(raw: '', frames: const [], needsSymbolication: false);
    final decodedEmpty = NativeStackTrace.decode(empty.encode());
    expect(decodedEmpty.frames, isEmpty);

    final userId = codec.decodeMessage(codec.encodeMessage(<Object?>[null]));
    expect(userId, [null]);
  });

  test('all lifecycle and diagnostic states survive typed results', () {
    for (final state in [
      'enabled',
      'disabled',
      'restartRequired',
      'unsupported',
      'error'
    ]) {
      final result =
          NativeCollectionResult(state: state, reason: 'reason-$state');
      expect(NativeCollectionResult.decode(result.encode()).encode(),
          result.encode());
    }
    for (final state in ['invoked', 'disabled', 'unsupported', 'error']) {
      final result =
          NativeDiagnosticResult(state: state, reason: 'reason-$state');
      expect(NativeDiagnosticResult.decode(result.encode()).encode(),
          result.encode());
    }
  });
}
