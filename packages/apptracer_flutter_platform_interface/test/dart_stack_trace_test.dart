import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const String _vmTrace = '''
#0      MyHomePage.build.<anonymous closure> (package:example/main.dart:78:7)
#1      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1183:21)
#2      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:275:24)
<asynchronous suspension>
#3      _rootRunUnary (dart:async/zone.dart:1407:13)
''';

// Shape produced by an AOT build with `--obfuscate --split-debug-info`.
const String _obfuscatedTrace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 12345, tid: 12371, name io.flutter.ui
os: android arch: arm64 comp: no sim: no
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
isolate_dso_base: 7938750000, vm_dso_base: 7938750000
isolate_instructions: 79387d1000, vm_instructions: 79387cb000
    #00 abs 0000007938a1c2f0 virt 00000000002cc2f0 _kDartIsolateSnapshotInstructions+0x24b2f0
    #01 abs 0000007938a1b114 virt 00000000002cb114 _kDartIsolateSnapshotInstructions+0x24a114
    #02 abs 0000007938a19008 virt 00000000002c9008
''';

const String _v8Trace = '''
Error
    at Object.wrapException (http://localhost:8080/main.dart.js:4321:17)
    at main_closure.call\$0 (http://localhost:8080/main.dart.js:1234:5)
    at Object._rootRun (http://localhost:8080/main.dart.js:9:11)
''';

const String _mozillaTrace = '''
wrapException@http://localhost:8080/main.dart.js:4321:17
main_closure.call\$0@http://localhost:8080/main.dart.js:1234:5
@http://localhost:8080/main.dart.js:1:1
''';

void main() {
  group('DartStackTrace.parse', () {
    test('keeps the raw text verbatim', () {
      final trace = DartStackTrace.parse(_obfuscatedTrace);
      expect(trace.raw, _obfuscatedTrace);
    });

    test('parses VM frames with member, uri, line and column', () {
      final trace = DartStackTrace.parse(_vmTrace);

      expect(trace.isObfuscated, isFalse);
      expect(trace.frames, hasLength(5));

      final first = trace.frames.first;
      expect(first.index, 0);
      expect(first.member, 'MyHomePage.build.<anonymous closure>');
      expect(first.uri, 'package:example/main.dart');
      expect(first.line, 78);
      expect(first.column, 7);
      expect(first.fileName, 'main.dart');
      expect(first.packageName, 'example');
      expect(first.needsSymbolication, isFalse);
    });

    test('parses dart: SDK uris that contain a colon', () {
      final trace = DartStackTrace.parse(_vmTrace);
      final last = trace.frames.last;

      expect(last.member, '_rootRunUnary');
      expect(last.uri, 'dart:async/zone.dart');
      expect(last.line, 1407);
      expect(last.column, 13);
      expect(last.packageName, isNull);
    });

    test('marks the asynchronous suspension frame', () {
      final trace = DartStackTrace.parse(_vmTrace);
      final async =
          trace.frames.where((f) => f.isAsynchronousSuspension).toList();

      expect(async, hasLength(1));
      expect(async.single.raw.trim(), '<asynchronous suspension>');
    });

    test('parses obfuscated frames and the symbolication header', () {
      final trace = DartStackTrace.parse(_obfuscatedTrace);

      expect(trace.isObfuscated, isTrue);
      expect(trace.buildId, 'b71885097a7ebc4d1ab80642f606c4be');
      expect(trace.os, 'android');
      expect(trace.architecture, 'arm64');
      expect(trace.isolateDsoBase, '7938750000');
      expect(trace.vmDsoBase, '7938750000');
      expect(trace.isolateInstructions, '79387d1000');
      expect(trace.vmInstructions, '79387cb000');

      // Header lines must not be mistaken for frames.
      expect(trace.frames, hasLength(3));

      final first = trace.frames.first;
      expect(first.index, 0);
      expect(first.absoluteAddress, '0000007938a1c2f0');
      expect(first.virtualAddress, '00000000002cc2f0');
      expect(first.symbol, '_kDartIsolateSnapshotInstructions+0x24b2f0');
      expect(first.needsSymbolication, isTrue);
      expect(first.isSymbolic, isFalse);
    });

    test('parses an obfuscated frame without a trailing symbol', () {
      final trace = DartStackTrace.parse(_obfuscatedTrace);
      final last = trace.frames.last;

      expect(last.absoluteAddress, '0000007938a19008');
      expect(last.virtualAddress, '00000000002c9008');
      expect(last.symbol, isNull);
    });

    test('parses V8-style dart2js frames', () {
      final trace = DartStackTrace.parse(_v8Trace);
      final named =
          trace.frames.where((f) => f.member == 'Object.wrapException');

      expect(named, hasLength(1));
      expect(named.single.uri, 'http://localhost:8080/main.dart.js');
      expect(named.single.line, 4321);
      expect(named.single.column, 17);
    });

    test('parses SpiderMonkey-style dart2js frames', () {
      final trace = DartStackTrace.parse(_mozillaTrace);

      expect(trace.frames, hasLength(3));
      expect(trace.frames.first.member, 'wrapException');
      expect(trace.frames.first.uri, 'http://localhost:8080/main.dart.js');
      expect(trace.frames.first.line, 4321);
      expect(trace.frames.last.member, '<anonymous>');
    });

    test('never drops an unrecognised line', () {
      final trace = DartStackTrace.parse('total gibberish\nmore gibberish');

      expect(trace.frames, hasLength(2));
      expect(trace.frames.first.raw, 'total gibberish');
      expect(trace.frames.first.isSymbolic, isFalse);
      expect(trace.frames.first.needsSymbolication, isFalse);
    });

    test('handles null, empty and whitespace input', () {
      expect(DartStackTrace.parse(null).isEmpty, isTrue);
      expect(DartStackTrace.parse('').isEmpty, isTrue);
      expect(DartStackTrace.parse('   \n  ').isEmpty, isTrue);
    });

    test('accepts a real StackTrace object', () {
      late final StackTrace captured;
      try {
        throw StateError('boom');
      } catch (_, stackTrace) {
        captured = stackTrace;
      }

      final trace = DartStackTrace.parse(captured);
      expect(trace.frames, isNotEmpty);
      expect(trace.raw, captured.toString());
    });

    test('round-trips through toMap', () {
      final map = DartStackTrace.parse(_obfuscatedTrace).toMap();

      expect(map['obfuscated'], isTrue);
      expect(map['buildId'], 'b71885097a7ebc4d1ab80642f606c4be');
      expect((map['frames']! as List<Object?>), hasLength(3));
      expect(map['raw'], _obfuscatedTrace);
    });
  });
}
