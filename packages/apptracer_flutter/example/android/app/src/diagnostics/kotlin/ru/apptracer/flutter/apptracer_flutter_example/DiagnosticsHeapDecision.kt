package ru.apptracer.flutter.apptracer_flutter_example

import ru.ok.tracer.Tracer
import ru.ok.tracer.heap.dumps.HeapDumpConfiguration
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

/** A cheap synchronous decision, not a subscription or an asynchronous fetch. */
object DiagnosticsHeapDecision {
    val allowed = AtomicBoolean(false)
    val readThreads = CopyOnWriteArrayList<String>()

    fun configuration(): HeapDumpConfiguration = HeapDumpConfiguration.Builder()
        .provideEnabled {
            // Instrumentation belongs only to this verification fixture.
            readThreads.add(Thread.currentThread().name)
            allowed.get() && !Tracer.isDisabled
        }
        .build()
}
