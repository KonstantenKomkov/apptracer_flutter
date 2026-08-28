package ru.apptracer.flutter

import android.app.Application
import ru.ok.tracer.HasTracerConfiguration
import ru.ok.tracer.TracerConfiguration

/**
 * An [Application] that carries the configuration this package applies anyway,
 * for an application that needs to add configuration of its own.
 *
 * Naming it in the manifest is **not** required: [TracerAutoConfigProvider]
 * installs the same settings at process start, and an integration that has no
 * `Application` of its own needs nothing at all. This class exists for the case
 * that undoes that — the SDK reads configuration off the `Application` object
 * and takes its list whole, so an `Application` implementing
 * [HasTracerConfiguration] replaces our defaults rather than adding to them.
 * Subclassing keeps them:
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
 * Which settings are in that list, and why they are the ones, is documented on
 * [TracerAutoConfig] — the single place this package decides it.
 *
 * Requires the `ru.ok.tracer` SDK on the classpath, which is the point at which
 * the manifest would name this class anyway.
 */
open class TracerApplication : Application(), HasTracerConfiguration {

    override val tracerConfiguration: List<TracerConfiguration>
        get() = TracerAutoConfig.defaultConfigurations()
}
