package ru.apptracer.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The frame mapping is what Tracer groups Android events by, so it is worth
 * pinning down precisely.
 */
class DartErrorTest {

    @Test
    fun `splits a Dart member into declaring class and method`() {
        val frames = listOf(
            mapOf<String, Any?>(
                "member" to "MyHomePage.build.<anonymous closure>",
                "uri" to "package:example/main.dart",
                "line" to 78,
            )
        )

        val element = DartError.toStackTrace(frames).single()

        assertEquals("MyHomePage.build", element.className)
        assertEquals("<anonymous closure>", element.methodName)
        assertEquals("package:example/main.dart", element.fileName)
        assertEquals(78, element.lineNumber)
    }

    @Test
    fun `renders like a Dart frame`() {
        val frames = listOf(
            mapOf<String, Any?>(
                "member" to "Repository.load",
                "uri" to "package:example/repo.dart",
                "line" to 12,
            )
        )

        assertEquals(
            "Repository.load(package:example/repo.dart:12)",
            DartError.toStackTrace(frames).single().toString()
        )
    }

    @Test
    fun `handles a member with no dot`() {
        val frames = listOf(
            mapOf<String, Any?>(
                "member" to "_rootRunUnary",
                "uri" to "dart:async/zone.dart",
                "line" to 1407,
            )
        )

        val element = DartError.toStackTrace(frames).single()

        assertEquals("dart", element.className)
        assertEquals("_rootRunUnary", element.methodName)
    }

    @Test
    fun `keeps the virtual address of an obfuscated frame`() {
        val frames = listOf(
            mapOf<String, Any?>(
                "absAddress" to "0000007938a1c2f0",
                "virtAddress" to "00000000002cc2f0",
                "symbol" to "_kDartIsolateSnapshotInstructions+0x24b2f0",
            )
        )

        val element = DartError.toStackTrace(frames).single()

        assertEquals("dart.unsymbolized", element.className)
        assertEquals("_kDartIsolateSnapshotInstructions+0x24b2f0", element.methodName)
        assertTrue(element.fileName!!.contains("00000000002cc2f0"))
    }

    @Test
    fun `marks the asynchronous suspension frame`() {
        val frames = listOf(mapOf<String, Any?>("asyncSuspension" to true))

        assertEquals(
            "<asynchronous suspension>",
            DartError.toStackTrace(frames).single().methodName
        )
    }

    @Test
    fun `falls back to the raw line for an unrecognised frame`() {
        val frames = listOf(mapOf<String, Any?>("raw" to "total gibberish"))

        val element = DartError.toStackTrace(frames).single()

        assertEquals("total gibberish", element.fileName)
        assertEquals("<unknown>", element.methodName)
    }

    @Test
    fun `does not capture JVM frames`() {
        // The JVM stack at the point of the call is identical for every Dart
        // error, so capturing it would collapse every report into one group.
        val error = DartError("StateError: boom")

        assertTrue(error.stackTrace.isEmpty())
    }

    @Test
    fun `renders the Dart type in the message rather than the JVM class`() {
        assertEquals("DartError: StateError: boom", DartError("StateError: boom").toString())
        assertEquals("DartError", DartError("").toString())
    }

    @Test
    fun `tolerates an empty frame list`() {
        assertEquals(0, DartError.toStackTrace(emptyList()).size)
    }

    @Test
    fun `treats a missing line as zero`() {
        val frames = listOf(
            mapOf<String, Any?>("member" to "a.b", "uri" to "package:x/y.dart")
        )

        assertEquals(0, DartError.toStackTrace(frames).single().lineNumber)
        assertNull(DartError.toStackTrace(listOf(mapOf<String, Any?>("member" to "a.b"))).single().fileName)
    }
}
