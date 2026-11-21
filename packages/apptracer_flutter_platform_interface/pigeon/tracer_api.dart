import 'package:pigeon/pigeon.dart';

class NativeOptions {
  NativeOptions({
    this.appToken,
    this.dsn,
    required this.environment,
    this.release,
    this.dist,
    required this.isCollectionEnabled,
    required this.nativeInitialization,
    required this.preservePreviousReports,
    required this.maxBreadcrumbs,
    required this.attachRawStackTraceAsLog,
    required this.maxRawStackTraceLogBytes,
    required this.maxStackFrames,
    required this.debug,
    this.apiUrl,
    required this.initialCustomKeys,
  });

  final String? appToken;
  final String? dsn;
  final String environment;
  final String? release;
  final String? dist;
  final bool isCollectionEnabled;
  final String nativeInitialization;
  final bool preservePreviousReports;
  final int maxBreadcrumbs;
  final bool attachRawStackTraceAsLog;
  final int maxRawStackTraceLogBytes;
  final int maxStackFrames;
  final bool debug;
  final String? apiUrl;
  final Map<String, String> initialCustomKeys;
}

class NativeStackFrame {
  NativeStackFrame({
    required this.raw,
    this.index,
    this.member,
    this.uri,
    this.line,
    this.column,
    this.absoluteAddress,
    this.virtualAddress,
    this.symbol,
    required this.isAsynchronousSuspension,
  });

  final String raw;
  final int? index;
  final String? member;
  final String? uri;
  final int? line;
  final int? column;
  final String? absoluteAddress;
  final String? virtualAddress;
  final String? symbol;
  final bool isAsynchronousSuspension;
}

class NativeStackTrace {
  NativeStackTrace({
    required this.raw,
    required this.frames,
    required this.needsSymbolication,
    this.buildId,
    this.os,
    this.architecture,
    this.isolateDsoBase,
    this.vmDsoBase,
    this.isolateInstructions,
    this.vmInstructions,
  });

  final String raw;
  final List<NativeStackFrame> frames;
  final bool needsSymbolication;
  final String? buildId;
  final String? os;
  final String? architecture;
  final String? isolateDsoBase;
  final String? vmDsoBase;
  final String? isolateInstructions;
  final String? vmInstructions;
}

class NativeBreadcrumb {
  NativeBreadcrumb({
    required this.message,
    this.category,
    required this.level,
    required this.timestamp,
    required this.data,
  });

  final String message;
  final String? category;
  final String level;
  final String timestamp;
  final Map<String, Object?> data;
}

class NativeEvent {
  NativeEvent({
    required this.exceptionType,
    required this.message,
    required this.severity,
    required this.fatal,
    required this.timestamp,
    this.issueKey,
    this.library,
    this.context,
    required this.customKeys,
    required this.stackTrace,
    required this.breadcrumbs,
  });

  final String exceptionType;
  final String message;
  final String severity;
  final bool fatal;
  final String timestamp;
  final String? issueKey;
  final String? library;
  final String? context;
  final Map<String, String> customKeys;
  final NativeStackTrace stackTrace;
  final List<NativeBreadcrumb> breadcrumbs;
}

class NativeCollectionResult {
  NativeCollectionResult({required this.state, this.reason});
  final String state;
  final String? reason;
}

class NativeDiagnosticResult {
  NativeDiagnosticResult({required this.state, this.reason});
  final String state;
  final String? reason;
}

@HostApi()
abstract class TracerNativeApi {
  bool initialize(NativeOptions options);
  NativeCollectionResult startCollection(NativeOptions options);
  NativeCollectionResult pauseCollection();
  NativeCollectionResult resumeCollection();
  @async
  NativeCollectionResult stopAndClearCollection();
  NativeCollectionResult getCollectionState();
  void stopCollection();
  void recordError(NativeEvent event);
  void recordLog(String message);
  void setCustomKey(String key, String value);
  void removeCustomKey(String key);
  void setUserId(String? userId);
  @async
  NativeDiagnosticResult runHeapDump(String tag);
  @async
  NativeDiagnosticResult runDiskUsage();
  @async
  NativeDiagnosticResult setHeapDumpEnabled(bool enabled);
}
