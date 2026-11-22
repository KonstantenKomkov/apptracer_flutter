import 'models/dart_stack_frame.dart';
import 'models/dart_stack_trace.dart';
import 'models/tracer_breadcrumb.dart';
import 'models/tracer_collection_result.dart';
import 'models/tracer_diagnostic_result.dart';
import 'models/tracer_event.dart';
import 'models/tracer_options.dart';
import 'pigeon/tracer_api.dart';

/// Converts public options to the generated transport model.
NativeOptions nativeOptions(TracerOptions options) => NativeOptions(
      appToken: options.resolvedAppToken,
      dsn: options.dsn,
      environment: options.resolvedEnvironment,
      release: options.release,
      dist: options.dist,
      isCollectionEnabled: options.isCollectionEnabled,
      nativeInitialization: options.nativeInitialization.name,
      preservePreviousReports: options.preservePreviousReports,
      maxBreadcrumbs: options.maxBreadcrumbs,
      attachRawStackTraceAsLog: options.attachRawStackTraceAsLog,
      maxRawStackTraceLogBytes: options.maxRawStackTraceLogBytes,
      maxStackFrames: options.maxStackFrames,
      debug: options.debug,
      apiUrl: options.apiUrl,
      initialCustomKeys: Map<String, String>.of(options.initialCustomKeys),
    );

/// Converts a public event without dropping nullable or diagnostic fields.
NativeEvent nativeEvent(TracerEvent event) => NativeEvent(
      exceptionType: event.exceptionType,
      message: event.message,
      severity: event.severity.wireName,
      fatal: event.fatal,
      timestamp: event.timestamp.toIso8601String(),
      issueKey: event.issueKey,
      library: event.library,
      context: event.context,
      customKeys: Map<String, String>.of(event.customKeys),
      stackTrace: _nativeStack(event.stackTrace),
      breadcrumbs: event.breadcrumbs.map(_nativeBreadcrumb).toList(),
    );

NativeStackTrace _nativeStack(DartStackTrace stack) => NativeStackTrace(
      raw: stack.raw,
      frames: stack.frames.map(_nativeFrame).toList(),
      needsSymbolication: stack.needsSymbolication,
      buildId: stack.buildId,
      os: stack.os,
      architecture: stack.architecture,
      isolateDsoBase: stack.isolateDsoBase,
      vmDsoBase: stack.vmDsoBase,
      isolateInstructions: stack.isolateInstructions,
      vmInstructions: stack.vmInstructions,
    );

NativeStackFrame _nativeFrame(DartStackFrame frame) => NativeStackFrame(
      raw: frame.raw,
      index: frame.index,
      member: frame.member,
      uri: frame.uri,
      line: frame.line,
      column: frame.column,
      absoluteAddress: frame.absoluteAddress,
      virtualAddress: frame.virtualAddress,
      symbol: frame.symbol,
      isAsynchronousSuspension: frame.isAsynchronousSuspension,
    );

NativeBreadcrumb _nativeBreadcrumb(TracerBreadcrumb crumb) => NativeBreadcrumb(
      message: crumb.message,
      category: crumb.category,
      level: crumb.level.wireName,
      timestamp: crumb.timestamp.toIso8601String(),
      data: Map<String, Object?>.of(crumb.data),
    );

/// Decodes a generated lifecycle result with the existing fail-closed rules.
TracerCollectionResult publicCollectionResult(NativeCollectionResult result) =>
    TracerCollectionResult.fromMap(<Object?, Object?>{
      'state': result.state,
      'reason': result.reason,
    });

/// Decodes a generated diagnostic result with the existing fail-closed rules.
TracerDiagnosticResult publicDiagnosticResult(NativeDiagnosticResult result) =>
    TracerDiagnosticResult.fromMap(<Object?, Object?>{
      'state': result.state,
      'reason': result.reason,
    });
