# Kotlin symbolication discrepancy

This fixture contains only the Java/Kotlin probe entries extracted from the
exact R8 8.9.32 mapping uploaded during Android SDK 1.6.1 acceptance. It contains
no credentials. `stacktrace.txt` preserves the actual obfuscated probe frames;
`expected.txt` is the result of local Retrace 8.9.32.

```sh
java -cp "$R8_JAR" com.android.tools.r8.retrace.Retrace \
  tool/fixtures/android-sdk161/kotlin-symbolication/mapping.fixture \
  tool/fixtures/android-sdk161/kotlin-symbolication/stacktrace.txt
```

For the audited toolchain, `R8_JAR` can point to AGP 8.9.1's `builder-8.9.1.jar`,
which includes Retrace 8.9.32. Compare stdout with `expected.txt`.
This fragment is **not** a replacement for the full application mapping.

The Tracer console restored the Java frame correctly, but rendered the Kotlin
frame as `KotlinCrashProbe.crash(KotlinCrashProbe.java:14)` in both formatted and
plain views. Local Retrace restores `KotlinCrashProbe.kt:6`.
The full uploaded gzip mapping was checked byte-for-byte against the archived
mapping by SHA-256; its multipart buildUuid also matches the tested APK.

See the [acceptance protocol](../../../../docs/android-sdk-1.6.1-acceptance.md)
for the exact APK/mapping hashes, buildUuid and console event link. Task 21
remains open until the console also restores the Kotlin file and line. Keeping
the Kotlin probe unobfuscated or changing the expected output would hide the
failed criterion, so neither is used as a workaround.
