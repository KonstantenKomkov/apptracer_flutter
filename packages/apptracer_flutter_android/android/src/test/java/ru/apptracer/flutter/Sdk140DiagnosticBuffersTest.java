package ru.apptracer.flutter;

import java.io.File;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Lazy;
import ru.ok.tracer.utils.SimpleFileKeyValueStorage;

/** Real vendor stores populated without starting Android collectors. */
public final class Sdk140DiagnosticBuffersTest {
    public static void main(String[] args) throws Exception {
        loadedStoresAreRetired();
        uninitializedStoreIsNotLoaded();
        incompatibleStoreFails();
        System.out.println("Sdk140DiagnosticBuffers: 3 vendor store checks passed");
    }

    private static void loadedStoresAreRetired() throws Exception {
        Object tags = empty("ru.ok.tracer.session.TagsStorage");
        put(tags, "lock", new Object());
        Collection<String> values = new ArrayList<>(Arrays.asList("user=old", "screen=old"));
        put(tags, "tagsData", values);
        put(tags, "prevTagsData", Collections.singletonList("previous-user"));
        Object logs = empty("ru.ok.tracer.crash.report.LogStorage");
        put(logs, "lock", new Object());
        Object buf = Class.forName("ru.ok.tracer.crash.report.LogBuf").getConstructor().newInstance();
        java.lang.reflect.Method add = Arrays.stream(buf.getClass().getMethods())
                .filter(method -> method.getName().equals("addLast"))
                .findFirst().orElseThrow(() -> new AssertionError("SDK log insertion method missing"));
        Object log = empty(add.getParameterTypes()[0]);
        for (Field payload : log.getClass().getDeclaredFields()) {
            if (java.lang.reflect.Modifier.isStatic(payload.getModifiers())) continue;
            payload.setAccessible(true);
            if (payload.getType() == byte[].class) payload.set(log, new byte[]{1, 2, 3});
            if (payload.getType() == int.class) payload.set(log, 12);
        }
        add.invoke(buf, log);
        check(!get(buf, "length").equals(0), "log fixture has no bytes to erase");
        put(logs, "logsData", buf);
        put(logs, "prevLogsData", Collections.singletonList(log));
        put(logs, "logsFile", new File("unused-report-path"));
        Object crash = empty("ru.ok.tracer.crash.report.CrashLoggerInternal");
        put(crash, "logStorage", logs);
        SimpleFileKeyValueStorage files = new SimpleFileKeyValueStorage(
                () -> new File("/nonexistent-apptracer-test-report"));
        files.putString("session_system_state", "old-account-json");
        Object sessions = session(files);
        // These model names may be obfuscated: the plugin reflects the store
        // fields, not model internals. Resolve the fixture types from those fields.
        Object system = empty(field(sessions, "currentSystemStateData").getType());
        Object oldSession = empty(field(sessions, "currentSessionStateData").getType());
        populateIdentity(system);
        populateIdentity(oldSession);
        put(sessions, "currentSystemStateData", system);
        put(sessions, "prevLaunchSystemStateData", system);
        put(sessions, "currentSessionStateData", oldSession);
        put(sessions, "prevLaunchSessionStateData", oldSession);
        put(sessions, "sessionStatesData", Collections.singletonList(oldSession));
        Object core = empty("ru.ok.tracer.CoreTracerConfiguration");
        put(core, "initialKeys", Collections.singletonMap("user", "old-account"));
        Sdk140DiagnosticBuffers.clear(tags, sessions, crash, core);
        check(values.isEmpty() && get(tags, "prevTagsData") == null, "native tags retained");
        check(((Enum<?>) get(tags, "prevTagsState")).name().equals("CLEAN"), "previous tags can reload");
        check(((Collection<?>) get(buf, "deque")).isEmpty(), "native logs retained");
        check(get(buf, "length").equals(0), "log buffer length retained");
        check(get(logs, "prevLogsData") == null, "previous native logs retained");
        check(((Enum<?>) get(logs, "prevLogsState")).name().equals("CLEAN"), "previous logs can reload");
        for (String name : Arrays.asList("currentSystemStateData", "prevLaunchSystemStateData",
                "currentSessionStateData", "prevLaunchSessionStateData")) {
            check(get(sessions, name) == null, "session retained: " + name);
        }
        check(((Collection<?>) get(sessions, "sessionStatesData")).isEmpty(), "session history retained");
        Lazy<?> map = (Lazy<?>) get(files, "map$delegate");
        check(((Map<?, ?>) ((AtomicReference<?>) map.getValue()).get()).isEmpty(), "file cache retained diagnostics");
        check(((Map<?, ?>) get(core, "initialKeys")).isEmpty(), "SDK initial keys retained");
        Sdk140DiagnosticBuffers.clear(tags, sessions, crash, core); // repeat remains safe
    }

    private static void uninitializedStoreIsNotLoaded() throws Exception {
        AtomicInteger reads = new AtomicInteger();
        SimpleFileKeyValueStorage files = new SimpleFileKeyValueStorage(() -> {
            reads.incrementAndGet();
            throw new AssertionError("cleanup loaded persisted diagnostics");
        });
        Object sessions = session(files);
        Sdk140DiagnosticBuffers.clear(null, sessions, null, null);
        check(reads.get() == 0, "erasure touched disk supplier");
        check(!((Lazy<?>) get(files, "map$delegate")).isInitialized(), "erasure initialized file cache");
        check(get(sessions, "loaded").equals(true), "retired session store can reload");
    }

    private static void incompatibleStoreFails() throws Exception {
        try {
            Sdk140DiagnosticBuffers.clear(new Object(), null, null, null);
            throw new AssertionError("unknown store accepted as cleaned");
        } catch (IllegalStateException expected) { }
    }

    private static Object session(SimpleFileKeyValueStorage files) throws Exception {
        Object sessions = empty("ru.ok.tracer.session.SessionStateStorage");
        put(sessions, "lock", new Object());
        put(sessions, "fileStorage", files);
        return sessions;
    }
    private static void populateIdentity(Object model) throws Exception {
        for (Field data : model.getClass().getDeclaredFields()) {
            if (java.lang.reflect.Modifier.isStatic(data.getModifiers())) continue;
            data.setAccessible(true);
            if (data.getType() == String.class) data.set(model, "old-account-diagnostic");
            if (data.getType() == Map.class) data.set(model, Collections.singletonMap("userId", "old-account"));
        }
    }
    private static Object empty(String type) throws Exception { return empty(Class.forName(type)); }
    private static Object empty(Class<?> type) throws Exception {
        // Test-only allocation avoids Android constructors/collectors. Objects
        // and their fields still come from the vendor JAR, not fixture classes.
        Class<?> allocator = Class.forName("sun.misc.Unsafe");
        Field singleton = allocator.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        return allocator.getMethod("allocateInstance", Class.class)
                .invoke(singleton.get(null), type);
    }
    private static Field field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }
    private static Object get(Object target, String name) throws Exception { return field(target, name).get(target); }
    private static void put(Object target, String name, Object value) throws Exception { field(target, name).set(target, value); }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
