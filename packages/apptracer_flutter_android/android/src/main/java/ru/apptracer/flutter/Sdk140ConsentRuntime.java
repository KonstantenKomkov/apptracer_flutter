package ru.apptracer.flutter;

import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import java.io.File;
import java.lang.reflect.Field;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import ru.ok.tracer.Tracer;
import ru.ok.tracer.base.process.ProcessUtils;
import ru.ok.tracer.crash.report.TracerCrashReport;
import ru.ok.tracer.startup.TracerStartup;

/** Process-scoped adapter for the inspected 1.4.0 crash/native startup graph. */
public final class Sdk140ConsentRuntime {
    public interface Completion { void complete(Map<String, String> result); }
    private static final ExecutorService cleanup = Executors.newSingleThreadExecutor();
    private static ConsentTracerApplication sdkContext;
    private static Application host;
    private static String state = "disabled";
    private static String reason;
    private static boolean irreversible;
    private static int cleanupsPending;
    private static Thread.UncaughtExceptionHandler previousHandler;
    private static Thread.UncaughtExceptionHandler sdkHandler;
    private static Sdk140FatalHandler fatalHandler;
    private static final Set<String> INITIALIZERS = new HashSet<>(Arrays.asList(
        "ru.ok.tracer.utils.LoggerInitializer", "ru.ok.tracer.TracerInitializer",
        "ru.ok.tracer.crash.report.CrashReportInitializer",
        "ru.ok.tracer.nativebridge.NativeBridgeInitializer"
    ));

    private Sdk140ConsentRuntime() { }

    public static synchronized boolean ownsRuntime() { return host != null; }

    public static synchronized Map<String, String> snapshot() {
        return result(state, reason);
    }

    public static Map<String, String> automaticSnapshot() {
        if (Tracer.isDisabled()) return result("restartRequired", null);
        try {
            Tracer.INSTANCE.getRuntimeConfigs();
        } catch (IllegalStateException notInitialized) {
            return result("disabled", "sdk_not_initialized");
        }
        if (TracerCrashReport.INSTANCE.isDisabled$tracer_crash_report_release()) {
            return result("disabled", "sdk_collection_disabled");
        }
        return result("enabled", null);
    }

    public static synchronized Map<String, String> start(Context context, boolean preservePreviousReports) {
        if (cleanupsPending != 0 || irreversible) return snapshot();
        if ("enabled".equals(state)) return snapshot();
        try {
            validateVersion();
            Application application = (Application) context.getApplicationContext();
            if (!application.getPackageName().equals(ProcessUtils.getProcessName(application))) {
                return result("unsupported", "deferred_secondary_process_unsupported");
            }
            validateInitializers(application);
            try {
                Tracer.INSTANCE.getRuntimeConfigs();
                return result("error", "sdk_already_initialized");
            } catch (IllegalStateException notInitialized) {
                // SDK's checked getter throws before initialization.
            }
            host = application;
            SharedPreferences marker = marker(application);
            if (!preservePreviousReports || marker.getBoolean("purge_required", false)) {
                clearDiagnosticRoots(application);
            }
            // The marker stores only a technical purge obligation. It is not
            // evidence of consent, account ownership or document applicability.
            if (!marker.edit().putBoolean("purge_required", false).commit()) {
                return setResult("error", "purge_marker_write_failed");
            }
            sdkContext = new ConsentTracerApplication(application);
            previousHandler = Thread.getDefaultUncaughtExceptionHandler();
            irreversible = true; // SDK initialization itself is one-shot.
            TracerStartup.init(sdkContext); // preserves vendor dependency ordering
            if (Thread.getDefaultUncaughtExceptionHandler() != previousHandler) {
                fatalHandler = Sdk140FatalHandler.attach(previousHandler);
                sdkHandler = fatalHandler.installedHandler();
            }
            if (!Tracer.isDisabled() && !TracerCrashReport.INSTANCE.isDisabled$tracer_crash_report_release()
                    && fatalHandler == null) throw new IllegalStateException("SDK fatal handler missing");
            if (Tracer.isDisabled() || TracerCrashReport.INSTANCE.isDisabled$tracer_crash_report_release()) {
                sdkContext.revoke();
                Tracer.disable();
                stopAndClear(application, ignored -> { });
                return result("error", "sdk_collection_disabled");
            }
            return setResult("enabled", null);
        } catch (Throwable failure) {
            if (sdkContext != null) {
                if (fatalHandler == null && Thread.getDefaultUncaughtExceptionHandler() != previousHandler) {
                    try {
                        fatalHandler = Sdk140FatalHandler.attach(previousHandler);
                        sdkHandler = fatalHandler.installedHandler();
                    } catch (Exception unverifiedHandler) { /* Cleanup must fail closed below. */ }
                }
                sdkContext.revoke();
                Tracer.disable();
                stopAndClear(host, ignored -> { });
                return result("error", "native_start_or_initial_cleanup_failed");
            }
            return setResult("error", "native_start_or_initial_cleanup_failed");
        }
    }

