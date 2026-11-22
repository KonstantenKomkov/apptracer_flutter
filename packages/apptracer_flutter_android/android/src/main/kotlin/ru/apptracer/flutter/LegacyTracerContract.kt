package ru.apptracer.flutter

import io.flutter.plugin.common.MethodCall

internal fun MethodCall.toNativeOptions() = NativeOptions(
    appToken = argument("appToken"), dsn = argument("dsn"),
    environment = argument<String>("environment").orEmpty(),
    release = argument("release"), dist = argument("dist"),
    isCollectionEnabled = argument<Boolean>("isCollectionEnabled") != false,
    nativeInitialization = argument<String>("nativeInitialization") ?: "automatic",
    preservePreviousReports = argument<Boolean>("preservePreviousReports") == true,
    maxBreadcrumbs = argument<Number>("maxBreadcrumbs")?.toLong() ?: 100,
    attachRawStackTraceAsLog = argument<Boolean>("attachRawStackTraceAsLog") != false,
    maxRawStackTraceLogBytes = argument<Number>("maxRawStackTraceLogBytes")?.toLong() ?: 0,
    maxStackFrames = argument<Number>("maxStackFrames")?.toLong() ?: 0,
    debug = argument<Boolean>("debug") == true, apiUrl = argument("apiUrl"),
    initialCustomKeys = argument<Map<String, String>>("initialCustomKeys").orEmpty(),
)

internal fun Map<String, String>.toCollectionResult() = NativeCollectionResult(
    state = getValue("state"), reason = this["reason"])

internal fun Map<String, String>.toDiagnosticResult() = NativeDiagnosticResult(
    state = getValue("state"), reason = this["reason"])

@Suppress("UNCHECKED_CAST")
internal fun MethodCall.toNativeEvent(): NativeEvent {
    val args = (arguments as? Map<String, Any?>).orEmpty()
    val stack = (args["stackTrace"] as? Map<String, Any?>).orEmpty()
    val frames = (stack["frames"] as? List<Map<String, Any?>>).orEmpty().map { frame ->
        frame.toNativeFrame()
    }
    val breadcrumbs = (args["breadcrumbs"] as? List<Map<String, Any?>>).orEmpty().map { crumb ->
        NativeBreadcrumb(
            message = crumb["message"] as? String ?: "",
            category = crumb["category"] as? String,
            level = crumb["level"] as? String ?: "info",
            timestamp = crumb["timestamp"] as? String ?: "",
            data = crumb["data"] as? Map<String, Any?> ?: emptyMap(),
        )
    }
    return NativeEvent(
        exceptionType = args["exceptionType"] as? String ?: "DartError",
        message = args["message"] as? String ?: "",
        severity = args["severity"] as? String ?: "error",
        fatal = args["fatal"] == true,
        timestamp = args["timestamp"] as? String ?: "",
        issueKey = args["issueKey"] as? String,
        library = args["library"] as? String,
        context = args["context"] as? String,
        customKeys = args["customKeys"] as? Map<String, String> ?: emptyMap(),
        stackTrace = NativeStackTrace(
            raw = stack["raw"] as? String ?: "",
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

internal fun Map<String, Any?>.toNativeFrame() =
    NativeStackFrame(
        raw = (this["raw"] as? String).orEmpty(),
        index = (this["index"] as? Number)?.toLong(),
        member = this["member"] as? String,
        uri = this["uri"] as? String,
        line = (this["line"] as? Number)?.toLong(),
        column = (this["column"] as? Number)?.toLong(),
        absoluteAddress = this["absAddress"] as? String,
        virtualAddress = this["virtAddress"] as? String,
        symbol = this["symbol"] as? String,
        isAsynchronousSuspension = this["asyncSuspension"] == true,
    )
