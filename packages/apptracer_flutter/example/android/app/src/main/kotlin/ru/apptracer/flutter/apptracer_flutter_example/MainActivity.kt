package ru.apptracer.flutter.apptracer_flutter_example

import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a small channel for the two failure modes Dart cannot reach.
 *
 * A native crash and an ANR are the native SDK's job, not this package's, but
 * checks 7 and 8 of the live-verification plan still need a way to trigger
 * them from the example. Nothing here touches the Tracer SDK, so this file
 * stays in the ordinary source set and compiles without credentials.
 */
class MainActivity : FlutterActivity() {

    private var verificationEngine: FlutterEngine? = null

    private fun checkSecondaryEngine(result: MethodChannel.Result) {
        if (verificationEngine != null) { result.error("busy", "probe active", null); return }
        val engine = FlutterEngine(this)
        verificationEngine = engine
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "ru.apptracer.flutter.example/secondary")
        channel.setMethodCallHandler { call, reply ->
            if (call.method == "result") {
                reply.success(null)
                result.success(call.arguments)
                Handler(Looper.getMainLooper()).post {
                    channel.setMethodCallHandler(null)
                    engine.destroy()
                    verificationEngine = null
                }
            } else reply.notImplemented()
        }
        engine.dartExecutor.executeDartEntrypoint(io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint(
            io.flutter.FlutterInjector.instance().flutterLoader().findAppBundlePath(), "secondaryConsentProbe"))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "collectionRuntimeSnapshot" -> {
                        val writer = Class.forName("ru.ok.tracer.minidump.Minidump").getMethod("getInstance").invoke(null)
                        val installed = writer.javaClass.getDeclaredField("installedMinidumpWriter").apply { isAccessible = true }.getBoolean(writer)
                        result.success(mapOf(
                            "pid" to Process.myPid(),
                            "nativeInstalled" to installed,
                            "watchdogs" to Thread.getAllStackTraces().keys.count { it.javaClass.name == "ru.ok.tracer.crash.report.AnrWatchdogThread" }
                        ))
                    }
                    "probeRetiredSdkStartup" -> {
                        // Explicit reproducer after managed stop/clear. Never
                        // reset vendor singletons or enable the retired runtime.
                        val type = Class.forName("ru.ok.tracer.Tracer")
                        val tracer = type.getField("INSTANCE").get(null)
                        val context = type.getMethod("getContext").invoke(tracer) as android.content.Context
                        val handler = Thread.getDefaultUncaughtExceptionHandler()
                        Class.forName("ru.ok.tracer.startup.TracerStartup")
                            .getMethod("init", android.content.Context::class.java).invoke(null, context)
                        val initializedAgain = try {
                            type.getMethod("init\$tracer_commons_release", android.content.Context::class.java)
                                .invoke(tracer, context)
                            "returned"
                        } catch (failure: java.lang.reflect.InvocationTargetException) {
                            failure.targetException.message ?: failure.targetException.javaClass.simpleName
                        }
                        val runtime = Class.forName("ru.apptracer.flutter.Sdk140ConsentRuntime")
                        val sdkContext = runtime.getDeclaredField("sdkContext").apply { isAccessible = true }.get(null)
                        val io = sdkContext.javaClass.getDeclaredField("io").apply { isAccessible = true }.get(sdkContext)
                        val open = io.javaClass.getDeclaredMethod("isOpen").apply { isAccessible = true }.invoke(io)
                        result.success(mapOf(
                            "coreReinitialize" to initializedAgain,
                            "ioOpenAfterStartup" to open,
                            "handlerUnchanged" to (handler === Thread.getDefaultUncaughtExceptionHandler()),
                            "disabled" to type.getMethod("isDisabled").invoke(null)
                        ))
                    }
                    "disableSdkForVerification" -> {
                        // Simulate a host's ordinary runtime pause, without
                        // invoking the plugin's consent withdrawal/cleanup.
                        try {
                            Class.forName("ru.ok.tracer.Tracer").getMethod("disable").invoke(null)
                            result.success(null)
                        } catch (failure: ReflectiveOperationException) {
                            result.error("sdk_unavailable", "Runtime pause unavailable", null)
                        }
                    }
                    "cleanupFailureFixture" -> {
                        val root = java.io.File(cacheDir, "tracer")
                        if (call.argument<Boolean>("enabled") == true) {
                            root.mkdirs()
                            java.io.File(root, "verification-undeletable").writeText("fixture")
                            android.system.Os.chmod(root.absolutePath, 320) // 0500: no writes
                        } else if (root.exists()) {
                            android.system.Os.chmod(root.absolutePath, 448) // 0700
                        }
                        result.success(null)
                    }
                    "checkSecondaryEngine" -> checkSecondaryEngine(result)
                    "recreateForVerification" -> {
                        intent.putExtra("apptracerScenario", "cold-after-recreate")
                        result.success(null)
                        Handler(Looper.getMainLooper()).post { recreate() }
                    }
                    "verificationContext" -> result.success(mapOf(
                        "scenario" to (intent.getStringExtra("apptracerScenario") ?: "inspect"),
                        "runId" to (intent.getStringExtra("apptracerRun") ?: ""),
                        "cachePath" to cacheDir.absolutePath,
                        "filesPath" to filesDir.absolutePath,
                        "outputPath" to java.io.File(getExternalFilesDir(null), "verification").absolutePath
                    ))
                    "configureVerification" -> {
                        val url = call.argument<String>("apiUrl")
                        if (url != null && !url.startsWith("http://127.0.0.1:")) {
                            result.error("invalid_endpoint", "Only local test endpoints are allowed", null)
                        } else {
                            getSharedPreferences("apptracer_verification", MODE_PRIVATE).edit()
                                .putString("api_url", url).commit()
                            result.success(null)
                        }
                    }
                    "exitInfo" -> {
                        if (android.os.Build.VERSION.SDK_INT >= 30) {
                            val manager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                            result.success(manager.getHistoricalProcessExitReasons(packageName, 0, 10).map {
                                mapOf("reason" to it.reason, "timestamp" to it.timestamp,
                                    "pid" to it.pid, "hasTrace" to (it.traceInputStream?.use { stream -> stream.read() != -1 } ?: false))
                            })
                        } else result.success(emptyList<Any>())
                    }
                    "crashNatively" -> {
                        // SIGSEGV to our own process: the signal handler that
                        // tracer-crash-report-native installs catches it the
                        // same way it would catch a real segfault. Killing the
                        // process outright would be invisible to it, and
                        // throwing from Kotlin would produce a JVM crash —
                        // a different path, already covered elsewhere.
                        result.success(null)
                        Process.sendSignal(Process.myPid(), SIGSEGV)
                    }

