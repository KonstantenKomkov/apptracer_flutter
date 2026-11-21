package ru.apptracer.flutter

import io.flutter.plugin.common.MethodCall

internal fun NativeOptions.toMethodCall(method: String): MethodCall = MethodCall(method, mapOf(
    "appToken" to appToken,
    "dsn" to dsn,
    "environment" to environment,
    "release" to release,
    "dist" to dist,
    "isCollectionEnabled" to isCollectionEnabled,
    "nativeInitialization" to nativeInitialization,
    "preservePreviousReports" to preservePreviousReports,
    "maxBreadcrumbs" to maxBreadcrumbs,
    "attachRawStackTraceAsLog" to attachRawStackTraceAsLog,
    "maxRawStackTraceLogBytes" to maxRawStackTraceLogBytes,
    "maxStackFrames" to maxStackFrames,
    "debug" to debug,
    "apiUrl" to apiUrl,
    "initialCustomKeys" to initialCustomKeys,
))

internal fun Map<String, String>.toCollectionResult() = NativeCollectionResult(
    state = getValue("state"), reason = this["reason"])

internal fun Map<String, String>.toDiagnosticResult() = NativeDiagnosticResult(
    state = getValue("state"), reason = this["reason"])

@Suppress("UNCHECKED_CAST")
internal fun NativeStackFrame.toLegacyMap(): Map<String, Any?> = mapOf(
    "raw" to raw,
    "index" to index,
    "member" to member,
    "uri" to uri,
    "line" to line,
    "column" to column,
    "absAddress" to absoluteAddress,
    "virtAddress" to virtualAddress,
    "symbol" to symbol,
    "asyncSuspension" to isAsynchronousSuspension,
)

internal fun MethodCall.toNativeEvent(): NativeEvent {
    val args = arguments as Map<String, Any?>
    val stack = args["stackTrace"] as Map<String, Any?>
    val frames = (stack["frames"] as? List<Map<String, Any?>>).orEmpty().map { frame ->
        NativeStackFrame(
            raw = frame["raw"] as String,
            index = (frame["index"] as? Number)?.toLong(),
            member = frame["member"] as? String,
            uri = frame["uri"] as? String,
            line = (frame["line"] as? Number)?.toLong(),
            column = (frame["column"] as? Number)?.toLong(),
            absoluteAddress = frame["absAddress"] as? String,
            virtualAddress = frame["virtAddress"] as? String,
            symbol = frame["symbol"] as? String,
            isAsynchronousSuspension = frame["asyncSuspension"] == true,
        )
    }
    val breadcrumbs = (args["breadcrumbs"] as? List<Map<String, Any?>>).orEmpty().map { crumb ->
        NativeBreadcrumb(
            message = crumb["message"] as String,
            category = crumb["category"] as? String,
            level = crumb["level"] as String,
            timestamp = crumb["timestamp"] as String,
            data = crumb["data"] as? Map<String, Any?> ?: emptyMap(),
        )
    }
    return NativeEvent(
        exceptionType = args["exceptionType"] as String,
        message = args["message"] as String,
        severity = args["severity"] as String,
        fatal = args["fatal"] == true,
        timestamp = args["timestamp"] as String,
        issueKey = args["issueKey"] as? String,
        library = args["library"] as? String,
        context = args["context"] as? String,
        customKeys = args["customKeys"] as? Map<String, String> ?: emptyMap(),
        stackTrace = NativeStackTrace(
            raw = stack["raw"] as String,
            frames = frames,
            needsSymbolication = stack["needsSymbolication"] == true,
            buildId = stack["buildId"] as? String,
            os = stack["os"] as? String,
            architecture = stack["arch"] as? String,
            isolateDsoBase = stack["isolateDsoBase"] as? String,
            vmDsoBase = stack["vmDsoBase"] as? String,
            isolateInstructions = stack["isolateInstructions"] as? String,
            vmInstructions = stack["vmInstructions"] as? String,
        ),
        breadcrumbs = breadcrumbs,
    )
}
