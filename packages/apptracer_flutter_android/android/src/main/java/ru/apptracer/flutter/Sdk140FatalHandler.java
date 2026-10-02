package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

/** Revokes and drains the SDK's synchronous Java crash writer before file cleanup. */
final class Sdk140FatalHandler implements Thread.UncaughtExceptionHandler {
    private static final String SDK_HANDLER = "ru.ok.tracer.crash.report.TracerUncaughtExceptionHandler";
    private static final String SDK_CHAIN = "ru.ok.tracer.utils.ChainedUncaughtExceptionHandler";
    private Thread.UncaughtExceptionHandler delegate;
    private final Set<Thread> startupWriters = new HashSet<>();
    private Thread.UncaughtExceptionHandler installed;
    private boolean open = true;
    private int active;

    Sdk140FatalHandler(Thread.UncaughtExceptionHandler delegate) {
        if (delegate == null) throw new NullPointerException("delegate");
        this.delegate = delegate;
    }

    static Sdk140FatalHandler attach(Thread.UncaughtExceptionHandler previous) throws Exception {
        Thread.UncaughtExceptionHandler current = Thread.getDefaultUncaughtExceptionHandler();
        Sdk140FatalHandler controlled;
        if (current != null && current.getClass().getName().equals(SDK_CHAIN)) {
            Field before = field(current, "handlerBefore");
            Object sdk = before.get(current);
            if (sdk == null || !sdk.getClass().getName().equals(SDK_HANDLER)
                    || field(current, "handlerAfter").get(current) != previous) {
                throw new IllegalStateException("unverified fatal handler chain");
            }
            controlled = new Sdk140FatalHandler((Thread.UncaughtExceptionHandler) sdk);
            // Keep the SDK chain's normal forwarding to the host/OS handler.
            // Only its diagnostic writer receives revocable admission.
            before.set(current, controlled);
            controlled.installed = current;
        } else if (current != null && previous == null && current.getClass().getName().equals(SDK_HANDLER)) {
            controlled = new Sdk140FatalHandler(current);
            if (Thread.getDefaultUncaughtExceptionHandler() != current) {
                throw new IllegalStateException("fatal handler changed during startup");
            }
            Thread.setDefaultUncaughtExceptionHandler(controlled);
            controlled.installed = controlled;
        } else {
            throw new IllegalStateException("unverified fatal handler");
        }
        // A crash may already have entered the original handler during SDK
        // startup, before its chain could be wrapped. Keep those threads until
        // they leave the inspected SDK/chain frames; they bypass our counter.
        for (java.util.Map.Entry<Thread, StackTraceElement[]> entry : Thread.getAllStackTraces().entrySet()) {
            if (inSdkHandler(entry.getValue())) controlled.startupWriters.add(entry.getKey());
        }
        return controlled;
    }

    Thread.UncaughtExceptionHandler installedHandler() { return installed; }

    @Override public void uncaughtException(Thread thread, Throwable error) {
        Thread.UncaughtExceptionHandler action;
        synchronized (this) {
            if (!open) return;
            action = delegate;
            active++;
        }
        try { action.uncaughtException(thread, error); }
        finally {
            synchronized (this) { active--; notifyAll(); }
        }
    }

    synchronized void close() { open = false; delegate = null; notifyAll(); }

    synchronized boolean awaitIdle(long timeout, TimeUnit unit) throws InterruptedException {
        if (open) throw new IllegalStateException("revoke before draining fatal writers");
        long remaining = unit.toNanos(timeout);
        if (remaining < 0) throw new IllegalArgumentException("negative timeout");
        long last = System.nanoTime();
        while (true) {
            java.util.Iterator<Thread> writers = startupWriters.iterator();
            while (writers.hasNext()) {
                if (!inSdkHandler(writers.next().getStackTrace())) writers.remove();
            }
            if (active == 0 && startupWriters.isEmpty()) return true;
            if (remaining <= 0) return false;
            // Startup writers do not signal our monitor when leaving vendor
            // code. Poll only their completion; tracked writers notify directly.
            TimeUnit.NANOSECONDS.timedWait(this, Math.min(remaining, TimeUnit.MILLISECONDS.toNanos(10)));
            long now = System.nanoTime();
            remaining -= now - last;
            last = now;
        }
    }

    private static boolean inSdkHandler(StackTraceElement[] frames) {
        for (StackTraceElement frame : frames) {
            String owner = frame.getClassName();
            if (owner.equals(SDK_HANDLER) || owner.equals(SDK_CHAIN)
                    || (owner.equals("ru.ok.tracer.crash.report.TracerCrashReport")
                        && frame.getMethodName().startsWith("reportUncaughtException"))
                    || (owner.equals("ru.ok.tracer.crash.report.CrashLoggerInternal")
                        && frame.getMethodName().equals("reportCrash"))) return true;
        }
        return false;
    }
    private static Field field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }
}
