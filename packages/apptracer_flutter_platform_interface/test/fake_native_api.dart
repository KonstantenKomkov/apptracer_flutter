// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';

class FakeNativeApi implements TracerNativeApi {
  @override
  final BinaryMessenger? pigeonVar_binaryMessenger = null;
  @override
  final String pigeonVar_messageChannelSuffix = '';

  final List<String> calls = <String>[];
  final Map<String, List<Object?>> arguments = <String, List<Object?>>{};
  bool initializeResult = true;
  Object? initializeError;
  Object? operationError;
  Completer<bool>? initializeCompleter;
  Completer<NativeCollectionResult>? resumeCompleter;
  Object? collectionError;
  Object? diagnosticError;
  NativeCollectionResult Function(String method) collectionHandler = (method) =>
      NativeCollectionResult(
          state: method == 'pauseCollection' ? 'disabled' : 'enabled');
  NativeDiagnosticResult Function(String method) diagnosticHandler =
      (method) => NativeDiagnosticResult(state: 'invoked');

  void record(String method, [List<Object?> args = const <Object?>[]]) {
    calls.add(method);
    arguments[method] = args;
  }

  @override
  Future<bool> initialize(NativeOptions options) async {
    record('initialize', <Object?>[options]);
    if (initializeCompleter != null) return initializeCompleter!.future;
    if (initializeError != null) throw initializeError!;
    return initializeResult;
  }

  @override
  Future<NativeCollectionResult> startCollection(NativeOptions options) async {
    record('startCollection', <Object?>[options]);
    return collectionHandler('startCollection');
  }

  @override
  Future<NativeCollectionResult> pauseCollection() async {
    record('pauseCollection');
    return collectionHandler('pauseCollection');
  }

  @override
  Future<NativeCollectionResult> resumeCollection() async {
    record('resumeCollection');
    if (resumeCompleter != null) return resumeCompleter!.future;
    return collectionHandler('resumeCollection');
  }

  @override
  Future<NativeCollectionResult> stopAndClearCollection() async {
    record('stopAndClearCollection');
    if (collectionError != null) throw collectionError!;
    return collectionHandler('stopAndClearCollection');
  }

  @override
  Future<NativeCollectionResult> getCollectionState() async {
    record('getCollectionState');
    return collectionHandler('getCollectionState');
  }

  @override
  Future<void> stopCollection() async {
    record('stopCollection');
  }

  @override
  Future<void> recordError(NativeEvent event) async {
    record('recordError', <Object?>[event]);
    if (operationError != null) throw operationError!;
  }

  @override
  Future<void> recordLog(String message) async {
    record('recordLog', <Object?>[message]);
    if (operationError != null) throw operationError!;
  }

  @override
  Future<void> setCustomKey(String key, String value) async {
    record('setCustomKey', <Object?>[key, value]);
  }

  @override
  Future<void> removeCustomKey(String key) async {
    record('removeCustomKey', <Object?>[key]);
  }

  @override
  Future<void> setUserId(String? userId) async {
    record('setUserId', <Object?>[userId]);
  }

  @override
  Future<NativeDiagnosticResult> runHeapDump(String tag) async {
    record('runHeapDump', <Object?>[tag]);
    if (diagnosticError != null) throw diagnosticError!;
    return diagnosticHandler('runHeapDump');
  }

  @override
  Future<NativeDiagnosticResult> runDiskUsage() async {
    record('runDiskUsage');
    if (diagnosticError != null) throw diagnosticError!;
    return diagnosticHandler('runDiskUsage');
  }

  @override
  Future<NativeDiagnosticResult> setHeapDumpEnabled(bool enabled) async {
    record('setHeapDumpEnabled', <Object?>[enabled]);
    if (diagnosticError != null) throw diagnosticError!;
    return diagnosticHandler('setHeapDumpEnabled');
  }
}

final platformError = PlatformException(code: 'boom');
final missingPlugin = MissingPluginException();
