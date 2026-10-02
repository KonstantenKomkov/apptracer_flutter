package ru.apptracer.flutter;

/** Checks exactly the names used by the deferred adapter, including after R8. */
public final class Sdk140ReflectionTest {
    public static void main(String[] args) throws Exception {
        fields("ru.ok.tracer.utils.ChainedUncaughtExceptionHandler", "handlerBefore", "handlerAfter");
        type("ru.ok.tracer.crash.report.TracerUncaughtExceptionHandler").getConstructor();
        fields("ru.ok.tracer.Tracer", "tagsStorage", "stateStorage");
        fields("ru.ok.tracer.CoreTracerConfiguration", "initialKeys", "overrideAppTokenProvider");
        fields("ru.ok.tracer.utils.SequentialExecutor", "queue");
        fields("ru.ok.tracer.utils.SequentialExecutor$QueueRunnable", "this$0");
        fields("ru.ok.tracer.session.TagsStorage", "tagsData", "lock", "prevTagsData", "prevTagsState");
        fields("ru.ok.tracer.session.SessionStateStorage", "lock", "fileStorage", "loaded",
                "currentSystemStateData", "prevLaunchSystemStateData", "sessionStatesData",
                "currentSessionStateData", "prevLaunchSessionStateData");
        fields("ru.ok.tracer.utils.SimpleFileKeyValueStorage", "map$delegate");
        fields("ru.ok.tracer.crash.report.TracerCrashReport", "crashLoggerInternal");
        fields("ru.ok.tracer.crash.report.CrashLoggerInternal", "logStorage");
        fields("ru.ok.tracer.crash.report.LogStorage", "lock", "logsData", "prevLogsData",
                "prevLogsState", "logsFile", "logsState");
        fields("ru.ok.tracer.crash.report.LogBuf", "deque", "length");
        fields("ru.ok.tracer.crash.report.AnrWatchdogThread", "bgHandler", "mainHandler");
        state("ru.ok.tracer.session.TagsStorage$PrevTagsState", "CLEAN");
        state("ru.ok.tracer.crash.report.LogStorage$PrevLogsState", "CLEAN");
        state("ru.ok.tracer.crash.report.LogStorage$LogsState", "NONE");
        for (String initializer : new String[]{"ru.ok.tracer.utils.LoggerInitializer",
                "ru.ok.tracer.TracerInitializer", "ru.ok.tracer.crash.report.CrashReportInitializer",
                "ru.ok.tracer.nativebridge.NativeBridgeInitializer"}) {
            type(initializer).getConstructor();
        }
        // Do not initialize JNI classes while inspecting their Java signatures.
        Class<?> writer = type("ru.ok.tracer.minidump.Minidump");
        writer.getMethod("getInstance");
        writer.getMethod("uninstallMinidumpWriter");
        Object version = type("ru.ok.tracer.BuildConfig").getField("LIBRARY_VERSION").get(null);
        if (!"1.4.0".equals(version)) throw new AssertionError("unverified SDK version");
        System.out.println("Sdk140Reflection: startup, queue, buffer and writer names retained");
    }
    private static Class<?> type(String name) throws Exception {
        return Class.forName(name, false, Sdk140ReflectionTest.class.getClassLoader());
    }
    private static void fields(String type, String... names) throws Exception {
        Class<?> owner = type(type);
        for (String name : names) owner.getDeclaredField(name);
    }
    private static void state(String type, String expected) throws Exception {
        for (Object value : type(type).getEnumConstants()) {
            if (((Enum<?>) value).name().equals(expected)) return;
        }
        throw new AssertionError("missing SDK terminal state: " + type + "." + expected);
    }
}
