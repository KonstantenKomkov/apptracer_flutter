package ru.apptracer.flutter;

import android.app.Application;
import android.content.Context;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import ru.ok.tracer.CoreTracerConfiguration;
import ru.ok.tracer.HasTracerConfiguration;
import ru.ok.tracer.TracerConfiguration;

/** SDK-only context; the host's actual Application and manifest are unchanged. */
final class ConsentTracerApplication extends Application implements HasTracerConfiguration {
    private final Application host;
    private final List<TracerConfiguration> configurations;
    private final CoreTracerConfiguration controlledCore;
    private final Sdk140Endpoint endpoint;
    private final List<ActivityLifecycleCallbacks> callbacks = new ArrayList<>();
    private final List<ExecutorService> ownedExecutors = new ArrayList<>();
    final RevocableExecutor io;
    final Sdk140BackgroundExecutor background;
    private boolean collecting = true;

    ConsentTracerApplication(Application host) {
        this.host = host;
        attachBaseContext(host);
        List<TracerConfiguration> supplied = host instanceof HasTracerConfiguration
                ? ((HasTracerConfiguration) host).getTracerConfiguration()
                : TracerAutoConfig.defaultConfigurations();
        if (supplied == null) throw new IllegalStateException("null Tracer configuration");
        CoreTracerConfiguration core = null;
        List<TracerConfiguration> combined = new ArrayList<>();
        for (TracerConfiguration config : supplied) {
            if (config instanceof CoreTracerConfiguration) {
                if (core != null) throw new IllegalStateException("duplicate core configuration");
                core = (CoreTracerConfiguration) config;
            } else combined.add(config);
        }
        if (core == null) core = new CoreTracerConfiguration.Builder().build();
        final CoreTracerConfiguration original = core;
        io = new RevocableExecutor(executor(core.getIoExecutor$tracer_commons_release(), false),
                Sdk140ConsentRuntime::executorFailed);
        background = new Sdk140BackgroundExecutor(executor(core.getBgExecutor$tracer_commons_release(), true),
                Sdk140ConsentRuntime::executorFailed);
        endpoint = new Sdk140Endpoint(io, original::getApiUrl);
        // Copy every 1.4.0 core field. Providers remain dynamic; no token is
        // copied to Dart, a log or a separate persistent store.
        CoreTracerConfiguration.Builder builder = new CoreTracerConfiguration.Builder()
                .provideApiUrl(endpoint::get)
                .provideOverrideAppToken(original::getOverrideAppToken)
                .setDebugUpload(core.getDebugUpload())
                .setExperimentalMaxKeysCount(core.getMaxKeysCount$tracer_commons_release())
                .setInitialKeys(core.getInitialKeys$tracer_commons_release())
                .setTrafficStatsTag(core.getTrafficStatsTag$tracer_commons_release())
                .setIoExecutor(io)
                .setBgExecutor(background);
        if (core.getOverrideEnvironment$tracer_commons_release() != null) {
            builder.setOverrideEnvironment(core.getOverrideEnvironment$tracer_commons_release());
        }
        controlledCore = builder.build();
        combined.add(controlledCore);
        configurations = Collections.unmodifiableList(combined);
    }

    CoreTracerConfiguration coreConfiguration() { return controlledCore; }

    private Executor executor(Executor supplied, boolean sequential) {
        if (supplied != null) return supplied;
        ExecutorService created = sequential ? Executors.newSingleThreadExecutor()
                : Executors.newCachedThreadPool();
        ownedExecutors.add(created);
        return created;
    }

    @Override public Context getApplicationContext() { return this; }
    @Override public List<TracerConfiguration> getTracerConfiguration() { return configurations; }

    @Override public synchronized void registerActivityLifecycleCallbacks(ActivityLifecycleCallbacks callback) {
        if (!collecting) return;
        callbacks.add(callback);
        host.registerActivityLifecycleCallbacks(callback);
    }

    @Override public synchronized void unregisterActivityLifecycleCallbacks(ActivityLifecycleCallbacks callback) {
        callbacks.remove(callback);
        host.unregisterActivityLifecycleCallbacks(callback);
    }

    synchronized void revokeAdmission() {
        collecting = false;
        io.close();
        endpoint.revoke();
        background.close();
    }

    synchronized void revoke() {
        revokeAdmission();
        for (ActivityLifecycleCallbacks callback : callbacks) {
            host.unregisterActivityLifecycleCallbacks(callback);
        }
        callbacks.clear();
        // Executor services created here belong to the plugin. Never shut down
        // the host's executors; closing the wrappers releases queued payloads.
        for (ExecutorService executor : ownedExecutors) executor.shutdown();
    }
}