    static synchronized void executorFailed(Throwable failure) {
        if (sdkContext == null) return;
        try {
            if ("enabled".equals(state)) {
                // Uses the same persisted revocation path as an explicit stop.
                stopAndClear(host, ignored -> { });
            } else {
                // A host executor may run synchronously during startup. Close
                // admissions now; startup will finish installing collectors and
                // queue their cleanup before it can return enabled.
                if (fatalHandler != null) fatalHandler.close();
                sdkContext.revokeAdmission();
                Tracer.disable();
            }
        } catch (Throwable revocationFailure) {
            // A failure in teardown must not escape an SDK worker and become
            // another fatal exception. Cleanup remains unproven and off.
        }
        setResult("error", "native_executor_failed");
    }

    /** Called on the platform thread. Revocation precedes all asynchronous work. */
    public static synchronized void stopAndClear(Context context, Completion completion) {
        Application application = host != null ? host : (Application) context.getApplicationContext();
        try {
            validateVersion();
            if (!application.getPackageName().equals(ProcessUtils.getProcessName(application))) {
                completion.complete(result("unsupported", "deferred_secondary_process_unsupported"));
                return;
            }
            if (sdkContext == null) {
                // Without a controlled start, automatic SDK jobs cannot be
                // tracked. Never delete their files while they may be sending.
                try {
                    Tracer.INSTANCE.getRuntimeConfigs();
                    host = application;
                    irreversible = true;
                    Tracer.disable();
                    completion.complete(setResult("error", "unmanaged_native_runtime"));
                    return;
                } catch (IllegalStateException notInitialized) { }
            }
            host = application;
            if (fatalHandler != null) fatalHandler.close();
            if (sdkContext != null) sdkContext.revokeAdmission();
            boolean persisted;
            try {
                // Persist before host callback removal: a host may throw while
                // unregistering callbacks, but revocation must survive restart.
                persisted = marker(application).edit().putBoolean("purge_required", true).commit();
            } finally {
                try { if (sdkContext != null) sdkContext.revoke(); }
                finally { if (irreversible) Tracer.disable(); }
            }
            state = "disabled";
            reason = "cleanup_pending";
            cleanupsPending++;
            cleanup.execute(() -> finishStop(application, persisted, completion));
        } catch (Throwable failure) {
            completion.complete(setResult("error", "native_revocation_failed"));
        }
    }

