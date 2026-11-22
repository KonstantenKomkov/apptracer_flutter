package ru.apptracer.flutter

import io.flutter.plugin.common.MethodCall
import org.junit.Assert.assertEquals
import org.junit.Test

class LegacyTracerContractTest {
    @Test
    fun `legacy compatibility retains every event field`() {
        val event = NativeEvent(
            exceptionType = "StateError",
            message = "Ошибка 😀",
            severity = "warning",
            fatal = false,
            timestamp = "2026-11-21T00:00:00.000Z",
            issueKey = "issue-1",
            library = "flutter",
            context = "context",
            customKeys = mapOf("endpoint" to "/orders"),
            stackTrace = NativeStackTrace(
                raw = "build_id: 'abcdef'",
                frames = listOf(NativeStackFrame(
                    raw = "#00 abs 00001234 virt 00005678",
                    index = 0,
                    absoluteAddress = "00001234",
                    virtualAddress = "00005678",
                    symbol = "snapshot+0x1234",
                    isAsynchronousSuspension = false,
                )),
                needsSymbolication = true,
                buildId = "abcdef",
                os = "android",
                architecture = "arm64",
                isolateDsoBase = "1000",
                vmDsoBase = "2000",
                isolateInstructions = "3000",
                vmInstructions = "4000",
            ),
            breadcrumbs = listOf(NativeBreadcrumb(
                message = "Хлебная крошка",
                category = "test",
                level = "info",
                timestamp = "2026-11-21T00:00:00.000Z",
                data = mapOf("answer" to 42, "nullable" to null),
            )),
        )

        val stack = event.stackTrace
        val arguments = mapOf(
            "exceptionType" to event.exceptionType,
            "message" to event.message,
            "severity" to event.severity,
            "fatal" to event.fatal,
            "timestamp" to event.timestamp,
            "issueKey" to event.issueKey,
            "library" to event.library,
            "context" to event.context,
            "customKeys" to event.customKeys,
            "stackTrace" to mapOf(
                "raw" to stack.raw,
                "frames" to listOf(mapOf("raw" to "#00 abs 00001234 virt 00005678", "index" to 0,
                    "absAddress" to "00001234", "virtAddress" to "00005678", "symbol" to "snapshot+0x1234")),
                "needsSymbolication" to stack.needsSymbolication,
                "buildId" to stack.buildId,
                "os" to stack.os,
                "arch" to stack.architecture,
                "isolateDsoBase" to stack.isolateDsoBase,
                "vmDsoBase" to stack.vmDsoBase,
                "isolateInstructions" to stack.isolateInstructions,
                "vmInstructions" to stack.vmInstructions,
            ),
            "breadcrumbs" to event.breadcrumbs.map {
                mapOf(
                    "message" to it.message,
                    "category" to it.category,
                    "level" to it.level,
                    "timestamp" to it.timestamp,
                    "data" to it.data,
                )
            },
        )

        assertEquals(event, MethodCall("recordError", arguments).toNativeEvent())
    }

    @Test
    fun `typed options keep nullable and initial fields in legacy compatibility`() {
        val options = MethodCall("startCollection", mapOf(
            "nativeInitialization" to "deferred",
            "initialCustomKeys" to mapOf("tenant" to "global"),
        )).toNativeOptions()

        assertEquals("deferred", options.nativeInitialization)
        assertEquals(null, options.appToken)
        assertEquals(mapOf("tenant" to "global"), options.initialCustomKeys)
    }
}
