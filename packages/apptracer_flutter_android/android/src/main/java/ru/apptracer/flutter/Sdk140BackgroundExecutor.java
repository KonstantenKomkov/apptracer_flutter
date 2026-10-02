package ru.apptracer.flutter;

import java.lang.reflect.Field;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;

/** Revokes the extra SequentialExecutor queue installed by Tracer 1.4.0. */
final class Sdk140BackgroundExecutor implements Executor {
    private final RevocableExecutor executor;
    private final RevocableExecutor.FailureHandler failures;
    private RevocableQueue queue;
    private Object scheduler;
    private boolean open = true;
    private boolean bindingFailed;

    Sdk140BackgroundExecutor(Executor delegate, RevocableExecutor.FailureHandler failures) {
        executor = new RevocableExecutor(delegate, failures);
        this.failures = failures;
    }

    @Override public void execute(Runnable command) {
        // The SDK calls this when it schedules its first queue runner, before
        // that runner reaches the host executor. Preserve the original queue:
        // copying it while SDK producers are submitting would lose work.
        IllegalStateException bindingError = null;
        synchronized (this) {
            try {
                if (!command.getClass().getName().equals(
                        "ru.ok.tracer.utils.SequentialExecutor$QueueRunnable")) {
                    throw new IllegalStateException("unverified background runner");
                }
                Field owner = command.getClass().getDeclaredField("this$0");
                owner.setAccessible(true);
                Object current = owner.get(command);
                if (scheduler == null) {
                    Field tasks = current.getClass().getDeclaredField("queue");
                    tasks.setAccessible(true);
                    Object original = tasks.get(current);
                    if (original.getClass() != ConcurrentLinkedQueue.class) {
                        throw new IllegalStateException("unverified background queue");
                    }
                    @SuppressWarnings("unchecked")
                    ConcurrentLinkedQueue<Runnable> source = (ConcurrentLinkedQueue<Runnable>) original;
                    queue = new RevocableQueue(source);
                    if (!open) queue.close();
                    tasks.set(current, queue);
                    scheduler = current;
                } else if (scheduler != current) {
                    throw new IllegalStateException("multiple background schedulers");
                }
            } catch (ReflectiveOperationException | RuntimeException failure) {
                bindingFailed = true;
                close();
                bindingError = new IllegalStateException("cannot control SDK background queue", failure);
            }
        }
        if (bindingError != null) {
            if (failures == null) throw bindingError;
            failures.failed(bindingError);
            return;
        }
        executor.execute(command);
    }

    synchronized void close() {
        open = false;
        if (queue != null) queue.close();
        executor.close();
    }

    boolean awaitIdle(long timeout, TimeUnit unit) throws InterruptedException {
        synchronized (this) {
            if (bindingFailed) throw new IllegalStateException("SDK background queue unverified");
        }
        return executor.awaitIdle(timeout, unit);
    }

    /** Only add/poll/isEmpty are used by the inspected vendor bytecode. */
    private static final class RevocableQueue extends ConcurrentLinkedQueue<Runnable> {
        private final ConcurrentLinkedQueue<Runnable> source;
        private boolean open = true;

        RevocableQueue(ConcurrentLinkedQueue<Runnable> source) { this.source = source; }

        @Override public synchronized boolean add(Runnable task) {
            if (task == null) throw new NullPointerException("task");
            return open && source.add(task);
        }
        @Override public synchronized Runnable poll() { return open ? source.poll() : null; }
        @Override public synchronized boolean isEmpty() { return !open || source.isEmpty(); }
        synchronized void close() { open = false; source.clear(); }
    }
}
