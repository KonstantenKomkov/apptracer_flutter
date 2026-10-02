package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class Sdk140FatalHandlerTest {
    public static void main(String[] args) throws Exception {
        revokedCallsDoNotReachWriter();
        activeWriterMustDrain();
        throwingWriterReleasesAdmission();
        actualSdkChainForwardsAfterRevocation();
        startupWriterOutsideCounterMustDrain();
        System.out.println("Sdk140FatalHandler: 5 fatal admission/drain checks passed");
    }
    private static void revokedCallsDoNotReachWriter() throws Exception {
        AtomicInteger writes = new AtomicInteger();
        Sdk140FatalHandler handler = new Sdk140FatalHandler((thread, error) -> writes.incrementAndGet());
        handler.uncaughtException(Thread.currentThread(), new RuntimeException("allowed"));
        handler.close();
        handler.uncaughtException(Thread.currentThread(), new RuntimeException("off"));
        check(writes.get() == 1 && handler.awaitIdle(1, TimeUnit.SECONDS), "off fatal reached writer");
    }
    private static void activeWriterMustDrain() throws Exception {
        CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        Sdk140FatalHandler handler = new Sdk140FatalHandler((thread, error) -> {
            entered.countDown();
            waitFor(release);
        });
        Thread writing = new Thread(() -> handler.uncaughtException(Thread.currentThread(), new RuntimeException()));
        writing.start();
        try {
            check(entered.await(5, TimeUnit.SECONDS), "writer never entered");
            handler.close();
            check(!handler.awaitIdle(1, TimeUnit.MILLISECONDS), "active fatal falsely drained");
        } finally { release.countDown(); writing.join(5000); }
        check(handler.awaitIdle(1, TimeUnit.SECONDS), "finished fatal retained admission");
    }
    private static void throwingWriterReleasesAdmission() throws Exception {
        Sdk140FatalHandler handler = new Sdk140FatalHandler((thread, error) -> { throw new IllegalStateException(); });
        boolean propagated = false;
        try { handler.uncaughtException(Thread.currentThread(), new RuntimeException()); }
        catch (IllegalStateException expected) { propagated = true; }
        check(propagated, "writer failure did not reach vendor forwarding chain");
        handler.close();
        check(handler.awaitIdle(1, TimeUnit.SECONDS), "throwing fatal held admission");
    }
    private static void actualSdkChainForwardsAfterRevocation() throws Exception {
        Thread.UncaughtExceptionHandler original = Thread.getDefaultUncaughtExceptionHandler();
        AtomicInteger forwarded = new AtomicInteger();
        Thread.UncaughtExceptionHandler host = (thread, error) -> forwarded.incrementAndGet();
        Thread.UncaughtExceptionHandler chain = chain(host);
        try {
            Thread.setDefaultUncaughtExceptionHandler(chain);
            Sdk140FatalHandler controlled = Sdk140FatalHandler.attach(host);
            check(controlled.installedHandler() == chain, "vendor chain replaced");
            controlled.close();
            chain.uncaughtException(Thread.currentThread(), new RuntimeException("off"));
            check(forwarded.get() == 1, "host fatal callback missing or duplicated");
            check(controlled.awaitIdle(1, TimeUnit.SECONDS), "closed chain retained writer");
        } finally { Thread.setDefaultUncaughtExceptionHandler(original); }
    }
    private static void startupWriterOutsideCounterMustDrain() throws Exception {
        Thread.UncaughtExceptionHandler original = Thread.getDefaultUncaughtExceptionHandler();
        Class<?> crash = Class.forName("ru.ok.tracer.crash.report.TracerCrashReport");
        Field logger = crash.getDeclaredField("crashLoggerInternal"); logger.setAccessible(true);
        Object previousLogger = logger.get(null);
        Field disabled = Class.forName("ru.ok.tracer.Tracer").getDeclaredField("isDisabled");
        disabled.setAccessible(true);
        boolean previousDisabled = disabled.getBoolean(null);
        Field configDisabled = crash.getDeclaredField("isConfigDisabled");
        configDisabled.setAccessible(true);
        boolean previousConfigDisabled = configDisabled.getBoolean(null);
        Class<?> allocator = Class.forName("sun.misc.Unsafe");
        Field singleton = allocator.getDeclaredField("theUnsafe"); singleton.setAccessible(true);
        Object fakeLogger = allocator.getMethod("allocateInstance", Class.class).invoke(singleton.get(null),
                Class.forName("ru.ok.tracer.crash.report.CrashLoggerInternal"));
        CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        AtomicInteger forwarded = new AtomicInteger();
        Thread.UncaughtExceptionHandler host = (thread, error) -> forwarded.incrementAndGet();
        Thread.UncaughtExceptionHandler chain = chain(host);
        Throwable slow = new RuntimeException("startup writer") {
            @Override public StackTraceElement[] getStackTrace() {
                entered.countDown(); waitFor(release); return super.getStackTrace();
            }
        };
        Thread writing = new Thread(() -> {
            try { chain.uncaughtException(Thread.currentThread(), slow); }
            catch (Throwable fixtureFailure) { /* Uninitialized store prevents any filesystem write. */ }
        });
        try {
            logger.set(null, fakeLogger);
            disabled.setBoolean(null, false);
            configDisabled.setBoolean(null, false);
            Thread.setDefaultUncaughtExceptionHandler(chain);
            writing.start();
            check(entered.await(5, TimeUnit.SECONDS), "real SDK fatal serializer did not enter");
            Sdk140FatalHandler controlled = Sdk140FatalHandler.attach(host);
            controlled.close();
            check(!controlled.awaitIdle(1, TimeUnit.MILLISECONDS), "startup fatal bypassed drain counter");
            release.countDown(); writing.join(5000);
            check(!writing.isAlive(), "startup writer still active");
            check(controlled.awaitIdle(1, TimeUnit.SECONDS), "finished startup writer retained");
            check(forwarded.get() == 1, "startup chain lost host forwarding");
        } finally {
            release.countDown(); writing.join(5000);
            logger.set(null, previousLogger);
            disabled.setBoolean(null, previousDisabled);
            configDisabled.setBoolean(null, previousConfigDisabled);
            Thread.setDefaultUncaughtExceptionHandler(original);
        }
    }
    private static Thread.UncaughtExceptionHandler chain(Thread.UncaughtExceptionHandler host) throws Exception {
        Thread.UncaughtExceptionHandler sdk = (Thread.UncaughtExceptionHandler) Class.forName(
                "ru.ok.tracer.crash.report.TracerUncaughtExceptionHandler").getConstructor().newInstance();
        return (Thread.UncaughtExceptionHandler) Class.forName("ru.ok.tracer.utils.ChainedUncaughtExceptionHandler")
                .getConstructor(Thread.UncaughtExceptionHandler.class, Thread.UncaughtExceptionHandler.class)
                .newInstance(sdk, host);
    }
    private static void waitFor(CountDownLatch latch) {
        try { if (!latch.await(5, TimeUnit.SECONDS)) throw new AssertionError("test release timed out"); }
        catch (InterruptedException error) { throw new AssertionError(error); }
    }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