    private static void finishStop(Application application, boolean markerPersisted, Completion completion) {
        Map<String, String> reply;
        try {
            ConsentTracerApplication controlled;
            synchronized (Sdk140ConsentRuntime.class) { controlled = sdkContext; }
            if (controlled != null) {
                if (!controlled.io.awaitIdle(30, TimeUnit.SECONDS)
                        || !controlled.background.awaitIdle(30, TimeUnit.SECONDS)) {
                    throw new IllegalStateException("native work did not drain");
                }
                if (fatalHandler != null) {
                    if (!fatalHandler.awaitIdle(30, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("Java fatal writer did not drain");
                    }
                } else if (Thread.getDefaultUncaughtExceptionHandler() != previousHandler) {
                    throw new IllegalStateException("Java fatal handler is unverified");
                }
                stopWatchdogs();
                uninstallNativeWriter();
                if (Thread.getDefaultUncaughtExceptionHandler() == sdkHandler) {
                    Thread.setDefaultUncaughtExceptionHandler(previousHandler);
                }
                Sdk140DiagnosticBuffers.clear(
                        read(Tracer.INSTANCE, "tagsStorage"), read(Tracer.INSTANCE, "stateStorage"),
                        read(TracerCrashReport.INSTANCE, "crashLoggerInternal"), controlled.coreConfiguration());
            }
            if (!markerPersisted) throw new IllegalStateException("purge marker was not persisted");
            clearDiagnosticRoots(application);
            // Keep the revocation obligation until the next authorized start.
            // A fatal/native callback that was already running may outlive this
            // purge or the process itself. Its files must not be preserved by a
            // later preservePreviousReports request after withdrawal.
            synchronized (Sdk140ConsentRuntime.class) {
                reply = setResult(irreversible ? "restartRequired" : "disabled", null);
            }
        } catch (Throwable failure) {
            synchronized (Sdk140ConsentRuntime.class) {
                reply = setResult("error", "native_stop_or_cleanup_failed");
            }
        }
        synchronized (Sdk140ConsentRuntime.class) {
            cleanupsPending--;
            if (cleanupsPending != 0) setResult("disabled", "cleanup_pending");
        }
        final Map<String, String> delivered = reply;
        new Handler(Looper.getMainLooper()).post(() -> completion.complete(delivered));
    }

    private static void stopWatchdogs() throws Exception {
        for (Thread thread : Thread.getAllStackTraces().keySet()) {
            if (!thread.getClass().getName().equals("ru.ok.tracer.crash.report.AnrWatchdogThread")) continue;
            Handler background = null;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
            while (background == null && thread.isAlive() && System.nanoTime() < deadline) {
                background = (Handler) read(thread, "bgHandler");
                if (background == null) Thread.sleep(10);
            }
            if (background != null) {
                Handler main = (Handler) read(thread, "mainHandler");
                if (main != null) main.removeCallbacksAndMessages(null);
                background.removeCallbacksAndMessages(null);
                background.getLooper().quitSafely();
            }
            thread.join(5000);
            if (thread.isAlive()) throw new IllegalStateException("ANR writer still running");
        }
    }

    private static Object read(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    private static void uninstallNativeWriter() throws Exception {
        Class<?> type;
        try { type = Class.forName("ru.ok.tracer.minidump.Minidump"); }
        catch (ClassNotFoundException javaOnly) { return; }
        Object writer = type.getMethod("getInstance").invoke(null);
        type.getMethod("uninstallMinidumpWriter").invoke(writer);
    }

    private static void validateVersion() throws Exception {
        Object version = Class.forName("ru.ok.tracer.BuildConfig").getField("LIBRARY_VERSION").get(null);
        if (!"1.4.0".equals(version)) throw new IllegalStateException("unverified SDK version");
    }

    private static void validateInitializers(Application application) throws Exception {
        ApplicationInfo info = application.getPackageManager().getApplicationInfo(
                application.getPackageName(), PackageManager.GET_META_DATA);
        Set<String> found = new HashSet<>();
        if (info.metaData != null) for (String key : info.metaData.keySet()) {
            if (!key.startsWith("ru.ok.tracer.startup.Initializer@")) continue;
            String initializer = info.metaData.getString(key);
            if (!INITIALIZERS.contains(initializer)) throw new IllegalStateException("unverified initializer");
            found.add(initializer);
        }
        if (!found.containsAll(Arrays.asList("ru.ok.tracer.utils.LoggerInitializer",
                "ru.ok.tracer.TracerInitializer", "ru.ok.tracer.crash.report.CrashReportInitializer"))) {
            throw new IllegalStateException("missing initializer metadata");
        }
    }

    private static File root(Application application) { return new File(application.getCacheDir(), "tracer"); }
    private static void clearDiagnosticRoots(Application application) throws Exception {
        // SDK 1.4.0 stores crash/session queues under cache/tracer and its
        // stable device identifier under files/tracer. Both outlive one process.
        DiagnosticFiles.clear(root(application));
        DiagnosticFiles.clear(new File(application.getFilesDir(), "tracer"));
    }

    private static SharedPreferences marker(Application application) {
        return application.getSharedPreferences("apptracer_flutter_collection", Context.MODE_PRIVATE);
    }
    private static Map<String, String> setResult(String value, String detail) {
        state = value;
        reason = detail;
        return snapshot();
    }
    private static Map<String, String> result(String value, String detail) {
        Map<String, String> reply = new HashMap<>();
        reply.put("state", value);
        if (detail != null) reply.put("reason", detail);
        return reply;
    }
}
