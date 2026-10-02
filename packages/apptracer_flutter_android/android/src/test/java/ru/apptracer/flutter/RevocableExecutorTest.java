package ru.apptracer.flutter;

import java.util.ArrayDeque;
import java.util.Queue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public class RevocableExecutorTest {
    public static void main(String[] args) throws Exception {
        RevocableExecutorTest checks = new RevocableExecutorTest();
        checks.queuedAndLaterDiagnosticsCannotRunAfterClose();
        checks.activeWorkMustFinishBeforeCleanupCanSucceed();
        checks.failingCallbackDoesNotLeaveAnActiveOperation();
        checks.synchronousHostExecutorCanRevokeWithoutDeadlock();
        checks.runningExecutorCannotClaimSafeCleanup();
        checks.sdkFailureIsDeliveredWithoutAnUncaughtHostFailure();
        System.out.println("RevocableExecutor: 6 lifecycle checks passed");
    }

    private static void assertTrue(boolean condition) {
        if (!condition) throw new AssertionError("expected true");
    }
    private static void assertFalse(boolean condition) { assertTrue(!condition); }
    private static void assertEquals(int expected, int actual) {
        if (expected != actual) throw new AssertionError("expected " + expected + ", got " + actual);
    }
    private static void fail(String message) { throw new AssertionError(message); }

    public void sdkFailureIsDeliveredWithoutAnUncaughtHostFailure() throws Exception {
        AtomicBoolean observed = new AtomicBoolean();
        RevocableExecutor executor = new RevocableExecutor(Runnable::run,
                error -> observed.set(error instanceof IllegalStateException));
        executor.execute(() -> { throw new IllegalStateException("SDK startup failure"); });
        executor.close();
        assertTrue(observed.get());
        assertTrue(executor.awaitIdle(0, TimeUnit.SECONDS));
    }

    public void runningExecutorCannotClaimSafeCleanup() throws Exception {
        RevocableExecutor executor = new RevocableExecutor(Runnable::run);
        try {
            executor.awaitIdle(0, TimeUnit.SECONDS);
            fail("an open executor must not permit cleanup");
        } catch (IllegalStateException expected) {
            executor.close();
        }
    }

    public void queuedAndLaterDiagnosticsCannotRunAfterClose() throws Exception {
        Queue<Runnable> queue = new ArrayDeque<>();
        RevocableExecutor executor = new RevocableExecutor(queue::add);
        AtomicBoolean sent = new AtomicBoolean();
        executor.execute(() -> sent.set(true));
        executor.close();
        executor.execute(() -> sent.set(true));
        assertEquals(1, queue.size());
        queue.remove().run();
        assertFalse(sent.get());
        assertTrue(executor.awaitIdle(0, TimeUnit.SECONDS));
    }

    public void activeWorkMustFinishBeforeCleanupCanSucceed() throws Exception {
        CountDownLatch running = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        RevocableExecutor executor = new RevocableExecutor(task -> new Thread(task).start());
        executor.execute(() -> {
            running.countDown();
            try { release.await(); } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            }
        });
        try {
            assertTrue(running.await(2, TimeUnit.SECONDS));
            executor.close();
            assertFalse(executor.awaitIdle(0, TimeUnit.SECONDS));
        } finally {
            release.countDown();
        }
        assertTrue(executor.awaitIdle(2, TimeUnit.SECONDS));
        assertFalse(executor.isOpen());
    }

    public void failingCallbackDoesNotLeaveAnActiveOperation() throws Exception {
        RevocableExecutor executor = new RevocableExecutor(Runnable::run);
        try {
            executor.execute(() -> { throw new IllegalStateException("SDK failure"); });
            fail("expected SDK failure");
        } catch (IllegalStateException expected) {
            executor.close();
        }
        assertTrue(executor.awaitIdle(0, TimeUnit.SECONDS));
    }

    public void synchronousHostExecutorCanRevokeWithoutDeadlock() throws Exception {
        RevocableExecutor executor = new RevocableExecutor(Runnable::run);
        executor.execute(executor::close);
        assertFalse(executor.isOpen());
        assertTrue(executor.awaitIdle(0, TimeUnit.SECONDS));
    }
}
