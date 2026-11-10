# Optional Android diagnostics — SDK 1.6.1

Task Android №16, verified 2026-11-10 on an ARM64 API 35 emulator with a
minified release APK. [Machine-readable evidence](android-sdk-1.6.1-diagnostics.json)
records the APK SHA-256, toolchain, WorkSpecs, UI measurements and local HTTP
request sizes/hashes. This is not Tracer console acceptance.

## Isolated example configuration

`-Ptracer.diagnostics=true -Ptracer.enabled=true` adds a `diagnostics` flavor
with its own application ID, native `DiagnosticsActivity`, host configuration,
HeapDumps, DiskUsage and WorkManager 2.7.1. The default example and published
Flutter packages gain no optional dependency or public Dart diagnostic API.
The host supplies its own `HasTracerConfiguration`; crash collection is disabled
in this experiment. The disk interesting-size threshold is lowered to one byte
**only in this fixture**, so the small synthetic application produces samples.

The application disables the SDK before its providers run; the activity rejects
manual calls until permission is granted. Disk's periodic job is installed but
retains its idle/unmetered/battery constraints. Runtime admission is rechecked
before a queued heap call. After withdrawal, new wrapper requests are rejected.
This is an experimental process-local gate, **not supported consent/purge**:

- WorkManager owns a persistent database, executors and retry/scheduling state
  outside the crash adapter's controlled executors.
- Disk, shrink and sample-upload workers check global disable on entry, but
  that does not revoke work which has already passed the check or erase jobs.
- Heap dumping has synchronous file writes; sample uploads can already be in
  flight when a flag changes. Disabling a flag is not an atomic purge barrier.
- Startup can recover existing heap files; periodic work survives independently.

The build rejects combining this flavor with `tracer.deferred=true`. The
production deferred adapter's initializer allowlist also rejects heap/disk
initializers. No stop/clear guarantee is extended to these modules.

## Observed execution and delivery

| Operation | Manual `runNow` | Periodic/default behavior |
| --- | --- | --- |
| DiskUsage | Two calls created two independent one-time workers; each completed offline/unplugged, `put_constraints=false` | One daily job retained `UNMETERED`, device-idle and battery-not-low constraints with production `debugUpload=false` |
| HeapDumps | Two concurrent calls yielded one dump/shrink/upload sequence; the other call was rejected by the SDK's atomic admission flag | No general periodic behavior change inferred; startup recovery passes constraints onward |
| Shrink/upload work | One-time WorkSpecs had `NOT_REQUIRED` network and no charging requirement, including subsequent sample-upload workers | The manual override does not remove periodic disk constraints |

`DiskUsage.runNow()` queues WorkManager work; it does not return a completed
report. `HeapDumps.runNow(tag)` synchronously creates an hprof on its calling
thread before scheduling shrink/upload work. The host wrapper uses
`diagnostics-runNow` executor threads and reports admission only, not success.
The SDK's void API supplies neither a completion result nor a per-request ID.

**Moving heap dumping off the UI thread does not eliminate UI pauses.** In the
final offline/online runs the main-loop heartbeat gaps reached **3934/4523 ms**;
main-thread dispatch wall times overlapped the same VM pause (3916/4506 ms).
Both actual heap API invocations ran on the background executor. This result
does not satisfy a blanket promise of uninterrupted UI: a heap dump can stop
managed threads. Call it only where that latency is acceptable; this example
does not expose a default user-facing dump button.

Execution and delivery were tested separately:

1. Wi-Fi and mobile data disabled, simulated battery unplugged, loopback sink
   absent. Two disk workers and one shrink worker completed. Three upload workers
   returned `SUCCEEDED` with one attempt; their input sample files no longer
   existed. Bytecode confirms that `SampleUploadWorker` catches an I/O exception,
   deletes its sample and returns success. **No offline delivery/retry guarantee
   follows from removing constraints.**
2. Network restored, battery still unplugged, a fresh process/data set and local
   sink started. New diagnostics produced exactly two `DISK_USAGE` uploads and
   one `HEAP_DUMP` upload, each preceded by `initUpload`. Both disk bodies were
   667 bytes; the heap body was 7,903,518 bytes. This tests newly collected data
   after recovery, not replay of the discarded offline samples.
3. Requests before permission and after withdrawal were rejected. No additional
   WorkSpec appeared after withdrawal. This establishes the fixture's admission
   gate, not cleanup or cancellation of already running optional work.

Initial testing also demonstrated the default DiskUsage size filter: workers
can succeed without producing any sample. The final fixture lowers that filter
and requires actual per-feature upload bodies; worker success alone is never
accepted as proof of delivery.

## Reproduce

From `packages/apptracer_flutter/example`, prepare Flutter's release registrant:

```sh
flutter build apk --release --config-only \
  --target=lib/android_native_verification.dart --target-platform=android-arm64 \
  --android-skip-build-dependency-validation
cd android
TRACER_APP_TOKEN=android-sdk161-build-placeholder \
TRACER_PLUGIN_TOKEN=android-sdk161-plugin-placeholder \
./gradlew :app:assembleDiagnosticsRelease \
  -Ptracer.enabled=true -Ptracer.diagnostics=true \
  -Ptarget=lib/android_native_verification.dart -Ptarget-platform=android-arm64 \
  -PskipDependencyChecks=true -I ../../../../tool/android_no_upload.init.gradle
```

From the repository root, choose a disposable emulator explicitly:

```sh
python3 tool/check_android_diagnostics.py --serial emulator-5556 \
  --apk packages/apptracer_flutter/example/build/app/outputs/apk/diagnostics/release/app-diagnostics-release.apk \
  --output /tmp/apptracer-diagnostics-results
```

The runner refuses physical devices, clears only the `.diagnostics` example
package, simulates unplugging, switches radios, and restores radio/battery
settings in `finally`. It binds a local HTTP sink to port 37018 and uses adb
reverse for the online phase. Raw heap/disk bodies, headers and tokens are not
saved: evidence contains only selected feature names, byte counts and hashes.
Do not build this fixture with live credentials. Mapping/native uploads are
skipped via the init script; service-side acceptance remains Android №21.
