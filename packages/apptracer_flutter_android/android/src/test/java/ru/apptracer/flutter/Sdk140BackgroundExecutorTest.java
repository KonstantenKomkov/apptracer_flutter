package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.ArrayDeque;
import java.util.Queue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Runs against the vendor's real SequentialExecutor, not a reproduction. */
public final class Sdk140BackgroundExecutorTest {
    private static Executor sdk(Executor executor) throws Exception {
        return (Executor) Class.forName("ru.ok.tracer.utils.SequentialExecutor")
                .getConstructor(Executor.class).newInstance(executor);
    }

    public static void main(String[] args) throws Exception {
        queuedReportsAreReleased();
        activeRunnerCannotConsumeNextReport();
        synchronousHostWorks();
        revokeBeforeFirstTask();
        unexpectedRunnerCannotReportSuccessfulDrain();
        productionBindingFailureUsesCallback();
        System.out.println("Sdk140BackgroundExecutor: 6 vendor queue checks passed");
    }

    private static void queuedReportsAreReleased() throws Exception {
        Queue<Runnable> host = new ArrayDeque<>();
        Sdk140BackgroundExecutor controlled = new Sdk140BackgroundExecutor(host::add, null);
        Executor sdk = sdk(controlled);
        AtomicInteger sent = new AtomicInteger();
        sdk.execute(sent::incrementAndGet);
        sdk.execute(sent::incrementAndGet);
        controlled.close();
        for (int i = 0; i < 1000; i++) sdk.execute(sent::incrementAndGet);
        check(storedTasks(sdk).isEmpty(), "SDK retained revoked reports");
        host.remove().run();
        check(sent.get() == 0, "queued report ran after revoke");
        check(controlled.awaitIdle(1, TimeUnit.SECONDS), "closed pending runner not idle");
    }

    private static void activeRunnerCannotConsumeNextReport() throws Exception {
        Queue<Runnable> host = new ArrayDeque<>();
        Sdk140BackgroundExecutor controlled = new Sdk140BackgroundExecutor(host::add, null);
        Executor sdk = sdk(controlled);
        CountDownLatch entered = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        AtomicInteger sent = new AtomicInteger();
        sdk.execute(() -> {
            entered.countDown();
            try {
                if (!release.await(5, TimeUnit.SECONDS)) throw new AssertionError("test release timed out");
            } catch (InterruptedException error) { throw new AssertionError(error); }
        });
        sdk.execute(sent::incrementAndGet);
        Thread runner = new Thread(host.remove());
        runner.start();
        try {
            check(entered.await(5, TimeUnit.SECONDS), "first SDK task did not start");
            controlled.close();
            check(!controlled.awaitIdle(1, TimeUnit.MILLISECONDS), "active report falsely drained");
            sdk.execute(sent::incrementAndGet);
            check(storedTasks(sdk).isEmpty(), "active runner queue retained diagnostics");
        } finally { release.countDown(); runner.join(5000); }
        check(!runner.isAlive(), "SDK runner did not exit");
        check(sent.get() == 0, "active SDK runner consumed a subsequent revoked report");
        check(controlled.awaitIdle(1, TimeUnit.SECONDS), "runner did not drain");
    }

    private static void synchronousHostWorks() throws Exception {
        Sdk140BackgroundExecutor controlled = new Sdk140BackgroundExecutor(Runnable::run, null);
        Executor sdk = sdk(controlled);
        AtomicInteger sent = new AtomicInteger();
        sdk.execute(sent::incrementAndGet);
        controlled.close();
        sdk.execute(sent::incrementAndGet);
        check(sent.get() == 1, "synchronous host bypassed revocation");
        check(storedTasks(sdk).isEmpty(), "synchronous host retained future task");
    }

    private static void revokeBeforeFirstTask() throws Exception {
        Sdk140BackgroundExecutor controlled = new Sdk140BackgroundExecutor(Runnable::run, null);
        Executor sdk = sdk(controlled);
        AtomicInteger sent = new AtomicInteger();
        controlled.close();
        sdk.execute(sent::incrementAndGet);
        check(sent.get() == 0 && storedTasks(sdk).isEmpty(), "first late SDK task was retained");
    }

    private static void unexpectedRunnerCannotReportSuccessfulDrain() throws Exception {
        Sdk140BackgroundExecutor controlled = new Sdk140BackgroundExecutor(Runnable::run, null);
        try {
            controlled.execute(() -> { throw new AssertionError("unexpected task ran"); });
            throw new AssertionError("unexpected SDK runner accepted");
        } catch (IllegalStateException expected) { }
        try {
            controlled.awaitIdle(1, TimeUnit.SECONDS);
            throw new AssertionError("unverified queue reported drained");
        } catch (IllegalStateException expected) { }
    }

    private static void productionBindingFailureUsesCallback() throws Exception {
        AtomicInteger failures = new AtomicInteger();
        Sdk140BackgroundExecutor controlled = new Sdk140BackgroundExecutor(Runnable::run,
                error -> failures.incrementAndGet());
        controlled.execute(() -> { throw new AssertionError("unexpected task ran"); });
        check(failures.get() == 1, "binding failure did not reach lifecycle callback");
        try {
            controlled.awaitIdle(1, TimeUnit.SECONDS);
            throw new AssertionError("failed binding allowed successful purge");
        } catch (IllegalStateException expected) { }
    }

    private static Queue<?> storedTasks(Executor sdk) throws Exception {
        Field queue = sdk.getClass().getDeclaredField("queue");
        queue.setAccessible(true);
        Object gate = queue.get(sdk);
        Field source = gate.getClass().getDeclaredField("source");
        source.setAccessible(true);
        return (Queue<?>) source.get(gate);
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
