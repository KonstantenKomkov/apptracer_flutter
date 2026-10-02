package ru.apptracer.flutter

import org.junit.Test

/** Keeps the standalone JVM checks in the Gradle/CI unit-test suite as well. */
class NativeLifecycleHelpersTest {
    @Test
    fun `revocable executors reject queued and future diagnostics`() {
        RevocableExecutorTest.main(emptyArray())
    }

    @Test
    fun `SDK sequential queue releases diagnostics after revocation`() {
        Sdk140BackgroundExecutorTest.main(emptyArray())
    }

    @Test
    fun `SDK endpoint cannot fall back to Tracer after revocation`() {
        Sdk140EndpointTest.main(emptyArray())
    }

    @Test
    fun `SDK diagnostic stores retire without loading previous reports`() {
        Sdk140DiagnosticBuffersTest.main(emptyArray())
    }

    @Test
    fun `fatal writers drain before native purge`() {
        Sdk140FatalHandlerTest.main(emptyArray())
    }

    @Test
    fun `purge removes reports without following symbolic links`() {
        DiagnosticFilesTest.main(emptyArray())
    }

    @Test
    fun `purge removes cache reports and persistent device id`() {
        val base = java.io.File(System.getProperty("java.io.tmpdir"), "tracer-roots-${System.nanoTime()}")
        val cacheRoot = java.io.File(java.io.File(base, "cache"), "tracer")
        val filesRoot = java.io.File(java.io.File(base, "files"), "tracer")
        try {
            val report = java.io.File(cacheRoot, "crashes/report/stacktrace")
            val deviceId = java.io.File(filesRoot, "device_id.txt")
            check(report.parentFile?.mkdirs() == true)
            check(filesRoot.mkdirs())
            report.writeText("report")
            deviceId.writeText("identifier")

            DiagnosticFiles.clear(cacheRoot)
            DiagnosticFiles.clear(filesRoot)

            check(!cacheRoot.exists())
            check(!filesRoot.exists())
        } finally {
            base.deleteRecursively()
        }
    }
}
