# Android Tracer 1.6.1 Gradle fixture

Minimal AGP 8.9.1 / Kotlin 2.1.0 / compileSdk 35 application with alpha/beta
flavors, minified release and unminified debug. Java/Kotlin failure classes
are deliberately different between flavors, with actual R8 obfuscation.

Run `python3 tool/check_android_variants.py --output /tmp/tracer-variants`
from the repository root, using a new output directory. The runner copies this
fixture, uses the example's Gradle 8.12 wrapper, and requires Android SDK with
build-tools 36.0.0 for resource inspection. Set ANDROID_SDK_ROOT or ANDROID_HOME
outside the default macOS SDK location.

`android.enableProfileJson=true` makes AGP expose the real
AnalyticsEnabledApplicationVariant wrapper. It enables local build profiling,
not application analytics. The graph observer asserts the wrapper class and
checks variant-specific upload inputs/UUIDs. Never use live tokens here: the
fixture embeds placeholders, native upload is off, and the runner disables
mapping task execution with android_no_upload.init.gradle. The graph observers
are verification-only and must not be included in configuration-cache runs.

`tracer.enabled=false` removes plugin application and SDK runtime dependencies.
`tracer.uploadMapping=false` is the default; upload-on is only for guarded
wiring verification. This fixture does not certify remote symbolication,
Android device runtime, native symbols or Dart AOT symbols.
