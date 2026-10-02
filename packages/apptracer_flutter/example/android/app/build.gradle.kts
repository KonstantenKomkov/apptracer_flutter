plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Enable only for the separate native-consent verification entrypoint.
// Ordinary example builds keep their existing flavorless automatic behavior.
val deferredCollection = providers.gradleProperty("tracer.deferred").orNull == "true"

android {
    if (deferredCollection) {
        flavorDimensions += "collection"
        productFlavors {
            create("consent") {
                dimension = "collection"
                applicationIdSuffix = ".consent"
            }
        }
    }

    namespace = "ru.apptracer.flutter.apptracer_flutter_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.apptracer.flutter.apptracer_flutter_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Tracer is opt-in for this example so that a checkout without credentials
// still builds:
//
//     env 'ORG_GRADLE_PROJECT_tracer.enabled=true' \
//         flutter build apk --release \
//         --obfuscate --split-debug-info=build/symbols
//
// with TRACER_APP_TOKEN and TRACER_PLUGIN_TOKEN exported. A real application
// applies the plugin unconditionally; see app/tracer.gradle and the README.
if (project.findProperty("tracer.enabled") == "true") {
    apply(from = "tracer.gradle")
}
