package ru.apptracer.verification

/** Preserve a real obfuscated Kotlin call site for console symbolication checks. */
object KotlinCrashProbe {
    fun crash(runId: String): Nothing {
        throw IllegalStateException("Android Kotlin fatal verification: $runId")
    }
}
