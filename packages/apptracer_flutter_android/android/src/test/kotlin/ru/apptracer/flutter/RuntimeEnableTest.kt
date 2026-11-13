package ru.apptracer.flutter

import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import ru.ok.tracer.Tracer
import ru.ok.tracer.crash.report.CrashReportConfiguration
import ru.ok.tracer.crash.report.TracerCrashReport
import java.lang.reflect.Field
import java.util.concurrent.atomic.AtomicBoolean

/** Real vendor flag/configuration behavior; no Android startup or networking. */
class RuntimeEnableTest {
    private val saved = mutableMapOf<Field, Any?>()
    private val initialized = Tracer::class.java.getDeclaredField("isInitialized")
        .apply { isAccessible = true }.get(null) as AtomicBoolean
    private var previousInitialized = false

    private fun replace(type: Class<*>, name: String, value: Any?) {
        val field = type.getDeclaredField(name).apply { isAccessible = true }
        if (!saved.containsKey(field)) saved[field] = field.get(null)
        field.set(null, value)
    }

    private fun configuration(enabled: Boolean) {
        val configuration = CrashReportConfiguration.Builder().setEnabled(enabled).build()
        replace(Tracer::class.java, "runtimeConfigs", mapOf(configuration.getFeature() to configuration))
        replace(TracerCrashReport::class.java, "isConfigDisabled", !enabled)
    }

    @Before
    fun initializeFixture() {
        previousInitialized = initialized.getAndSet(true)
        replace(Tracer::class.java, "disabledOnBuild", false)
        replace(Tracer::class.java, "disabledInRuntime", false)
        replace(Sdk140ConsentRuntime::class.java, "host", null)
        replace(Sdk140ConsentRuntime::class.java, "state", "disabled")
        replace(Sdk140ConsentRuntime::class.java, "reason", null)
        replace(Sdk140ConsentRuntime::class.java, "cleanupsPending", 0)
        configuration(true)
    }

    @After
    fun restoreFixture() {
        saved.forEach { (field, value) -> field.set(null, value) }
        initialized.set(previousInitialized)
    }

    @Test
    fun `public pause returns disabled and resumes without initializing`() {
        assertEquals("disabled", Sdk140ConsentRuntime.pauseRuntime()["state"])
        assertTrue(Tracer.isDisabled)
        assertEquals("sdk_runtime_disabled", Sdk140ConsentRuntime.pauseRuntime()["reason"])
        assertEquals("enabled", Sdk140ConsentRuntime.resumeRuntime()["state"])
        assertFalse(Tracer.isDisabled)
    }

    @Test
    fun `optional commands do not initialize modules or change collection`() {
        var reply: Map<String, String>? = null
        TracerDiagnostics.run(true, " ") { reply = it }
        assertEquals("heap_tag_required", reply!!["reason"])
        TracerDiagnostics.run(true, "manual") { reply = it }
        assertEquals("diagnostic_module_not_initialized", reply!!["reason"])
        TracerDiagnostics.run(false, null) { reply = it }
        assertEquals("diagnostic_module_not_initialized", reply!!["reason"])
        assertEquals("heap_provider_not_installed", TracerDiagnostics.setHeapEnabled(true)["reason"])
        assertFalse(TracerDiagnostics.heapDumpEnabledProvider().get())
        assertFalse(Tracer.isDisabled)
        Tracer.disable()
        TracerDiagnostics.run(false, null) { reply = it }
        assertEquals("collection_disabled", reply!!["reason"])
        assertTrue(Tracer.isDisabled)
    }

    @Test
    fun `heap decision provider changes dynamically and remains false while disabled`() {
        val heap = ru.ok.tracer.heap.dumps.HeapDumpConfiguration.Builder()
            .provideEnabled(TracerDiagnostics.heapDumpEnabledProvider()).build()
        val crash = CrashReportConfiguration.Builder().setEnabled(true).build()
        replace(Tracer::class.java, "runtimeConfigs", mapOf(heap.getFeature() to heap, crash.getFeature() to crash))
        TracerDiagnostics.revoke()
        assertFalse(TracerDiagnostics.heapDumpEnabledProvider().get())
        assertEquals("invoked", TracerDiagnostics.setHeapEnabled(true)["state"])
        assertTrue(TracerDiagnostics.heapDumpEnabledProvider().get())
        Tracer.disable()
        assertFalse(TracerDiagnostics.heapDumpEnabledProvider().get())
        assertEquals("disabled", TracerDiagnostics.setHeapEnabled(true)["state"])
        Sdk140ConsentRuntime.resumeRuntime()
        assertTrue(TracerDiagnostics.heapDumpEnabledProvider().get())
        TracerDiagnostics.revoke()
        assertFalse(TracerDiagnostics.heapDumpEnabledProvider().get())
    }

