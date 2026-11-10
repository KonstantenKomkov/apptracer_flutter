package ru.apptracer.flutter.apptracer_flutter_example;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;
import java.lang.reflect.Field;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import ru.ok.tracer.Tracer;
import ru.ok.tracer.TracerConfiguration;
import ru.ok.tracer.heap.dumps.HeapDumpConfiguration;

/** Calls the actual 1.6.1 builder/getter, not a mock implementation. */
public final class HeapDumpProviderTest {
    private Field runtimeFlag;
    private boolean previousFlag;

    @Before public void before() throws Exception {
        runtimeFlag = Tracer.class.getDeclaredField("disabledInRuntime");
        runtimeFlag.setAccessible(true);
        previousFlag = runtimeFlag.getBoolean(null);
        runtimeFlag.setBoolean(null, false);
        DiagnosticsHeapDecision.INSTANCE.getAllowed().set(false);
        DiagnosticsHeapDecision.INSTANCE.getReadThreads().clear();
    }

    @After public void after() throws Exception {
        runtimeFlag.setBoolean(null, previousFlag);
        DiagnosticsHeapDecision.INSTANCE.getAllowed().set(false);
        DiagnosticsHeapDecision.INSTANCE.getReadThreads().clear();
    }

    private static boolean enabled(HeapDumpConfiguration config) {
        return config.getEnabled$tracer_heap_dumps_release();
    }

    @Test public void buildDoesNotEvaluateAndEveryReadUsesCurrentDecision() {
        AtomicBoolean decision = new AtomicBoolean(false);
        AtomicInteger reads = new AtomicInteger();
        HeapDumpConfiguration.Builder builder = new HeapDumpConfiguration.Builder()
                .provideEnabled(() -> { reads.incrementAndGet(); return decision.get(); });
        decision.set(true); // Decided after builder creation, before build/read.
        HeapDumpConfiguration config = builder.build();
        assertEquals(0, reads.get());
        assertTrue(enabled(config));
        decision.set(false);
        assertEquals(1, reads.get()); // No subscription callback on mutation.
        assertFalse(enabled(config));
        assertFalse(enabled(config));
        assertEquals(3, reads.get());
    }

    @Test public void providerExecutesSynchronouslyOnTheReadingThread() throws Exception {
        AtomicReference<Thread> calledOn = new AtomicReference<>();
        HeapDumpConfiguration config = new HeapDumpConfiguration.Builder()
                .provideEnabled(() -> { calledOn.set(Thread.currentThread()); return true; }).build();
        AtomicBoolean result = new AtomicBoolean();
        Thread reader = new Thread(() -> result.set(enabled(config)), "provider-reader");
        reader.start();
        reader.join(5000);
        assertFalse(reader.isAlive());
        assertTrue(result.get());
        assertSame(reader, calledOn.get());
    }

    @Test public void exceptionsAndNullResultsDisableButErrorsEscape() {
        assertFalse(enabled(new HeapDumpConfiguration.Builder()
                .provideEnabled(() -> { throw new IllegalStateException("decision unavailable"); }).build()));
        assertFalse(enabled(new HeapDumpConfiguration.Builder().provideEnabled(() -> null).build()));
        AssertionError error = new AssertionError("fatal decision failure");
        try {
            enabled(new HeapDumpConfiguration.Builder().provideEnabled(() -> { throw error; }).build());
            fail("Error must not be described as an SDK-caught Exception");
        } catch (AssertionError actual) { assertSame(error, actual); }
    }

    @Test public void lastBuilderSetterWinsWithoutMutatingBuiltConfiguration() {
        HeapDumpConfiguration.Builder builder = new HeapDumpConfiguration.Builder()
                .setEnabled(false).provideEnabled(() -> true);
        HeapDumpConfiguration original = builder.build();
        assertTrue(enabled(original));
        builder.setEnabled(false);
        assertFalse(enabled(builder.build()));
        assertTrue(enabled(original));
    }

    @Test public void hostOwnsLazyConfigurationAndGlobalDisableStillWins() throws Exception {
        DiagnosticsApplication host = new DiagnosticsApplication();
        HeapDumpConfiguration heap = null;
        for (TracerConfiguration config : host.getTracerConfiguration()) {
            if (config instanceof HeapDumpConfiguration) heap = (HeapDumpConfiguration) config;
        }
        assertNotNull(heap);
        assertTrue(DiagnosticsHeapDecision.INSTANCE.getReadThreads().isEmpty());
        assertFalse(enabled(heap));
        DiagnosticsHeapDecision.INSTANCE.getAllowed().set(true);
        assertTrue(enabled(heap));
        runtimeFlag.setBoolean(null, true);
        assertFalse(enabled(heap));
        runtimeFlag.setBoolean(null, false);
        DiagnosticsHeapDecision.INSTANCE.getAllowed().set(false);
        assertFalse(enabled(heap));
    }
}
