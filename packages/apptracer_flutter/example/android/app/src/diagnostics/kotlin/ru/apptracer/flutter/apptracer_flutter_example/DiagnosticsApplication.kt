package ru.apptracer.flutter.apptracer_flutter_example

import android.app.Application
import android.content.Context
import ru.ok.tracer.CoreTracerConfiguration
import ru.ok.tracer.HasTracerConfiguration
import ru.ok.tracer.Tracer
import ru.ok.tracer.TracerConfiguration
import ru.ok.tracer.crash.report.CrashFreeConfiguration
import ru.ok.tracer.crash.report.CrashReportConfiguration
import ru.ok.tracer.disk.usage.DiskUsageConfiguration
import ru.ok.tracer.heap.dumps.HeapDumpConfiguration
import ru.apptracer.flutter.TracerDiagnostics

/** Isolated native/Dart experiments, never part of the supported deferred integration. */
class DiagnosticsApplication : Application(), HasTracerConfiguration {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // Before SDK providers run. Permission in this fixture is process-local;
        // existing WorkManager files/jobs are NOT covered by consent cleanup.
        Tracer.disable()
    }

    override val tracerConfiguration: List<TracerConfiguration>
        get() = configurations(resources.getBoolean(R.bool.apptracer_verification_dart_diagnostics))

    // Keep configuration construction testable without an attached Android Context.
    fun configurations(dartApi: Boolean): List<TracerConfiguration> = listOf(
            CoreTracerConfiguration.build {
                // Keep production periodic constraints; this is a release APK.
                setDebugUpload(false)
                provideApiUrl { "http://127.0.0.1:37018" }
            },
            CrashReportConfiguration.build { setEnabled(dartApi) },
            CrashFreeConfiguration.build { setEnabled(false) },
            if (dartApi)
                HeapDumpConfiguration.Builder()
                    .provideEnabled(TracerDiagnostics.heapDumpEnabledProvider()).build()
            else DiagnosticsHeapDecision.configuration(),
            // Force a sample for this small synthetic app; the production
            // interesting-size default can legitimately discard its result.
            DiskUsageConfiguration.Builder().setEnabled(true).setInterestingSize(1).build(),
        )
}
