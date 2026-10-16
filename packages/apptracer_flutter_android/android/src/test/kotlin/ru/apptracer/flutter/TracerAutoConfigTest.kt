package ru.apptracer.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.ok.tracer.Tracer
import ru.ok.tracer.TracerConfiguration
import ru.ok.tracer.TracerFeature
import ru.ok.tracer.crash.report.CrashReportConfiguration

/**
 * Pins the two things about the auto-configuration that a new Tracer SDK
 * version could break quietly: that the one setting we care about is actually
 * set, and that the non-public setter it is delivered through still exists.
 *
 * Both are read reflectively because the SDK marks them `internal`, and Kotlin
 * cannot spell the `$module` suffix its members carry in the bytecode. Nothing
 * here is minified, so reflection is safe in a way it would not be in the
 * plugin itself — see [TracerAutoConfig].
 */
class TracerAutoConfigTest {

    @Test
    fun `enables the non-fatal rate limit`() {
        val configuration = TracerAutoConfig.defaultConfigurations().single()

        assertTrue(configuration is CrashReportConfiguration)
        assertTrue(configuration.readsRateLimitAsEnabled())
        assertFalse(configuration.readsTombstoneAsEnabled())
    }

    @Test
    fun `tombstone opt-in preserves the non-fatal rate limit without native module`() {
        val configuration = TracerAutoConfig.defaultConfigurations(true).single()

        assertTrue(configuration.readsRateLimitAsEnabled())
        assertTrue(configuration.readsTombstoneAsEnabled())
    }

    @Test
    fun `explicit false keeps tombstones disabled`() {
        assertFalse(TracerAutoConfig.defaultConfigurations(false).single().readsTombstoneAsEnabled())
    }

    @Test
    fun `publishes the configuration through the SDK's runtime configs`() {
        assertTrue(TracerAutoConfig.install())

        val published = Tracer::class.java
            .getDeclaredField("runtimeConfigs")
            .apply { isAccessible = true }
            .get(null)

        @Suppress("UNCHECKED_CAST")
        val byFeature = published as Map<TracerFeature, TracerConfiguration>
        val expected = TracerAutoConfig.defaultConfigurations().single()

        assertEquals(setOf(expected.getFeature()), byFeature.keys)
        assertTrue(byFeature.getValue(expected.getFeature()).readsRateLimitAsEnabled())
    }

    private fun TracerConfiguration.readsRateLimitAsEnabled(): Boolean =
        javaClass
            .getMethod("getNonFatalRateLimitEnabled\$tracer_crash_report_release")
            .invoke(this) as Boolean

    private fun TracerConfiguration.readsTombstoneAsEnabled(): Boolean =
        javaClass
            .getMethod("getTombstoneEnabled\$tracer_crash_report_release")
            .invoke(this) as Boolean
}
