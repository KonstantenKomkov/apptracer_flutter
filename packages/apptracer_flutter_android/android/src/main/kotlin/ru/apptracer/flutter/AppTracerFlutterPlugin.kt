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
class AppTracerFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var enabled = false
    private var debug = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
        enabled = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> result.success(initialize(call))
                "stopCollection" -> {
                    stopCollection()
                    result.success(null)
                }
                "recordError" -> {
                    recordError(call)
                    result.success(null)
                }
                "recordLog" -> {
                    recordLog(call.argument<String>("message"))
                    result.success(null)
                }
                "setCustomKey" -> {
                    setCustomKey(call.argument<String>("key"), call.argument<String>("value"))
                    result.success(null)
                }
                "removeCustomKey" -> {
                    setCustomKey(call.argument<String>("key"), null)
                    result.success(null)
                }
                "setUserId" -> {
                    setUserId(call.argument<String>("userId"))
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
            result.success(null)
        }
    }

    private fun initialize(call: MethodCall): Boolean {
        debug = call.argument<Boolean>("debug") ?: false

        if (call.argument<String>("appToken") != null) {
            Log.w(
                TAG,
                "TracerOptions.appToken is ignored on Android. The token comes " +
                    "from the ru.ok.tracer Gradle plugin, which writes it into " +
                    "the tracer_app_token string resource at build time."
            )
        }

        if (call.argument<String>("environment") != null) {
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

        // `isDisabled` is a Kotlin property on Tracer, not a method.
        if (Tracer.isDisabled) {
            logDebug("the Tracer SDK reports that it is disabled")
            enabled = false
            return false
        }

        enabled = true
        return true
    }

    /**
     * Stops collection.
     *
     * `Tracer.disable()` sets a one-way flag inside the SDK: there is no
     * documented way to re-enable it in the same process. That is the correct
     * behaviour for a withdrawal of consent, and it is why a later
     * `initialize` cannot restart native collection until the app restarts.
     */
    private fun stopCollection() {
        enabled = false
        if (!isSdkOnClasspath()) {
            return
        }
        Tracer.disable()
    }

    private fun recordError(call: MethodCall) {
        if (!enabled) {
            return
        }

        val exceptionType = call.argument<String>("exceptionType") ?: "DartError"
        val message = call.argument<String>("message").orEmpty()
        val issueKey = call.argument<String>("issueKey")
        val severity = severityOf(call.argument<String>("severity"))

        @Suppress("UNCHECKED_CAST")
        val stack = call.argument<Map<String, Any?>>("stackTrace")

        @Suppress("UNCHECKED_CAST")
        val frames = (stack?.get("frames") as? List<Map<String, Any?>>).orEmpty()

        val title = if (message.isEmpty()) exceptionType else "$exceptionType: $message"
        val throwable = DartError(title)
        throwable.stackTrace = DartError.toStackTrace(frames)

        @Suppress("UNCHECKED_CAST")
        val customKeys = call.argument<Map<String, String>>("customKeys")
        customKeys?.forEach { (key, value) -> Tracer.setCustomProperty(key, value) }

        Tracer.setCustomProperty(KEY_DART_EXCEPTION_TYPE, exceptionType)
        if (stack?.get("needsSymbolication") == true) {
            Tracer.setCustomProperty(KEY_DART_NEEDS_SYMBOLICATION, "true")
            (stack["buildId"] as? String)?.let {
                Tracer.setCustomProperty(KEY_DART_BUILD_ID, it)
            }
        }

        TracerCrashReport.report(severity, throwable, issueKey)
    }

    private fun recordLog(message: String?) {
        if (!enabled || message.isNullOrEmpty()) {
            return
        }
        TracerCrashReport.log(message)
    }

    private fun setCustomKey(key: String?, value: String?) {
        if (!enabled || key.isNullOrEmpty()) {
            return
        }
        // setCustomProperty rather than setKey: Tracer caps a key's value at
        // 31 characters but a custom property's at 128, and 31 is too short for
        // most of what callers actually want to attach.
        Tracer.setCustomProperty(key, value)
    }

    private fun setUserId(userId: String?) {
        if (!enabled) {
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
        ) != 0
    }

    private fun logDebug(message: String) {
        if (debug) {
            Log.d(TAG, message)
        }
    }

    private companion object {
        const val TAG = "apptracer_flutter"
        const val CHANNEL_NAME = "ru.apptracer.flutter/tracer"
        const val KEY_DART_EXCEPTION_TYPE = "dart.exception_type"
        const val KEY_DART_NEEDS_SYMBOLICATION = "dart.needs_symbolication"
        const val KEY_DART_BUILD_ID = "dart.build_id"
    }
}
