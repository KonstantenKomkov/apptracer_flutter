package ru.apptracer.flutter

import android.app.Application
import ru.ok.tracer.HasTracerConfiguration
import ru.ok.tracer.TracerConfiguration
import ru.ok.tracer.crash.report.CrashReportConfiguration

/**
 * An [Application] that configures the Tracer SDK the way a Flutter
 * application needs it, so that an integration does not have to write this
 * class by hand.
 *
 * Point the manifest at it and nothing else is required:
 *
 * ```xml
 * <application android:name="ru.apptracer.flutter.TracerApplication" … >
 * ```
 *
 * An application that already has an `Application` of its own subclasses this
 * one instead, and adds to the list rather than replacing it:
 *
 * ```kotlin
 * class MyApplication : TracerApplication() {
 *     override val tracerConfiguration: List<TracerConfiguration>
 *         get() = super.tracerConfiguration + CoreTracerConfiguration.build {
 *             setDebugUpload(true)
 *         }
 * }
 * ```
 *
 * The configuration is built through `Builder` rather than the SDK's `build {}`
 * helper on purpose: that helper is an inline function compiled for JVM target
 * 11, and inlining it here would force every consumer of this plugin to compile
 * for 11 as well.
 *
 * ### Why this cannot simply be the default
 *
 * The SDK reads its configuration from the `Application` object and only from
 * there: `Tracer` checks whether it implements [HasTracerConfiguration] and
 * otherwise logs "Application does not implement HasTracerConfiguration". A
 * Flutter plugin is not the `Application`, and the runtime setter the SDK uses
 * internally is not public API. One line in the manifest is as close to a
 * default as this can get.
 *
 * ### What it turns on, and why that one thing
 *
 * The non-fatal rate limit, which the vendor recommends and which matters more
 * here than in a native application. Every Dart error this package reports is a
 * non-fatal, and the SDK's hard default is **8 non-fatals per session**
 * (`LIMIT_MAX_NON_FATALS_PER_SESSION`); the limit raises that to 10 per hour.
 * An application that hits the cap loses errors silently, which is the failure
 * mode a crash reporter can least afford.
 *
 * Nothing else is set. `setDebugUpload` would start sending from debug builds,
 * and `setSendAnr` costs an ANR watchdog — both are decisions for the
 * application, not for a wrapper.
 *
 * Requires the `ru.ok.tracer` SDK on the classpath, which is the point at which
 * the manifest would name this class anyway.
 */
open class TracerApplication : Application(), HasTracerConfiguration {

    override val tracerConfiguration: List<TracerConfiguration>
        get() = listOf(
            CrashReportConfiguration.Builder()
                .setExperimentalNonFatalRateLimitEnabled(true)
                .build(),
        )
}
