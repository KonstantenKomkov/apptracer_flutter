package ru.apptracer.verification;

/** Deliberately outside the Flutter plugin's kept namespace for R8 acceptance. */
public final class JavaCrashProbe {
    public static void crash(String runId) {
        throw new IllegalStateException("Android Java fatal verification: " + runId);
    }
}
