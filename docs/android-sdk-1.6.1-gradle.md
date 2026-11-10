# Android Tracer 1.6.1 Gradle verification

## Mapping/native upload controls (Android №18)

The example reads strict Boolean Gradle properties `tracer.uploadMapping` and
`tracer.uploadNativeSymbols` through providers. Both default to true, preserving
normal production upload behavior. Explicitly disabling both removes the plugin
token requirement; a nonempty `TRACER_APP_TOKEN` is still required whenever the
SDK is included. If either upload flag is true, `TRACER_PLUGIN_TOKEN` is required.
Invalid Boolean strings fail configuration instead of silently changing behavior.
The actual vendor DSL property is `uploadMapping`, singular.

```sh
TRACER_APP_TOKEN=your-app-token ./gradlew :app:assembleRelease \
  -Ptracer.enabled=true -Ptracer.uploadMapping=false \
  -Ptracer.uploadNativeSymbols=false
```

The example's Flutter plugin controls Java/Kotlin R8 via `-Pshrink=true/false`;
this is separate from Dart's `--obfuscate` and `--split-debug-info`.
`tool/check_android_mapping_matrix.py --output /tmp/tracer-mapping-results`
prepares the release registrant, then performs seven clean builds with
placeholder tokens and vendor upload task types disabled by the verification
init script. It inspects generated resources, APK resources with aapt2, mapping
files, R8 task presence, mapping input paths and task dependencies.

**Completed 2026-11-10:** Flutter 3.47.4 / AGP 8.9.1 / Gradle 8.12 / Kotlin 2.1.0 /
JDK 21.0.8, ARM64 release. [Exact hashes and task graphs](android-sdk-1.6.1-mappings.json).

| R8 | Mapping flag | UUID in generated resource and APK | Mapping upload task |
| --- | --- | --- | --- |
| on | true | nonzero generated UUID | registered; verification guard skips execution |
| on | false | all-zero UUID | absent |
| off | true | all-zero UUID | absent |
| off | false | all-zero UUID | absent |

Additional cases verified omitted flags (both uploads enabled), native-only
upload (zero mapping UUID, only native task), and a second clean R8 build with
both uploads disabled and **no plugin token**. The two disabled-upload builds
have identical generated resource SHA-256 and R8 mapping SHA-256. Their complete
APK hashes differ: this check isolates Tracer UUID stability and **does not claim
byte-for-byte APK reproducibility**. The zero UUID resource is still present;
"no generated UUID" must not be read as "no UUID resource".

With mapping enabled and R8 active, `uploadTracerMappingForRelease` consumes
`outputs/mapping/release/mapping.txt` and depends on `minifyReleaseWithR8`.
With either prerequisite off, that upload task is absent. Native upload remains
independent. Guarded enabled cases prove task wiring, not remote uploads.
No package, mapping file or native symbol was published by these checks.

Negative checks reject a missing app token with both uploads off, a missing
plugin token for either mapping-only or native-only, and invalid Boolean text.
`tool/check_android_sdk161.sh` now unsets the plugin token and explicitly turns
off both uploads while retaining its independent no-upload guard. This lets CI
exercise SDK/R8 without live credentials. Production defaults remain enabled.

Analytics-wrapper variants and configuration-cache reuse are separate №20/19
checks. Java/Kotlin mapping is separate from native symbols and Dart AOT symbols;
service-side symbolication of the exact build remains №21.

The updated CI helper passed: 31 Android JUnit tests and both clean SDK/no-SDK
release/R8 builds, with no plugin token. Separate diff review verified defaults,
independent flags, negative checks and the task graph guard. The graph-inspection
init script is intentionally limited to this uncached matrix and is not used
for the subsequent configuration-cache test.

## Analytics-enabled variants (Android №20)

Normal example configuration exposes `ApplicationVariantImpl_Decorated`.
With the standard AGP option `android.enableProfileJson=true`, the same AGP
8.9.1 exposes `AnalyticsEnabledApplicationVariant_Decorated`. This is local
Gradle build profiling, not a new analytics SDK for the application. No user's
telemetry opt-in setting is changed. Inspection of AGP's `ProjectOptions`,
`VariantManager` and `ApplicationVariantImpl.createUserVisibleVariantObject`
confirms that profiling creates the stats builder used by the wrapper.

The 1.6.1 Tracer plugin first tests concrete implementation classes, then the
public `ApplicationVariant`/`LibraryVariant` interfaces to obtain minification
state. The analytics wrapper implements the public application interface but
is not an `ApplicationVariantImpl`. The reproduced branch therefore exercises
the added interface fallback instead of just building another plain variant.

`tool/fixtures/android-sdk161` is an independent minimal application with
alpha/beta flavors, Java/Kotlin failure classes unique to each flavor, minified
release and unminified debug. `tool/check_android_variants.py` copies it to a
fresh output directory and builds all four variants with mappings on, then off.
The observer records actual wrapper types; it does not manufacture a proxy or
replace plugin callbacks.

