# Android setup guide

Current SDK coordinates and supported environments are summarized in
[platform-matrix.md](platform-matrix.md). Historical acceptance results are not
installation instructions; use this guide for setup.

## Dependencies and tokens

Create an Android project in Tracer and copy its `appToken` and `pluginToken`.
The application needs `appToken`; the build needs `pluginToken` only for mapping
and native-symbol uploads.

Keep Flutter `includeBuild` in `android/settings.gradle.kts`, then configure
repositories and the plugin:

```kotlin
pluginManagement {
    repositories {
        maven("https://nexus-external.vkteam.ru/repository/maven-tracer-public-exposed/") {
            content { includeGroup("ru.ok.tracer") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("ru.ok.tracer") version "1.6.2" apply false
}
```

Add VK Nexus to dependency repositories in `android/build.gradle.kts` or
`dependencyResolutionManagement.repositories`:

```kotlin
maven("https://nexus-external.vkteam.ru/repository/maven-tracer-public-exposed/") {
    content { includeGroup("ru.ok.tracer") }
}
google()
mavenCentral()
```

In `android/app/build.gradle.kts`:

```kotlin
plugins {
    // Keep the existing Flutter and Android plugins.
    id("ru.ok.tracer")
}

android {
    buildFeatures {
        resValues = true
    }
}

tracer {
    create("defaultConfig") {
        appToken = "ANDROID_APP_TOKEN"
        pluginToken = providers.gradleProperty("androidPluginToken").orNull
        uploadMapping = true
        uploadNativeSymbols = true
    }
}

dependencies {
    implementation(platform("ru.ok.tracer:tracer-platform:1.6.2"))
    implementation("ru.ok.tracer:tracer-crash-report")
    // Optional native crash reports:
    implementation("ru.ok.tracer:tracer-crash-report-native")
}
```

The Android SDK reads `appToken` from the generated resource. Do not pass it to
`TracerOptions`; it is ignored on Android. `environment` also comes from the
Gradle plugin, by default the build variant name.

Store `pluginToken` outside the repository in `~/.gradle/gradle.properties`:

```properties
androidPluginToken=...
```

In CI use `ORG_GRADLE_PROJECT_androidPluginToken` or `-PandroidPluginToken=…`.
With both upload flags false, only `appToken` is required; either enabled
upload requires `pluginToken`.

## Debug and native crashes

Debug uploads are off by default. Enable them only through an `Application`
implementing `HasTracerConfiguration` (`setDebugUpload`). Such an application
replaces package settings; subclass `ru.apptracer.flutter.TracerApplication`
and add custom configuration to `super.tracerConfiguration` to retain the
package's non-fatal rate limit.

Experimental tombstones are off by default. For SDK 1.5.2, 1.6.1 or 1.6.2 on
Android 12 / API 31+, enable them inside `<application>`:

```xml
<meta-data
    android:name="ru.apptracer.flutter.experimentalTombstoneEnabled"
    android:value="true" />
```

A custom `HasTracerConfiguration` must instead call
`setExperimentalTombstoneEnabled(true)` in its existing builder. Do not enable
both native module and tombstones for the same crash unless MINIDUMP and
TOMBSTONE duplicates are intended.

## Consent and lifecycle

For deferred consent, remove both startup providers from the manifest and start
collection explicitly after authorization. `pauseCollection`/`resumeCollection`
pauses an authorized session without clearing context; logout requires
`stopAndClearCollection`. See [native-collection-consent.md](native-collection-consent.md)
and [privacy.md](privacy.md).

For symbolication, upload mapping and native symbols from the exact build. The
known Kotlin console file/line defect and configuration-cache limitation are
recorded in [release-history.md](release-history.md), not treated as fixed.
