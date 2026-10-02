package ru.apptracer.flutter;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;

/**
 * An SDK executor whose permission can be revoked without shutting down an
 * executor owned by the host application. Queued callbacks drop their captured
 * diagnostics on close; active callbacks must drain before files can be purged.
 *
 * Closing does not establish network cancellation. A timeout must be treated as
 * a failed stop, and no cleanup may run until awaitIdle returns true.
 */
final class RevocableExecutor implements Executor {
    interface FailureHandler { void failed(Throwable error); }
    private final Executor delegate;
    private final FailureHandler failures;
    private final Set<Pending> pending = new HashSet<>();
    private boolean open = true;
    private int active;

    RevocableExecutor(Executor delegate) { this(delegate, null); }

    RevocableExecutor(Executor delegate, FailureHandler failures) {
        this.delegate = delegate;
        this.failures = failures;
    }

    @Override
    public void execute(Runnable command) {
        if (command == null) throw new NullPointerException("command");
        Pending task;
        synchronized (this) {
            if (!open) return;
            task = new Pending(command);
            pending.add(task);
        }
        try {
            // A host executor may run synchronously or reject. Never call it
            // under our monitor: revoke must remain available while it runs.
            delegate.execute(task);
        } catch (RuntimeException | Error error) {
            synchronized (this) {
                pending.remove(task);
                task.command = null;
            }
            throw error;
        }
    }

    synchronized void close() {
        open = false;
        for (Pending task : pending) task.command = null;
        pending.clear();
        notifyAll();
    }

    synchronized boolean isOpen() {
        return open;
    }

    synchronized boolean awaitIdle(long timeout, TimeUnit unit)
            throws InterruptedException {
        if (open) throw new IllegalStateException("revoke before draining");
        long remaining = unit.toNanos(timeout);
        if (remaining < 0) throw new IllegalArgumentException("negative timeout");
        long last = System.nanoTime();
        while (active != 0) {
            if (remaining <= 0) return false;
            TimeUnit.NANOSECONDS.timedWait(this, remaining);
            long now = System.nanoTime();
            remaining -= now - last;
            last = now;
        }
        return true;
    }

    private final class Pending implements Runnable {
        private Runnable command;

        Pending(Runnable command) {
            this.command = command;
        }

        @Override
        public void run() {
            Runnable action;
            synchronized (RevocableExecutor.this) {
                pending.remove(this);
                action = command;
                command = null;
                if (!open || action == null) return;
                active++;
            }
            try {
                action.run();
            } catch (RuntimeException | Error error) {
                if (failures == null) throw error;
                failures.failed(error);
            } finally {
                synchronized (RevocableExecutor.this) {
                    active--;
                    RevocableExecutor.this.notifyAll();
                }
            }
        }
    }
}