**Completed 2026-11-10:** eight APKs on Gradle 8.12 / AGP 8.9.1 / Kotlin 2.1.0 /
JDK 21.0.8 / compileSdk 35 / minSdk 21.
[Portable evidence: types, UUIDs, APK/mapping hashes and task graphs](android-sdk-1.6.1-variants.json).

- Both release upload tasks consume their own `outputs/mapping/<variant>/mapping.txt`
  and depend on their own `minify<Variant>WithR8` task. Their manifest application
  IDs and build UUIDs match the corresponding generated resource and APK.
- Alpha and beta release UUIDs differ when mappings are enabled. Mapping hashes
  differ and contain only their own Java/Kotlin failure classes. Actual R8 names
  are `b.a` / `b.b` in each variant, corresponding to different source classes;
  this demonstrates why selecting the wrong variant's mapping would be incorrect.
- Debug variants have a zero UUID, no mapping file and no upload task.
- Mapping-off release variants still run R8 and produce their separate mappings,
  but have a zero UUID and no upload task. All four variants still use the real
  analytics wrapper in this control run.

No vendor upload was attempted: enabled mapping tasks were SKIPPED by the guard,
and native upload remained off. Separate diff review checked flavor isolation,
actual obfuscation, provider-selected mapping inputs and the observer's limited
scope. Java/Kotlin symbolication in Tracer remains №21; nothing here establishes
native-symbol or Dart AOT symbolication support.

## Configuration cache (Android №19)

`tool/check_android_configuration_cache.py --output /tmp/tracer-cache-results`
runs every build with `--configuration-cache --configuration-cache-problems=fail`.
It uses the same command twice without clean, checks explicit reuse, changes a
tracked input, and verifies recalculation and changed output. Vendor uploads
remain disabled or blocked by the verification guard. No graph-observer init
script is used in cached builds.

**Completed in the plan's native-reproducer fallback, 2026-11-10.**
[Results and log hashes](android-sdk-1.6.1-cache.json), Gradle 8.12 / AGP 8.9.1 /
Kotlin 2.1.0 / JDK 21.0.8 / Flutter 3.47.4:

- Minimal Android fixture with SDK: first `assembleAlphaRelease` stores the
  cache; second explicitly reuses it. Changing `tracer.uploadMapping=false` to
  true in `gradle.properties`, with the **same command**, reports that this file
  changed and recalculates. The generated UUID changes from zero to nonzero;
  the newly selected mapping task is SKIPPED by the guard. The fourth run reuses
  the changed configuration and retains that UUID.
- Minimal fixture without SDK/plugin application: first stores, second reuses.
  The generated Tracer UUID resource is absent.
- Actual Flutter example's `generateReleaseResValues` and
  `generateTracerManifestSourcesForRelease`: store/reuse succeeds. Changing
  `TRACER_APP_TOKEN` between identical commands explicitly invalidates the cache
  and updates the generated resource. This verifies the example's provider-based
  settings and Tracer generation tasks, **not full APK assembly**.
- Full Flutter `assembleRelease`, with SDK and without SDK: both first and second
  runs fail to store the cache with the same upstream task ownership. No full
  Flutter cache reuse is claimed.

### Open blocker: full Flutter assemble

Flutter 3.47.4's `FlutterPlugin.kt`, in the `variant.outputs.forEach` /
`assembleTask.doLast` block around line 392, captures the legacy
`ApkVariantOutputImpl`. Its object graph includes Gradle Project, configuration
containers, dependency handlers and a Kotlin build service that cannot be
serialized. Gradle reports seven problems (five distinct categories) and discards
the cache. The stack names `FlutterPlugin$addFlutterTasks$2$1$1.$output`; the
same failure occurs when Tracer is not applied. The source also uses the legacy
variant to copy the APK into Flutter's output directory. Removing that action
would break the normal Flutter build contract and is not a fix in this repo.

The full-build blocker remains [open in the active plan](tasks/development_android_1.6.1.md#blocker-flutter-configuration-cache).
Resolution requires a compatible Flutter Gradle implementation/toolchain, then
successful strict store/reuse/invalidation for the full SDK and no-SDK commands.
Do not enable configuration cache for production Flutter assemble on the basis
of the passing native fixture or generation-task checks.

CI now has a dedicated job pinned to the audited Flutter 3.47.4 / JDK 21
combination. It runs the native gate and records the full Flutter limitation in
artifacts; unrelated failures are not accepted. The fallback recognizer requires
all cache problem task entries to be `:app:assembleRelease` and the diagnostic to
name both FlutterPlugin and ApkVariantOutputImpl. `--require-full-flutter` turns
this known limitation into a failing exit status; `--native-only` runs only the
minimal strict gate. Local validation passed; a remote CI run is separate
execution evidence. Separate diff review checked strict failure handling,
invalidation without clean, output verification and the absence of graph hooks.
