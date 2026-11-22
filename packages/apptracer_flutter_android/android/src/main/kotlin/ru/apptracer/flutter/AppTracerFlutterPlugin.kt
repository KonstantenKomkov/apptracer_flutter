package ru.apptracer.flutter

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import ru.ok.tracer.Severity
import ru.ok.tracer.Tracer
import ru.ok.tracer.crash.report.TracerCrashReport

/**
 * Android half of `apptracer_flutter`.
 *
 * Forwards Dart errors, logs and custom keys to the `ru.ok.tracer` SDK. Native
 * crashes, ANRs and the crash-free metric are handled by that SDK directly and
 * are none of this plugin's business.
 *
 * The Tracer SDK is a `compileOnly` dependency here: the host application adds
 * it together with the `ru.ok.tracer` Gradle plugin, which is also what
 * supplies `appToken`. Every entry point therefore has to survive the SDK being
 * absent, and does so by reporting "disabled" rather than throwing.
 */
class AppTracerFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, TracerNativeApi {

    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var debug = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        TracerNativeApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        TracerNativeApi.setUp(binding.binaryMessenger, null)
        applicationContext = null
    }

    override fun initialize(options: NativeOptions): Boolean = try {
        initializeRuntime(options)
    } catch (error: Throwable) {
        nativeFailure()
        false
    }

    override fun startCollection(options: NativeOptions): NativeCollectionResult = try {
        startCollectionState(options).toCollectionResult()
    } catch (error: Throwable) {
        nativeFailure()
        collectionState().toCollectionResult()
    }

    override fun pauseCollection(): NativeCollectionResult = try {
        pauseCollectionState().toCollectionResult()
    } catch (error: Throwable) {
        nativeFailure()
        collectionState().toCollectionResult()
    }

    override fun resumeCollection(): NativeCollectionResult = try {
        resumeCollectionState().toCollectionResult()
    } catch (error: Throwable) {
        nativeFailure()
        collectionState().toCollectionResult()
    }

    override fun stopAndClearCollection(callback: (Result<NativeCollectionResult>) -> Unit) {
        try {
            clearCollection { callback(Result.success(it.toCollectionResult())) }
        } catch (error: Throwable) {
            nativeFailure()
            callback(Result.success(NativeCollectionResult("error", "native_call_failed")))
        }
    }

    override fun getCollectionState(): NativeCollectionResult = try {
        collectionState().toCollectionResult()
    } catch (error: Throwable) {
        nativeFailure()
        NativeCollectionResult("error", "native_call_failed")
    }

    override fun stopCollection(callback: (Result<Unit>) -> Unit) {
        try {
            stopCollectionRuntime { callback(Result.success(Unit)) }
        } catch (error: Throwable) {
            nativeFailure()
            callback(Result.failure(error))
        }
    }

    override fun recordError(event: NativeEvent) {
        try {
            recordNativeEvent(event)
        } catch (error: Throwable) {
            nativeFailure()
        }
    }

    override fun recordLog(message: String) {
        try {
            recordLogMessage(message)
        } catch (error: Throwable) {
            nativeFailure()
        }
    }

    override fun setCustomKey(key: String, value: String) {
        try {
            setPersistentCustomKey(key, value)
        } catch (error: Throwable) {
            nativeFailure()
        }
    }

    override fun removeCustomKey(key: String) {
        try {
            setPersistentCustomKey(key, null)
        } catch (error: Throwable) {
            nativeFailure()
        }
    }

    override fun setUserId(userId: String?) {
        try {
            setNativeUserId(userId)
        } catch (error: Throwable) {
            nativeFailure()
        }
    }

    override fun runHeapDump(tag: String, callback: (Result<NativeDiagnosticResult>) -> Unit) =
        runDiagnostic(true, tag, callback)

    override fun runDiskUsage(callback: (Result<NativeDiagnosticResult>) -> Unit) =
        runDiagnostic(false, null, callback)

    override fun setHeapDumpEnabled(enabled: Boolean): NativeDiagnosticResult = try {
        if (!isSdkOnClasspath()) {
            NativeDiagnosticResult("unsupported", "sdk_missing")
        } else if (!AppTracerFlutterPlugin.enabled && enabled) {
            NativeDiagnosticResult("disabled", "collection_disabled")
        } else {
            TracerDiagnostics.setHeapEnabled(enabled).toDiagnosticResult()
        }
    } catch (error: Throwable) {
        NativeDiagnosticResult("error", "native_diagnostic_failed")
    }

    private fun runDiagnostic(
        heap: Boolean,
        tag: String?,
        callback: (Result<NativeDiagnosticResult>) -> Unit,
    ) {
        if (!enabled) {
            callback(Result.success(NativeDiagnosticResult("disabled", "collection_disabled")))
            return
        }
        try {
            TracerDiagnostics.run(heap, tag) { callback(Result.success(it.toDiagnosticResult())) }
        } catch (error: Throwable) {
            callback(Result.success(NativeDiagnosticResult("error", "native_diagnostic_failed")))
        }
    }

    private fun nativeFailure() {
        enabled = false
        lifecycleError = "native_call_failed"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> result.success(initializeRuntime(call.toNativeOptions()))
                "startCollection" -> result.success(startCollectionState(call.toNativeOptions()))
                "pauseCollection" -> result.success(pauseCollectionState())
                "resumeCollection" -> result.success(resumeCollectionState())
                "runHeapDump", "runDiskUsage" -> {
                    if (!enabled) result.success(mapOf("state" to "disabled", "reason" to "collection_disabled"))
                    else TracerDiagnostics.run(call.method == "runHeapDump", call.argument<String>("tag")) { result.success(it) }
                }
                "setHeapDumpEnabled" -> {
                    val requested = call.argument<Boolean>("enabled") == true
                    if (!isSdkOnClasspath()) result.success(mapOf("state" to "unsupported", "reason" to "sdk_missing"))
                    else if (!enabled && requested) result.success(mapOf("state" to "disabled", "reason" to "collection_disabled"))
                    else result.success(TracerDiagnostics.setHeapEnabled(requested))
                }
                "stopAndClearCollection" -> clearCollection { result.success(it) }
                "getCollectionState" -> result.success(collectionState())
                "stopCollection" -> stopCollectionRuntime { result.success(null) }
                "recordError" -> {
                    recordError(call)
                    result.success(null)
                }
                "recordLog" -> {
                    recordLogMessage(call.argument<String>("message"))
                    result.success(null)
                }
                "setCustomKey" -> {
                    setPersistentCustomKey(call.argument<String>("key"), call.argument<String>("value"))
                    result.success(null)
                }
                "removeCustomKey" -> {
                    setPersistentCustomKey(call.argument<String>("key"), null)
                    result.success(null)
                }
                "setUserId" -> {
                    setNativeUserId(call.argument<String>("userId"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            // Includes NoClassDefFoundError when the Tracer SDK is not on the
            // runtime classpath. A crash reporter must not be the thing that
            // crashes the application.
            enabled = false
            logDebug("call ${call.method} failed: $error")
            lifecycleError = "native_call_failed"
            if (call.method in listOf("runHeapDump", "runDiskUsage", "setHeapDumpEnabled")) {
                result.success(mapOf("state" to "error", "reason" to "native_diagnostic_failed"))
            } else if (call.method in listOf("startCollection", "stopAndClearCollection", "getCollectionState", "pauseCollection", "resumeCollection")) {
                result.success(collectionState())
            } else {
                result.success(null)
            }
        }
    }

    private fun startCollectionState(options: NativeOptions): Map<String, String> {
        if (!options.isCollectionEnabled) {
            return mapOf("state" to "disabled")
        }
        if (options.nativeInitialization == "deferred") {
            // The mode is checked before any SDK reference. Dart alone cannot
            // undo a provider that has already run.
            if (!hasDeferredManifest()) {
                return mapOf("state" to "error", "reason" to "deferred_manifest_required")
            }
            if (!isSdkOnClasspath()) return mapOf("state" to "unsupported", "reason" to "sdk_missing")
            if (!hasGradlePluginResources()) return mapOf("state" to "error", "reason" to "app_token_missing")
            val context = applicationContext ?: return mapOf("state" to "error", "reason" to "context_missing")
            val state = Sdk140ConsentRuntime.start(context, options.preservePreviousReports)
            enabled = state["state"] == "enabled"
            if (enabled) runtimePaused = false
            return state
        }
        if (stopped) return collectionState()
        initializeRuntime(options, resumeRuntime = true)
        return collectionState()
    }

    private fun pauseCollectionState(): Map<String, String> {
        if (!isSdkOnClasspath() || stopped || lifecycleError != null) return collectionState()
        val current = Sdk140ConsentRuntime.pauseRuntime()
        runtimePaused = current["reason"] == "sdk_runtime_disabled" && (enabled || runtimePaused)
        enabled = false
        return current
    }

    private fun resumeCollectionState(): Map<String, String> {
        if (!runtimePaused || stopped || lifecycleError != null) {
            return mapOf("state" to "disabled", "reason" to "no_live_pause")
        }
        val current = Sdk140ConsentRuntime.resumeRuntime()
        enabled = current["state"] == "enabled"
        if (enabled) runtimePaused = false
        return current
    }

    private fun collectionState(): Map<String, String> {
        if (isSdkOnClasspath() && Sdk140ConsentRuntime.ownsRuntime()) {
            return Sdk140ConsentRuntime.snapshot()
        }
        lifecycleError?.let { return mapOf("state" to "error", "reason" to it) }
        if (!isSdkOnClasspath()) return mapOf("state" to "unsupported", "reason" to "sdk_missing")
        if (applicationContext?.let { Sdk140ConsentRuntime.buildDisabled(it) } == true) {
            return mapOf("state" to "disabled", "reason" to "sdk_build_disabled")
        }
        if (stopped) return mapOf("state" to "restartRequired", "reason" to "collection_stopped")
        return Sdk140ConsentRuntime.automaticSnapshot()
    }

    private fun hasDeferredManifest(): Boolean {
        val context = applicationContext ?: return false
        val info = context.packageManager.getPackageInfo(
            context.packageName, android.content.pm.PackageManager.GET_PROVIDERS
        )
        val forbidden = setOf(
            "ru.ok.tracer.startup.InitializationProvider",
            "ru.apptracer.flutter.TracerAutoConfigProvider"
        )
        return info.providers.orEmpty().none { it.name in forbidden }
    }

    private fun clearCollection(complete: (Map<String, String>) -> Unit) {
        if (isSdkOnClasspath()) TracerDiagnostics.revoke()
        runtimePaused = false
        enabled = false
        AndroidEventScope.clearPersistentProperties()
        if (!isSdkOnClasspath()) {
            complete(mapOf("state" to "unsupported", "reason" to "sdk_missing"))
            return
        }
        val context = applicationContext
        if (context == null) {
            complete(mapOf("state" to "error", "reason" to "context_missing"))
            return
        }
        Sdk140ConsentRuntime.stopAndClear(context) { state -> complete(state) }
    }

    private fun initializeRuntime(options: NativeOptions, resumeRuntime: Boolean = false): Boolean {
        debug = options.debug
        if (stopped || lifecycleError != null) return false
        if (!options.isCollectionEnabled ||
            options.nativeInitialization == "deferred") return false

        if (options.appToken != null) {
            Log.w(
                TAG,
                "TracerOptions.appToken is ignored on Android. The token comes " +
                    "from the ru.ok.tracer Gradle plugin, which writes it into " +
                    "the tracer_app_token string resource at build time."
            )
        }

        if (options.environment.isNotEmpty()) {
            Log.w(
                TAG,
                "TracerOptions.environment is ignored on Android. The SDK takes " +
                    "it from the Gradle plugin, which defaults it to the build " +
                    "variant name; set `environment` in the tracer { } block, or " +
                    "override it with CoreTracerConfiguration.setOverrideEnvironment " +
                    "in an Application implementing HasTracerConfiguration."
            )
        }

        if (!isSdkOnClasspath()) {
            Log.w(
                TAG,
                "ru.ok.tracer:tracer-crash-report is missing from the runtime " +
                    "classpath, so Dart errors will not be delivered. Add it to " +
                    "your app module as described in the apptracer_flutter README."
            )
            enabled = false
            return false
        }

        if (!hasGradlePluginResources()) {
            lifecycleError = "app_token_missing"
            Log.w(
                TAG,
                "The tracer_app_token resource is missing. Apply the " +
                    "id(\"ru.ok.tracer\") Gradle plugin and make sure " +
                    "android.buildFeatures.resValues stays enabled (AGP 9 " +
                    "disables it by default)."
            )
            enabled = false
            return false
        }

        if (Sdk140ConsentRuntime.ownsRuntime()) {
            // An automatic call cannot bypass a managed deferred lifecycle.
            enabled = Sdk140ConsentRuntime.snapshot()["state"] == "enabled"
            return enabled
        }
        if (applicationContext?.let { Sdk140ConsentRuntime.buildDisabled(it) } == true) {
            enabled = false
            return false
        }
        val state = if (resumeRuntime) Sdk140ConsentRuntime.resumeRuntime()
            else Sdk140ConsentRuntime.automaticSnapshot()
        if (state["state"] == "error") lifecycleError = state["reason"]
        enabled = state["state"] == "enabled"
        return enabled
    }

    /** Full managed cleanup is awaited; only pause/resume retains a session. */
    private fun stopCollectionRuntime(complete: () -> Unit) {
        if (isSdkOnClasspath()) TracerDiagnostics.revoke()
        runtimePaused = false
        enabled = false
        AndroidEventScope.clearPersistentProperties()
        if (isSdkOnClasspath() && Sdk140ConsentRuntime.ownsRuntime()) {
            val context = applicationContext
            if (context != null) {
                Sdk140ConsentRuntime.stopAndClear(context) { complete() }
                return
            }
        }
        stopped = true
        if (isSdkOnClasspath()) Tracer.disable()
        complete()
    }

    private fun recordError(call: MethodCall) {
        recordNativeEvent(call.toNativeEvent())
    }

    private fun recordNativeEvent(event: NativeEvent) {
        if (!enabled || Tracer.isDisabled) {
            return
        }

        val exceptionType = event.exceptionType
        val message = event.message
        val severity = severityOf(event.severity)
        val stack = event.stackTrace
        val title = if (message.isEmpty()) exceptionType else "$exceptionType: $message"
        val throwable = DartError(title)
        throwable.stackTrace = DartError.toStackTrace(stack.frames)

        val eventProperties = mutableMapOf<String, String?>()
        eventProperties.putAll(event.customKeys)
        eventProperties[KEY_DART_EXCEPTION_TYPE] = exceptionType
        if (stack.needsSymbolication) {
            eventProperties[KEY_DART_NEEDS_SYMBOLICATION] = "true"
            eventProperties[KEY_DART_BUILD_ID] = stack.buildId
        } else {
            eventProperties[KEY_DART_NEEDS_SYMBOLICATION] = null
            eventProperties[KEY_DART_BUILD_ID] = null
        }

        AndroidEventScope.withEventProperties(eventProperties) {
            TracerCrashReport.report(severity, throwable, event.issueKey)
        }
    }

    private fun recordLogMessage(message: String?) {
        if (!enabled || Tracer.isDisabled || message.isNullOrEmpty()) {
            return
        }
        TracerCrashReport.log(message)
    }

    private fun setPersistentCustomKey(key: String?, value: String?) {
        if (!enabled || Tracer.isDisabled || key.isNullOrEmpty()) {
            return
        }
        // setCustomProperty rather than setKey: Tracer caps a key's value at
        // 31 characters but a custom property's at 64, and 31 is too short for
        // most of what callers actually want to attach.
        AndroidEventScope.setPersistentProperty(key, value)
    }

    private fun setNativeUserId(userId: String?) {
        if (!enabled || Tracer.isDisabled) {
            return
        }
        Tracer.setUserId(userId)
    }

    private fun severityOf(name: String?): Severity = when (name) {
        "fatal" -> Severity.FATAL
        "warning" -> Severity.WARNING
        "notice" -> Severity.NOTICE
        "info" -> Severity.INFO
        "debug" -> Severity.DEBUG
        else -> Severity.ERROR
    }

    private fun isSdkOnClasspath(): Boolean = try {
        Class.forName("ru.ok.tracer.crash.report.TracerCrashReport")
        true
    } catch (error: Throwable) {
        false
    }

    /**
     * Detects whether the `ru.ok.tracer` Gradle plugin ran.
     *
     * The plugin writes `tracer_app_token`, `tracer_environment`,
     * `tracer_is_disabled` and `tracer_mapping_uuid` as generated resources.
     * Without them the SDK has no token and silently collects nothing, which is
     * a confusing failure to debug from Dart.
     */
    private fun hasGradlePluginResources(): Boolean {
        val context = applicationContext ?: return false
        return context.resources.getIdentifier(
            "tracer_app_token",
            "string",
            context.packageName
        ).let { it != 0 && context.getString(it).isNotBlank() }
    }

    private fun logDebug(message: String) {
        if (debug) {
            Log.d(TAG, message)
        }
    }

    private companion object {
        // Engine and Activity lifetimes must not reset SDK process lifetime.
        var enabled = false
        var runtimePaused = false
        var stopped = false
        var lifecycleError: String? = null
        const val TAG = "apptracer_flutter"
        const val CHANNEL_NAME = "ru.apptracer.flutter/tracer"
        const val KEY_DART_EXCEPTION_TYPE = "dart.exception_type"
        const val KEY_DART_NEEDS_SYMBOLICATION = "dart.needs_symbolication"
        const val KEY_DART_BUILD_ID = "dart.build_id"
    }
}
