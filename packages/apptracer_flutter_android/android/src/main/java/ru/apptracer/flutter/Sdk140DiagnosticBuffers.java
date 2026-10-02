package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.Collection;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Lazy;

/** Terminal cleanup of inspected SDK 1.4.0 stores after all writers have stopped. */
final class Sdk140DiagnosticBuffers {
    private Sdk140DiagnosticBuffers() { }

    static void clear(Object tags, Object sessions, Object crashLogger, Object core) throws Exception {
        if (tags != null) clearTags(tags);
        if (sessions != null) clearSessions(sessions);
        if (crashLogger != null) {
            requireType(crashLogger, "ru.ok.tracer.crash.report.CrashLoggerInternal");
            Object logs = read(crashLogger, "logStorage");
            if (logs != null) clearLogs(logs);
        }
        if (core != null) {
            requireType(core, "ru.ok.tracer.CoreTracerConfiguration");
            // build() copies initialKeys. Replace that SDK-owned copy; never
            // mutate a host's original configuration or a singleton empty map.
            write(core, "initialKeys", Collections.emptyMap());
            // This copied callback retains the original host Core config.
            // The retired SDK must release that reference as well.
            write(core, "overrideAppTokenProvider", null);
        }
    }

    private static void clearTags(Object storage) throws Exception {
        requireType(storage, "ru.ok.tracer.session.TagsStorage");
        Collection<?> current = (Collection<?>) read(storage, "tagsData");
        synchronized (current) { current.clear(); }
        synchronized (read(storage, "lock")) {
            write(storage, "prevTagsData", null);
            terminalState(storage, "prevTagsState", "CLEAN");
        }
    }

    private static void clearLogs(Object storage) throws Exception {
        requireType(storage, "ru.ok.tracer.crash.report.LogStorage");
        synchronized (read(storage, "lock")) {
            Object buffer = read(storage, "logsData");
            requireType(buffer, "ru.ok.tracer.crash.report.LogBuf");
            Collection<?> deque = (Collection<?>) read(buffer, "deque");
            // LogBuf locks the deque, rather than the LogStorage monitor.
            synchronized (deque) {
                deque.clear();
                write(buffer, "length", 0);
            }
            write(storage, "prevLogsData", null);
            terminalState(storage, "prevLogsState", "CLEAN");
            write(storage, "logsFile", null);
            terminalState(storage, "logsState", "NONE");
        }
    }

    private static void clearSessions(Object storage) throws Exception {
        requireType(storage, "ru.ok.tracer.session.SessionStateStorage");
        synchronized (read(storage, "lock")) {
            Object files = read(storage, "fileStorage");
            requireType(files, "ru.ok.tracer.utils.SimpleFileKeyValueStorage");
            Lazy<?> map = (Lazy<?>) read(files, "map$delegate");
            // Never load disk diagnostics as a side effect of erasing memory.
            if (map.isInitialized()) {
                AtomicReference<?> reference = (AtomicReference<?>) map.getValue();
                @SuppressWarnings("unchecked")
                AtomicReference<Object> values = (AtomicReference<Object>) reference;
                values.set(Collections.emptyMap());
            }
            write(storage, "currentSystemStateData", null);
            write(storage, "prevLaunchSystemStateData", null);
            write(storage, "sessionStatesData", Collections.emptyList());
            write(storage, "currentSessionStateData", null);
            write(storage, "prevLaunchSessionStateData", null);
            // This SDK instance is retired permanently. Its stores cannot be
            // initialized from reports again; another start requires a process.
            write(storage, "loaded", true);
        }
    }

    private static void terminalState(Object target, String name, String state) throws Exception {
        Field field = field(target, name);
        for (Object value : field.getType().getEnumConstants()) {
            if (((Enum<?>) value).name().equals(state)) { field.set(target, value); return; }
        }
        throw new IllegalStateException("unverified storage state");
    }

    private static void requireType(Object value, String expected) {
        if (value == null || !value.getClass().getName().equals(expected)) {
            throw new IllegalStateException("unverified SDK diagnostic store");
        }
    }
    private static Field field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }
    private static Object read(Object target, String name) throws Exception { return field(target, name).get(target); }
    private static void write(Object target, String name, Object value) throws Exception { field(target, name).set(target, value); }
}
