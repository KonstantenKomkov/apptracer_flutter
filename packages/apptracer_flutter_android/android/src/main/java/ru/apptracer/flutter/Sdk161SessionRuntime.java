package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.jvm.functions.Function0;
import ru.ok.tracer.Tracer;
import ru.ok.tracer.crash.report.TracerCrashReport;
import ru.ok.tracer.startup.TracerStartup;

/** Recreates the audited crash-only 1.6.1 graph after completed managed purge.
 * Never reopens old executors/stores. Called on main only after all old writers
 * drained and the main-queue cleanup barrier completed. No automatic-mode reset. */
final class Sdk161SessionRuntime {
    private Sdk161SessionRuntime() { }

    static void prepare() throws Exception {
        if (!"1.6.1".equals(Class.forName("ru.ok.tracer.BuildConfig")
                .getField("LIBRARY_VERSION").get(null)) || !Tracer.isDisabled()) {
            throw new IllegalStateException("restart requires a retired SDK 1.6.1");
        }
        // Resolve every private contract before mutating any SDK object.
        List<LazyReset> resets = new ArrayList<>();
        resets.add(new LazyReset("ru.ok.tracer.utils.TracerThreads", "ioExecutor"));
        resets.add(new LazyReset("ru.ok.tracer.utils.TracerThreads", "bgExecutor"));
        resets.add(new LazyReset("ru.ok.tracer.Tracer", "httpClient"));
        resets.add(new LazyReset("ru.ok.tracer.Tracer", "dropManager"));
        AtomicBoolean initialized = (AtomicBoolean) field(Tracer.class, "isInitialized").get(null);
        AtomicReference<?> previousContext = (AtomicReference<?>) field(TracerStartup.class, "prevAppContext").get(null);
        Field device = field(Class.forName("ru.ok.tracer.base.deviceid.DeviceIdUtils"), "cachedDeviceId");
        Field session = field(Class.forName("ru.ok.tracer.base.sessionuuuid.SessionUuidHolder"), "sessionUuid");
        Field configDisabled = field(TracerCrashReport.class, "isConfigDisabled");
        for (LazyReset reset : resets) reset.apply();
        device.set(null, null);
        session.set(null, UUID.randomUUID().toString());
        configDisabled.set(null, false);
        // Startup recreates configuration, tags, sessions, crash logger, native
        // writer, activity callbacks, watchdog and fatal handler in SDK order.
        previousContext.set(null);
        initialized.set(false);
    }

    /** Preserve final Lazy references; reset their synchronized mutable state.
     * Old cached values remain retired. Factories are stateless SDK singletons. */
    static final class LazyReset {
        final Lazy<?> lazy;
        final Function0<?> factory;
        final Field value;
        final Field initializer;
        final Object empty;

        LazyReset(String owner, String property) throws Exception {
            lazy = (Lazy<?>) field(Class.forName(owner), property + "$delegate").get(null);
            if (!lazy.getClass().getName().equals("kotlin.SynchronizedLazyImpl")) {
                throw new IllegalStateException("unverified SDK lazy implementation");
            }
            factory = (Function0<?>) field(Class.forName(owner + "$" + property + "$2"), "INSTANCE").get(null);
            value = field(lazy.getClass(), "_value");
            initializer = field(lazy.getClass(), "initializer");
            if (field(lazy.getClass(), "lock").get(lazy) != lazy) {
                throw new IllegalStateException("unverified SDK lazy lock");
            }
            Lazy<?> fresh = LazyKt.lazy(factory);
            empty = value.get(fresh);
        }

        void apply() throws Exception {
            synchronized (lazy) {
                initializer.set(lazy, factory);
                value.set(lazy, empty);
            }
        }
    }

    private static Field field(Class<?> type, String name) throws Exception {
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }
}