    @Test
    fun `runtime disable is observed and repeated resume restores the real flag`() {
        repeat(2) {
            Tracer.disable()
            assertEquals("sdk_runtime_disabled", Sdk140ConsentRuntime.automaticSnapshot()["reason"])
            assertEquals("enabled", Sdk140ConsentRuntime.resumeRuntime()["state"])
            assertFalse(Tracer.isDisabled)
            assertEquals("enabled", Sdk140ConsentRuntime.resumeRuntime()["state"])
        }
    }

    @Test
    fun `build disable is not cleared even when runtime configs exist`() {
        replace(Tracer::class.java, "disabledOnBuild", true)
        Tracer.disable()
        assertEquals("sdk_build_disabled", Sdk140ConsentRuntime.resumeRuntime()["reason"])
        assertTrue(Tracer.isDisabled)
        replace(Tracer::class.java, "disabledOnBuild", false)
        assertTrue("runtime flag was incorrectly cleared", Tracer.isDisabled)
    }

    @Test
    fun `uninitialized SDK cannot be enabled`() {
        initialized.set(false)
        Tracer.disable()
        assertEquals("sdk_not_initialized", Sdk140ConsentRuntime.resumeRuntime()["reason"])
        assertTrue(Tracer.isDisabled)
    }

    @Test
    fun `host configuration keeps collection disabled`() {
        configuration(false)
        Tracer.disable()
        assertEquals("sdk_collection_disabled", Sdk140ConsentRuntime.resumeRuntime()["reason"])
        assertTrue(Tracer.isDisabled)
    }

    @Test
    fun `pending cleanup cannot be bypassed by runtime resume`() {
        Tracer.disable()
        replace(Sdk140ConsentRuntime::class.java, "cleanupsPending", 1)
        replace(Sdk140ConsentRuntime::class.java, "reason", "cleanup_pending")
        assertEquals("cleanup_pending", Sdk140ConsentRuntime.resumeRuntime()["reason"])
        assertTrue(Tracer.isDisabled)
    }

    @Test
    fun `retired or failed managed runtime cannot be resumed`() {
        replace(Sdk140ConsentRuntime::class.java, "host", android.app.Application())
        replace(Sdk140ConsentRuntime::class.java, "irreversible", true)
        Tracer.disable()
        for (state in listOf("restartRequired", "error")) {
            replace(Sdk140ConsentRuntime::class.java, "state", state)
            assertEquals(state, Sdk140ConsentRuntime.resumeRuntime()["state"])
            assertEquals(state, Sdk140ConsentRuntime.start(null, false)["state"])
            assertTrue(Tracer.isDisabled)
        }
    }

    @Test
    fun `throwing SDK logger leaves a failed managed resume disabled`() {
        replace(Sdk140ConsentRuntime::class.java, "host", android.app.Application())
        replace(Sdk140ConsentRuntime::class.java, "state", "enabled")
        replace(Sdk140ConsentRuntime::class.java, "irreversible", true)
        Tracer.disable()
        val delegate = Class.forName("ru.ok.tracer.utils.TracerLoggerDelegate")
        val throwingLogger = java.lang.reflect.Proxy.newProxyInstance(
            delegate.classLoader, arrayOf(delegate)
        ) { _, method, _ ->
            if (method.name == "getMinLogPriority") 0
            // The vendor catches Exception, but Error escapes its delegate.
            else throw AssertionError("host logger failed")
        }
        replace(Class.forName("ru.ok.tracer.utils.Logger"), "delegate", throwingLogger)
        assertEquals("native_enable_failed", Sdk140ConsentRuntime.resumeRuntime()["reason"])
        assertTrue(Tracer.isDisabled)
        assertEquals("error", Sdk140ConsentRuntime.start(null, false)["state"])
    }
}
