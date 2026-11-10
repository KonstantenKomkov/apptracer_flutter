package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicBoolean;
import ru.ok.tracer.Tracer;
import ru.ok.tracer.crash.report.CrashReportConfiguration;
import ru.ok.tracer.crash.report.TracerCrashReport;
import ru.ok.tracer.utils.Logger;
import ru.ok.tracer.utils.TracerLoggerDelegate;

/** Run the compiled adapter with each audited, unoptimized vendor runtime. */
public final class SdkRuntimeEnableTest {
    public static void main(String[] args) throws Exception {
        String version = (String) Class.forName("ru.ok.tracer.BuildConfig")
                .getField("LIBRARY_VERSION").get(null);
        if (!java.util.Arrays.asList("1.4.0", "1.5.2", "1.6.1").contains(version)) {
            throw new AssertionError("Unaudited runtime: " + version);
        }
        Class.forName("ru.ok.tracer.base.apptoken.AppTokenUtils")
                .getMethod("isTracerBuildDisabled", android.content.Context.class);
        boolean resumable = "1.6.1".equals(version);
        Field disabled = field(Tracer.class, resumable ? "disabledInRuntime" : "isDisabled");
        Field configs = field(Tracer.class, "runtimeConfigs");
        Field configDisabled = field(TracerCrashReport.class, "isConfigDisabled");
        AtomicBoolean initialized = (AtomicBoolean) field(Tracer.class, "isInitialized").get(null);
        boolean wasInitialized = initialized.getAndSet(true);
        boolean wasDisabled = disabled.getBoolean(null);
        boolean wasConfigDisabled = configDisabled.getBoolean(null);
        Object previousConfigs = configs.get(null);
        TracerLoggerDelegate previousLogger = Logger.INSTANCE.getDelegate$tracer_commons_release();
        try {
            Logger.INSTANCE.setDelegate$tracer_commons_release(new TracerLoggerDelegate() {
                public int getMinLogPriority() { return Integer.MAX_VALUE; }
                public void println(int priority, String message, Throwable error) { }
            });
            CrashReportConfiguration config = new CrashReportConfiguration.Builder().setEnabled(true).build();
            configs.set(null, Collections.singletonMap(config.getFeature(), config));
            configDisabled.setBoolean(null, false);
            Tracer.disable();
            String expected = resumable ? "enabled" : "restartRequired";
            String actual = Sdk140ConsentRuntime.resumeRuntime().get("state");
            if (!expected.equals(actual) || Tracer.isDisabled() == resumable) {
                throw new AssertionError("Unexpected resume for " + version + ": " + actual);
            }
            System.out.println("SdkRuntimeEnable: " + version + " -> " + actual);
        } finally {
            configs.set(null, previousConfigs);
            configDisabled.setBoolean(null, wasConfigDisabled);
            disabled.setBoolean(null, wasDisabled);
            initialized.set(wasInitialized);
            Logger.INSTANCE.setDelegate$tracer_commons_release(previousLogger);
        }
    }

    private static Field field(Class<?> type, String name) throws Exception {
        Field result = type.getDeclaredField(name);
        result.setAccessible(true);
        return result;
    }
}
