package ru.apptracer.flutter.apptracer_flutter_example

import android.app.Application
import ru.ok.tracer.CoreTracerConfiguration
import ru.ok.tracer.HasTracerConfiguration
import ru.ok.tracer.TracerConfiguration
import ru.ok.tracer.crash.report.CrashFreeConfiguration
import ru.ok.tracer.crash.report.CrashReportConfiguration

/**
 * Configures the Tracer Android SDK for the example.
 *
 * Lives in its own `src/tracer` source set, wired in by `app/tracer.gradle`,
 * because it references `ru.ok.tracer` — which is only on the classpath when
 * the build was started with `-Ptracer.enabled=true`. A checkout without
 * credentials must keep compiling.
 *
 * Two settings here are not defaults and are the reason this class exists:
 *
 *  * `setDebugUpload(true)` — without it the SDK sends nothing from a debug
 *    build, and half an hour goes into looking for events that were never
 *    dispatched.
 *  * `setSendAnr(true)` — ANR reporting, needed by check 8 of the
 *    live-verification plan.
 *
 * The non-fatal rate limit is deliberately left at its default: changing it
 * mid-verification would make it unclear whether a missing event was dropped
 * by the limiter or never sent. Note that leaving it out is an active choice
 * here — the SDK takes this list whole, so it also drops the limit that
 * `ru.apptracer.flutter.TracerAutoConfigProvider` installs for every
 * integration that writes no configuration of its own.
 */
class TracerHostApplication : Application(), HasTracerConfiguration {

    override val tracerConfiguration: List<TracerConfiguration>
        get() = listOf(
            CoreTracerConfiguration.build {
                setDebugUpload(true)
            },
            CrashReportConfiguration.build {
                setSendAnr(true)
                // Optional: setExperimentalAnrSnapshotsEnabled(true).
                //
                // Off by default. Without it a report logs "No main snapshots
                // to attach" — measured 2026-08-26 on an API 35 emulator — but
                // the stack of the blocked main thread still arrives, from the
                // system's own ANR trace: that run named this file's blocking
                // lambda exactly. What the flag adds is the *history* of the
                // stall: AnrWatchdogThread samples the main thread every 500 ms
                // after a 3-second freeze. Those are JVM frames, and Dart runs
                // on Flutter's own UI thread, so a Dart-side stall would not
                // show up in them. Left off: it is the vendor's experimental
                // flag, and the example should not read as a recommendation.
            },
            CrashFreeConfiguration.build {
                setEnabled(true)
            },
        )
}
