package ru.apptracer.flutter

import org.junit.Assert.*
import org.junit.Test
import ru.ok.tracer.CoreTracerConfiguration
import ru.ok.tracer.Tracer
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.Lazy

/** Real SDK lazy caches must use fresh executors; retired references stay closed. */
class SessionRecreationTest {
    @Test
    fun `replacing a session never reopens a retired executor or background queue`() {
        val initialized = Tracer::class.java.getDeclaredField("isInitialized").apply { isAccessible = true }.get(null) as AtomicBoolean
        val configs = Tracer::class.java.getDeclaredField("runtimeConfigs").apply { isAccessible = true }
        val oldInitialized = initialized.getAndSet(true)
        val oldConfigs = configs.get(null)
        val threads = Class.forName("ru.ok.tracer.utils.TracerThreads")
        val snapshots = listOf("ioExecutor", "bgExecutor").map { name ->
            val lazy = threads.getDeclaredField("${name}\$delegate").apply { isAccessible = true }.get(null) as Lazy<*>
            val value = lazy.javaClass.getDeclaredField("_value").apply { isAccessible = true }
            val initializer = lazy.javaClass.getDeclaredField("initializer").apply { isAccessible = true }
            Triple(lazy, value.get(lazy), initializer.get(lazy))
        }
        try {
            var delivered = 0
            var retiredIo: RevocableExecutor? = null
            var retiredBg: Executor? = null
            repeat(4) {
                val io = RevocableExecutor(Executor { it.run() })
                val bg = Sdk140BackgroundExecutor(Executor { it.run() }, null)
                val core = CoreTracerConfiguration.Builder().setIoExecutor(io).setBgExecutor(bg).build()
                configs.set(null, mapOf(core.getFeature() to core))
                Sdk161SessionRuntime.LazyReset(threads.name, "ioExecutor").apply()
                Sdk161SessionRuntime.LazyReset(threads.name, "bgExecutor").apply()
                val instance = threads.getField("INSTANCE").get(null)
                threads.getMethod("runOnIo", Runnable::class.java).invoke(instance, Runnable { delivered++ })
                threads.getMethod("runInBgSequential", Runnable::class.java).invoke(instance, Runnable { delivered++ })
                assertEquals((it + 1) * 2, delivered)
                retiredIo?.execute { fail("retired IO admitted work") }
                assertFalse(retiredIo?.isOpen ?: false)
                retiredBg?.execute { fail("retired SDK background queue admitted work") }
                val bgLazy = threads.getDeclaredField("bgExecutor\$delegate").apply { isAccessible = true }.get(null) as Lazy<*>
                val currentBg = bgLazy.value as Executor
                io.close()
                bg.close()
                retiredIo = io
                retiredBg = currentBg
            }
            assertNotNull(retiredBg)
        } finally {
            snapshots.forEach { (lazy, value, initializer) ->
                lazy.javaClass.getDeclaredField("initializer").apply { isAccessible = true }.set(lazy, initializer)
                lazy.javaClass.getDeclaredField("_value").apply { isAccessible = true }.set(lazy, value)
            }
            configs.set(null, oldConfigs)
            initialized.set(oldInitialized)
        }
    }
}
