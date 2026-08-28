package ru.apptracer.flutter;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ru.ok.tracer.Tracer;
import ru.ok.tracer.TracerConfiguration;
import ru.ok.tracer.TracerFeature;
import ru.ok.tracer.crash.report.CrashReportConfiguration;

/**
 * The Tracer configuration this package applies on its own, and the one way of
 * applying it that does not ask the host application for a line of manifest.
 *
 * <h3>What it turns on, and why that one thing</h3>
 *
 * The non-fatal rate limit, which the vendor recommends and which matters more
 * here than in a native application. Every Dart error this package reports is a
 * non-fatal, and the SDK's hard default is <b>8 non-fatals per session</b>
 * ({@code LIMIT_MAX_NON_FATALS_PER_SESSION}); the limit raises that to 10 per
 * hour. An application that hits the cap loses errors silently, which is the
 * failure mode a crash reporter can least afford.
 *
 * <p>Nothing else is set. {@code setDebugUpload} would start sending from debug
 * builds, and {@code setSendAnr} costs an ANR watchdog — both are decisions for
 * the application, not for a wrapper.
 *
 * <h3>How it reaches the SDK</h3>
 *
 * {@code Tracer} reads configuration off the {@code Application} object and
 * only from there: {@code Tracer.init} checks whether it implements
 * {@code HasTracerConfiguration} and otherwise logs "Application does not
 * implement HasTracerConfiguration". A Flutter plugin is not the
 * {@code Application}, and by the time a Flutter engine exists the SDK has long
 * been initialized — its own {@code InitializationProvider} runs before
 * {@code Application.onCreate}.
 *
 * <p>What {@code Tracer.init} actually does, though, is <i>write</i> the
 * configuration into a field, and only when the {@code Application} implements
 * the interface; otherwise it leaves whatever the field already holds. The
 * crash-report module reads that field afterwards, when it builds the token
 * bucket that enforces the non-fatal limit. So a configuration written before
 * the SDK's provider runs survives and takes effect —
 * {@link TracerAutoConfigProvider} does exactly that, ordered ahead by
 * {@code android:initOrder}.
 *
 * <p>The precedence that falls out of this is the one we want: an application
 * with its own {@code Application} implementing {@code HasTracerConfiguration}
 * overwrites this map wholesale, and its list wins. That is why
 * {@link TracerApplication} still exists — subclassing it keeps the rate limit
 * while adding to the list.
 *
 * <h3>Why this file is Java</h3>
 *
 * The setter is {@code internal} in Kotlin, so its JVM name carries a
 * {@code $tracer_commons_release} suffix that Kotlin has no way to spell but
 * Java takes as an ordinary identifier. It is called directly rather than
 * reflectively on purpose: R8 renames the SDK's members in a minified build and
 * rewrites this call site along with them, while a name looked up as a string
 * would break there and only there.
 *
 * <p>Being non-public API, it may disappear in a future SDK version. It fails as
 * a {@code NoSuchMethodError} on the very first call, at process start, which
 * {@link TracerAutoConfigProvider} swallows: the integration then behaves
 * exactly as it did before this class existed, and naming
 * {@link TracerApplication} in the manifest brings the limit back.
 *
 * <p>The configuration is built through {@code Builder} rather than the SDK's
 * {@code build {}} helper for a second reason: that helper is an inline function
 * compiled for JVM target 11, and inlining it would force every consumer of this
 * plugin to compile for 11 as well.
 */
public final class TracerAutoConfig {

    private TracerAutoConfig() {
    }

    /**
     * The configuration this package applies when the application writes none
     * of its own. Also the list {@link TracerApplication} exposes, so that
     * "what the package turns on" is written down once.
     */
    public static List<TracerConfiguration> defaultConfigurations() {
        return Collections.<TracerConfiguration>singletonList(
                new CrashReportConfiguration.Builder()
                        .setExperimentalNonFatalRateLimitEnabled(Boolean.TRUE)
                        .build()
        );
    }

    /**
     * Publishes {@link #defaultConfigurations()} to the SDK.
     *
     * <p>Does nothing once {@code Tracer} is initialized, which is not merely a
     * missed opportunity but a guard: past that point the map may already hold
     * the application's own configuration, and overwriting it would silently
     * drop settings the application asked for.
     *
     * @return whether the configuration was written.
     */
    public static boolean install() {
        if (isTracerInitialized()) {
            return false;
        }

        List<TracerConfiguration> configurations = defaultConfigurations();
        Map<TracerFeature, TracerConfiguration> byFeature =
                new LinkedHashMap<TracerFeature, TracerConfiguration>(configurations.size());
        for (TracerConfiguration configuration : configurations) {
            byFeature.put(configuration.getFeature(), configuration);
        }

        Tracer.INSTANCE.setRuntimeConfigs$tracer_commons_release(byFeature);
        return true;
    }

    /**
     * Asks the SDK whether it has been initialized, in the only way it answers:
     * the getter throws {@code IllegalStateException("Tracer is not
     * initialized")} until {@code Tracer.init} has run.
     */
    private static boolean isTracerInitialized() {
        try {
            Tracer.INSTANCE.getRuntimeConfigs();
            return true;
        } catch (IllegalStateException notInitializedYet) {
            return false;
        }
    }
}
