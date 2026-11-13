package ru.apptracer.flutter;

import android.os.Handler;
import android.os.Looper;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import javax.inject.Provider;
import ru.ok.tracer.Tracer;

/** Explicit optional SDK 1.6.1 commands; never installs modules or starts the SDK. */
public final class TracerDiagnostics {
    public interface Completion { void complete(Map<String, String> result); }
    private static volatile boolean heapEnabled;
    private static long generation;
    private static ExecutorService worker;
    private static final Provider<Boolean> heapProvider = () -> heapEnabled && !Tracer.isDisabled();

    private TracerDiagnostics() { }

    /** Install in the host's HeapDumpConfiguration.Builder.provideEnabled(...).
     * False until an authorized Dart call; evaluated synchronously by the SDK. */
    public static Provider<Boolean> heapDumpEnabledProvider() { return heapProvider; }

    static synchronized void revoke() {
        heapEnabled = false;
        generation++;
    }

    static synchronized Map<String, String> setHeapEnabled(boolean enabled) {
        if (!enabled) heapEnabled = false;
        Map<String, String> unavailable = availability();
        if (unavailable != null) return unavailable;
        try {
            Object configuration = null;
            for (Object value : Tracer.INSTANCE.getRuntimeConfigs().values()) {
                if (value.getClass().getName().equals("ru.ok.tracer.heap.dumps.HeapDumpConfiguration")) {
                    configuration = value;
                    break;
                }
            }
            if (configuration == null || read(configuration, "enabledProvider") != heapProvider) {
                return result("unsupported", "heap_provider_not_installed");
            }
            heapEnabled = enabled;
            return result("invoked", null);
        } catch (Throwable failure) {
            heapEnabled = false;
            return result("error", "heap_provider_update_failed");
        }
    }

    static synchronized void run(boolean heap, String tag, Completion completion) {
        Map<String, String> unavailable = availability();
        if (unavailable != null) { completion.complete(unavailable); return; }
        if (heap && (tag == null || tag.trim().isEmpty())) {
            completion.complete(result("error", "heap_tag_required"));
            return;
        }
        String name = heap ? "ru.ok.tracer.heap.dumps.HeapDumps" : "ru.ok.tracer.disk.usage.DiskUsage";
        final Class<?> type;
        final Object instance;
        try {
            type = Class.forName(name);
            instance = type.getField("INSTANCE").get(null);
            if (read(instance, "context") == null) {
                completion.complete(result("unsupported", "diagnostic_module_not_initialized"));
                return;
            }
        } catch (ClassNotFoundException missing) {
            completion.complete(result("unsupported", "diagnostic_module_missing"));
            return;
        } catch (Throwable failure) {
            completion.complete(result("error", "diagnostic_module_unverified"));
            return;
        }
        final long requestGeneration = generation;
        if (worker == null) worker = Executors.newSingleThreadExecutor();
        worker.execute(() -> {
            Map<String, String> reply;
            synchronized (TracerDiagnostics.class) {
                // Serialize admission with revocation, but never hold this lock
                // during a heap dump. Already running work cannot be cancelled.
                reply = requestGeneration != generation ? result("disabled", "superseded") : availability();
            }
            if (reply == null) {
                try {
                    if (heap) type.getMethod("runNow", String.class).invoke(instance, tag);
                    else type.getMethod("runNow").invoke(instance);
                    reply = result("invoked", null);
                } catch (Throwable failure) {
                    reply = result("error", "native_diagnostic_failed");
                }
            }
            final Map<String, String> delivered = reply;
            new Handler(Looper.getMainLooper()).post(() -> {
                synchronized (TracerDiagnostics.class) {
                    completion.complete(requestGeneration == generation ? delivered : result("disabled", "superseded"));
                }
            });
        });
    }

    private static Map<String, String> availability() {
        try {
            if (!"1.6.1".equals(Class.forName("ru.ok.tracer.BuildConfig").getField("LIBRARY_VERSION").get(null))) {
                return result("unsupported", "diagnostics_require_sdk_1_6_1");
            }
            if (Sdk140ConsentRuntime.ownsRuntime()) {
                return result("unsupported", "optional_diagnostics_outside_managed_cleanup");
            }
            if (!"enabled".equals(Sdk140ConsentRuntime.automaticSnapshot().get("state"))) {
                return result("disabled", "collection_disabled");
            }
            return null;
        } catch (Throwable unavailable) {
            return result("unsupported", "sdk_unavailable");
        }
    }

    private static Object read(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    private static Map<String, String> result(String state, String reason) {
        Map<String, String> result = new HashMap<>();
        result.put("state", state);
        if (reason != null) result.put("reason", reason);
        return result;
    }
}
