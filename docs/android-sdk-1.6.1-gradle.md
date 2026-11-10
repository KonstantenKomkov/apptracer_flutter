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
