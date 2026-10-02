package ru.apptracer.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import ru.ok.tracer.Tracer

class CollectionLifecycleTest {
    @Before
    fun resetProcessState() {
        for (name in listOf("enabled", "stopped")) {
            AppTracerFlutterPlugin::class.java.getDeclaredField(name).apply {
                isAccessible = true
                setBoolean(null, false)
            }
        }
        AppTracerFlutterPlugin::class.java.getDeclaredField("lifecycleError").apply {
            isAccessible = true
            set(null, null)
        }
        Tracer::class.java.getDeclaredField("isDisabled").apply {
            isAccessible = true
            setBoolean(null, false)
        }
    }

    @Test
    fun `deferred runtime option cannot bypass required manifest`() {
        val reply = invoke(AppTracerFlutterPlugin(), "startCollection", mapOf(
            "nativeInitialization" to "deferred", "isCollectionEnabled" to true
        )) as Map<*, *>
        assertEquals("error", reply["state"])
        assertEquals("deferred_manifest_required", reply["reason"])
        assertFalse(Tracer.isDisabled)
    }

    @Test
    fun `purge without an engine context reports an error`() {
        val reply = invoke(AppTracerFlutterPlugin(), "stopAndClearCollection") as Map<*, *>
        assertEquals("error", reply["state"])
        assertEquals("context_missing", reply["reason"])
    }

    @Test
    fun `another plugin instance cannot bypass process stop`() {
        invoke(AppTracerFlutterPlugin(), "stopCollection")
        val anotherEngine = AppTracerFlutterPlugin()
        assertEquals(false, invoke(anotherEngine, "initialize"))
        val reply = invoke(anotherEngine, "getCollectionState") as Map<*, *>
        assertEquals("restartRequired", reply["state"])
    }

    private fun invoke(plugin: AppTracerFlutterPlugin, method: String,
                       args: Map<String, Any> = emptyMap()): Any? {
        var reply: Any? = null
        plugin.onMethodCall(MethodCall(method, args), object : MethodChannel.Result {
            override fun success(result: Any?) { reply = result }
            override fun error(code: String, message: String?, details: Any?) {
                throw AssertionError("$code: $message")
            }
            override fun notImplemented() { throw AssertionError("method missing: $method") }
        })
        return reply
    }
}
