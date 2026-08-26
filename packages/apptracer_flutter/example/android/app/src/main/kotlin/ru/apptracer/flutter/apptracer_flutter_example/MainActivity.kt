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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