                    "crashJvm" -> {
                        // Exercise the Java uncaught-handler path separately
                        // from SIGSEGV. This is an explicit verification action.
                        result.success(null)
                        Handler(Looper.getMainLooper()).post {
                            ru.apptracer.verification.JavaCrashProbe.crash(intent.getStringExtra("apptracerRun") ?: "legacy")
                        }
                    }
                    "crashKotlin" -> {
                        result.success(null)
                        Handler(Looper.getMainLooper()).post {
                            ru.apptracer.verification.KotlinCrashProbe.crash(intent.getStringExtra("apptracerRun") ?: "legacy")
                        }
                    }

                    "blockMainThread" -> {
                        // Long on purpose. Tracer builds an ANR report from
                        // ApplicationExitInfo with REASON_ANR, which the system
                        // only records if it kills the process while the main
                        // thread is still stuck. A block that ends on its own
                        // leaves a healthy process behind and produces nothing,
                        // however loudly the ANR dialog complained. Measured
                        // 2026-08-26: a 10-second block gave "No crashes
                        // detected" on the next start.
                        val seconds = call.argument<Int>("seconds") ?: DEFAULT_ANR_SECONDS
                        // Answer first, block from a later message. The reply
                        // travels on this very thread, so blocking now would
                        // hold it until the ANR is over.
                        result.success(null)
                        Handler(Looper.getMainLooper()).post {
                            Thread.sleep(seconds * 1_000L)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL = "ru.apptracer.flutter.example/native"
        const val SIGSEGV = 11
        const val DEFAULT_ANR_SECONDS = 120
    }
}
