package ru.apptracer.flutter

import android.app.Application
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import ru.ok.tracer.SystemState
import ru.ok.tracer.Tracer
import ru.ok.tracer.crash.report.CrashReportConfiguration
import ru.ok.tracer.crash.report.TracerCrashReport
import ru.ok.tracer.session.SessionStateStorage
import ru.ok.tracer.utils.SimpleFileKeyValueStorage
import java.io.File
import java.lang.reflect.Field
import java.nio.file.Files
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class EventContextTest {
    private val saved = mutableListOf<Triple<Field, Any?, Any?>>()
    private lateinit var temporaryDirectory: File

    @Before
    fun initializeSdkStorage() {
        AndroidEventScope.clearPersistentProperties()
        temporaryDirectory = Files.createTempDirectory("apptracer-event-context").toFile()
        val storage = SessionStateStorage::class.java
            .getConstructor(android.content.Context::class.java)
            .newInstance(Application())
        replace(SessionStateStorage::class.java, "loaded", true, storage)
        replace(SessionStateStorage::class.java, "fileStorage",
            SimpleFileKeyValueStorage { File(temporaryDirectory, "state") }, storage)
        replace(SessionStateStorage::class.java, "currentSystemStateData", systemState(), storage)
        replace(Tracer::class.java, "stateStorage", storage)
        replace(Tracer::class.java, "disabledOnBuild", false)
        replace(Tracer::class.java, "disabledInRuntime", false)
        replace(TracerCrashReport::class.java, "crashLoggerInternal", null)
        replace(TracerCrashReport::class.java, "isConfigDisabled", false)
        val configuration = CrashReportConfiguration.Builder().setEnabled(true).build()
        replace(Tracer::class.java, "runtimeConfigs", mapOf(configuration.getFeature() to configuration))
        replace(AppTracerFlutterPlugin::class.java, "enabled", true)
    }

    @After
    fun restoreSdkStorage() {
        saved.asReversed().forEach { (field, receiver, value) -> field.set(receiver, value) }
        temporaryDirectory.deleteRecursively()
    }

    @Test
    fun `event properties and diagnostics do not leak into following events`() {
        val plugin = AppTracerFlutterPlugin()
        invoke(plugin, "setCustomKey", mapOf("key" to "tenant", "value" to "global-tenant"))
        invoke(plugin, "setCustomKey", mapOf("key" to "collision", "value" to "global-value"))

        recordError(plugin, mapOf(
            "endpoint" to "/orders",
            "collision" to "event-value",
        ), needsSymbolication = true, buildId = "build-a")

        assertEquals(
            mapOf("tenant" to "global-tenant", "collision" to "global-value"),
            properties(),
        )

        recordError(plugin, emptyMap(), needsSymbolication = false)

        assertEquals(
            mapOf("tenant" to "global-tenant", "collision" to "global-value"),
            properties(),
        )
        assertFalse(properties().containsKey("endpoint"))
        assertFalse(properties().containsKey("dart.needs_symbolication"))
        assertFalse(properties().containsKey("dart.build_id"))
    }

    @Test
    fun `beforeSend removals and changes override native scope only for their report`() {
        AndroidEventScope.setPersistentProperty("tenant", "global-tenant")
        AndroidEventScope.setPersistentProperty("collision", "global-value")
        val outgoing = mutableMapOf<String, String?>(
            "collision" to "filtered-value",
            "endpoint" to "/orders",
        )

        AndroidEventScope.withEventProperties(outgoing) {
            assertEquals(
                mapOf("collision" to "filtered-value", "endpoint" to "/orders"),
                properties(),
            )
        }

        assertEquals(
            mapOf("tenant" to "global-tenant", "collision" to "global-value"),
            properties(),
        )
    }

    @Test
    fun `report failure restores native scope`() {
        AndroidEventScope.setPersistentProperty("tenant", "global-tenant")

        assertThrows(AssertionError::class.java) {
            AndroidEventScope.withEventProperties(mutableMapOf("endpoint" to "/orders")) {
                throw AssertionError("synthetic SDK failure")
            }
        }

        assertEquals(mapOf("tenant" to "global-tenant"), properties())
    }

    @Test
    fun `concurrent reports cannot mix event properties`() {
        AndroidEventScope.setPersistentProperty("collision", "global-value")
        val workers = 6
        val executor = Executors.newFixedThreadPool(workers)
        val ready = CountDownLatch(workers)
        val start = CountDownLatch(1)
        val observations = ConcurrentLinkedQueue<MutableMap<String, String>>()
        try {
            val futures = (0 until workers).map { index ->
                executor.submit {
                    ready.countDown()
                    assertTrue(start.await(5, TimeUnit.SECONDS))
                    AndroidEventScope.withEventProperties(mutableMapOf(
                        "collision" to "event-$index",
                        "once-$index" to "$index",
                    )) {
                        Thread.sleep(5)
                        observations.add(properties().toMutableMap())
                    }
                }
            }
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()
            futures.forEach { it.get(5, TimeUnit.SECONDS) }
        } finally {
            executor.shutdownNow()
        }

        assertEquals(workers, observations.size)
        observations.forEach { event ->
            assertTrue(event.remove("collision")!!.startsWith("event-"))
            assertEquals(1, event.size)
            assertTrue(event.keys.single().startsWith("once-"))
        }
        assertEquals(mapOf("collision" to "global-value"), properties())
    }

    private fun recordError(
        plugin: AppTracerFlutterPlugin,
        customKeys: Map<String, String>,
        needsSymbolication: Boolean,
        buildId: String? = null,
    ) {
        invoke(plugin, "recordError", mapOf(
            "exceptionType" to "StateError",
            "message" to "synthetic",
            "severity" to "error",
            "customKeys" to customKeys,
            "stackTrace" to mapOf(
                "frames" to emptyList<Map<String, Any?>>(),
                "needsSymbolication" to needsSymbolication,
                "buildId" to buildId,
            ),
        ))
    }

    private fun properties(): Map<String, String> =
        Tracer.stateStorage.currentSystemState.properties.toMap()

    private fun systemState(): SystemState = SystemState::class.java.getConstructor(
        String::class.java, java.lang.Long.TYPE, String::class.java, String::class.java,
        String::class.java, String::class.java, String::class.java, String::class.java,
        String::class.java, String::class.java, java.lang.Boolean.TYPE, String::class.java,
        java.lang.Boolean.TYPE, Map::class.java, Set::class.java,
    ).newInstance(
        "1.0", 1L, "test", "test", "build", "session", "device", "device-id",
        "vendor", "os", false, "unknown", false, mutableMapOf<String, String>(), emptySet<Any>(),
    )

    private fun replace(type: Class<*>, name: String, value: Any?, receiver: Any? = null) {
        val field = type.getDeclaredField(name).apply { isAccessible = true }
        if (saved.none { it.first == field && it.second === receiver }) {
            saved.add(Triple(field, receiver, field.get(receiver)))
        }
        field.set(receiver, value)
    }

    private fun invoke(plugin: AppTracerFlutterPlugin, method: String, args: Map<String, Any?>) {
        plugin.onMethodCall(MethodCall(method, args), object : MethodChannel.Result {
            override fun success(result: Any?) = Unit
            override fun error(code: String, message: String?, details: Any?) {
                throw AssertionError("$code: $message")
            }
            override fun notImplemented() = throw AssertionError("method missing: $method")
        })
    }
}
