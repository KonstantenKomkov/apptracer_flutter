package ru.apptracer.flutter.apptracer_flutter_example

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.os.BatteryManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.TextView
import androidx.work.impl.WorkManagerImpl
import org.json.JSONArray
import org.json.JSONObject
import ru.ok.tracer.Tracer
import ru.ok.tracer.disk.usage.DiskUsage
import ru.ok.tracer.heap.dumps.HeapDumps
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Native-only runNow experiment inside the opt-in example flavor. */
@SuppressLint("RestrictedApi")
class DiagnosticsActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private val permitted = AtomicBoolean(false)
    private val destroyed = AtomicBoolean(false)
    private val workers = Executors.newFixedThreadPool(2) { r -> Thread(r, "diagnostics-runNow") }
    private val ticks = AtomicLong()
    private val maxGap = AtomicLong()
    private var lastTick = 0L
    private val invocations = java.util.Collections.synchronizedList(mutableListOf<Map<String, Any>>())
    private lateinit var label: TextView
    private val heartbeat = object : Runnable {
        override fun run() {
            val now = SystemClock.elapsedRealtime()
            if (lastTick != 0L) maxGap.updateAndGet { maxOf(it, now - lastTick) }
            lastTick = now
            ticks.incrementAndGet()
            if (!destroyed.get()) main.postDelayed(this, 16)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        label = TextView(this).apply { text = "Optional native diagnostics: preparing" }
        setContentView(label)
        main.post(heartbeat)
        Thread({ probe() }, "diagnostics-coordinator").start()
    }

    private fun requestHeap(done: CountDownLatch): Boolean {
        if (!permitted.get() || Tracer.isDisabled) return false
        workers.execute {
            try {
                // Recheck after queueing. This only closes admission: it does
                // not revoke a dump/upload already running in vendor code.
                if (permitted.get() && !Tracer.isDisabled) {
                    check(Looper.myLooper() != Looper.getMainLooper())
                    val start = SystemClock.elapsedRealtime()
                    HeapDumps.runNow("sdk161-runNow")
                    invocations.add(mapOf("thread" to Thread.currentThread().name,
                        "durationMs" to SystemClock.elapsedRealtime() - start))
                }
            } finally { done.countDown() }
        }
        return true
    }

    private fun requestDisk(): Boolean {
        if (!permitted.get() || Tracer.isDisabled) return false
        DiskUsage.runNow()
        return true
    }

    private fun work(): JSONArray {
        val database = WorkManagerImpl.getInstance(applicationContext).workDatabase
        val ids = mutableListOf<String>()
        database.query("SELECT id FROM WorkSpec", null).use { cursor ->
            while (cursor.moveToNext()) ids.add(cursor.getString(0))
        }
        return JSONArray(ids.mapNotNull { id ->
            database.workSpecDao().getWorkSpec(id)?.let { spec ->
                JSONObject().put("id", id).put("worker", spec.workerClassName)
                    .put("state", spec.state.name).put("attempts", spec.runAttemptCount)
                    .put("network", spec.constraints.requiredNetworkType.name)
                    .put("charging", spec.constraints.requiresCharging())
                    .put("idle", spec.constraints.requiresDeviceIdle())
                    .put("batteryNotLow", spec.constraints.requiresBatteryNotLow())
                    .put("intervalMs", spec.intervalDuration)
                    .put("putConstraints", spec.input.getBoolean(
                        if (spec.workerClassName.contains("ShrinkDumpWorker")) "param_put_constraints" else "put_constraints", true))
                    .put("sampleFileExists", spec.input.getString("tracer_sample_file_path")?.let { File(it).exists() })
            }
        })
    }

    private fun snapshot(stage: String, extra: JSONObject = JSONObject()) {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val connected = (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).activeNetwork != null
        val report = JSONObject().put("stage", stage).put("work", work())
            .put("connected", connected)
            .put("plugged", battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1))
            .put("uiTicks", ticks.get()).put("maxUiGapMs", maxGap.get())
            .put("invocations", JSONArray(synchronized(invocations) { invocations.map { JSONObject(it) } }))
            .put("details", extra)
        val output = File(getExternalFilesDir(null), "diagnostics.json")
        val temporary = File(output.parentFile, "diagnostics.tmp")
        temporary.writeText(report.toString(2))
        check(temporary.renameTo(output))
        main.post { if (!destroyed.get()) label.text = "Optional native diagnostics: $stage\nUI ticks: ${ticks.get()}" }
    }

    private fun objects(array: JSONArray) = (0 until array.length()).map { array.getJSONObject(it) }
    private fun probe() {
        val online = intent.getBooleanExtra("online", false)
        try {
            // Let startup install its periodic job, which must retain constraints.
            Thread.sleep(2000)
            check(!requestDisk() && !requestHeap(CountDownLatch(1)))
            val before = objects(work())
            check(before.none { it.getLong("intervalMs") == 0L })
            val periodic = before.single { it.getString("worker").contains("DiskUsageWorker") }
            check(periodic.getString("network") == "UNMETERED" && periodic.getBoolean("idle") && periodic.getBoolean("batteryNotLow"))
            snapshot("before-permission")
            val connected = (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).activeNetwork
            check((connected != null) == online) { "Device network does not match the requested phase" }
            val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))!!
            check(battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) == 0) { "Unplug simulated battery before probe" }
            Tracer.enable()
            permitted.set(true)
            val dispatched = CountDownLatch(1)
            val heaps = CountDownLatch(2)
            val dispatchTime = AtomicLong()
            val dispatchFailure = java.util.concurrent.atomic.AtomicReference<Throwable>()
            main.post {
                try {
                    val start = SystemClock.elapsedRealtime()
                    check(requestHeap(heaps) && requestHeap(heaps))
                    check(requestDisk() && requestDisk())
                    dispatchTime.set(SystemClock.elapsedRealtime() - start)
                } catch (failure: Throwable) {
                    dispatchFailure.set(failure)
                } finally { dispatched.countDown() }
            }
            check(dispatched.await(10, TimeUnit.SECONDS))
            dispatchFailure.get()?.let { throw it }
            check(heaps.await(60, TimeUnit.SECONDS))
            val deadline = SystemClock.elapsedRealtime() + 120000
            var collected = false
            while (!destroyed.get() && SystemClock.elapsedRealtime() < deadline) {
                val jobs = objects(work()).filter { it.getLong("intervalMs") == 0L }
                check(jobs.all { it.getString("network") == "NOT_REQUIRED" && !it.getBoolean("charging") })
                val disk = jobs.filter { it.getString("worker").contains("DiskUsageWorker") }
                val shrink = jobs.filter { it.getString("worker").contains("ShrinkDumpWorker") }
                if (disk.size == 2 && disk.all { it.getString("state") == "SUCCEEDED" } &&
                    shrink.size == 1 && shrink.single().getString("state") == "SUCCEEDED") {
                    check((disk + shrink).all { !it.getBoolean("putConstraints") })
                    collected = true
                    break
                }
                snapshot(if (online) "collecting-online" else "collecting-offline")
                Thread.sleep(500)
            }
            check(collected) { "Diagnostic work did not complete" }
            val details = JSONObject().put("mainDispatchMs", dispatchTime.get())
            snapshot(if (online) "collected-online" else "collected-offline", details)
            // SUCCEEDED only means the worker returned. The external HTTP sink
            // must separately prove delivery; this SDK drops samples on I/O errors.
            var uploadsFinished = false
            val uploadDeadline = SystemClock.elapsedRealtime() + 180000
            while (!destroyed.get() && SystemClock.elapsedRealtime() < uploadDeadline) {
                val jobs = objects(work()).filter { it.getLong("intervalMs") == 0L }
                val uploads = jobs.filter { it.getString("worker").contains("SampleUploadWorker") }
                if (uploads.size == 3 && uploads.all { it.getString("state") == "SUCCEEDED" }) {
                    uploadsFinished = true
                    break
                }
                Thread.sleep(1000)
            }
            check(uploadsFinished) { "Sample workers did not finish" }
            permitted.set(false)
            Tracer.disable()
            val beforeRevoke = objects(work()).map { it.getString("id") }.toSet()
            check(!requestDisk() && !requestHeap(CountDownLatch(1)))
            Thread.sleep(2000)
            check(beforeRevoke == objects(work()).map { it.getString("id") }.toSet())
            snapshot(if (online) "complete-online" else "complete-offline", details.put("prePermissionRejected", true)
                .put("postRevokeRejected", true).put("purgeSupported", false))
        } catch (failure: Throwable) {
            permitted.set(false)
            Tracer.disable()
            snapshot("error", JSONObject().put("error", failure.toString()))
        }
    }

    override fun onDestroy() {
        destroyed.set(true)
        permitted.set(false)
        main.removeCallbacks(heartbeat)
        workers.shutdown()
        super.onDestroy()
    }
}
