# Настройка Android

Актуальные версии SDK, минимальный API и проверенные среды приведены в
[матрице платформ](platform-matrix.md). [English](android-guide.en.md).

## Зависимости и токены

Создайте Android-проект в Tracer. Его `appToken` нужен приложению для отправки
событий, а `pluginToken` — сборке для загрузки маппингов и нативных символов.

В существующем `android/settings.gradle.kts` сохраните Flutter `includeBuild`
и плагины приложения. Добавьте репозиторий в `pluginManagement.repositories`
и объявите версию плагина:

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

Для зависимостей добавьте тот же репозиторий в `android/build.gradle.kts`
или `dependencyResolutionManagement.repositories`:

```kotlin
maven("https://nexus-external.vkteam.ru/repository/maven-tracer-public-exposed/") {
    content { includeGroup("ru.ok.tracer") }
}
google()
mavenCentral()
```

В `android/app/build.gradle.kts` добавьте плагин к существующим и настройте SDK:

```kotlin
plugins {
    // Сохраните существующие плагины Flutter и Android.
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
    // Опционально, для нативных падений:
    implementation("ru.ok.tracer:tracer-crash-report-native")
}
```

Gradle-плагин записывает `appToken` в ресурс приложения и задаёт окружение,
по умолчанию по имени build variant. На Android значения `appToken` и
`environment` из `TracerOptions` игнорируются.

Сохраните токен загрузки символов в `~/.gradle/gradle.properties`:

```properties
androidPluginToken=...
```

В CI передайте свойство через `ORG_GRADLE_PROJECT_androidPluginToken`.
Для первого события без загрузки символов выставьте `uploadMapping = false`
и `uploadNativeSymbols = false`. Тогда достаточно `appToken`.

<a id="debug-and-native-crashes"></a>

## Debug-сборки и нативные падения

Для первой проверки используйте release-сборку. В debug отправку можно включить
через `setDebugUpload` в `Application` с `HasTracerConfiguration`. Чтобы сохранить
лимит нефатальных событий пакета, наследуйте `ru.apptracer.flutter.TracerApplication`
и расширьте `super.tracerConfiguration`.

Экспериментальные tombstones выключены по умолчанию. Для SDK 1.5.2, 1.6.1
или 1.6.2 на Android 12 / API 31+ добавьте в `<application>`:

```xml
<meta-data
    android:name="ru.apptracer.flutter.experimentalTombstoneEnabled"
    android:value="true" />
```

Если конфигурацией управляет собственный `HasTracerConfiguration`, вызовите
`setExperimentalTombstoneEnabled(true)` в его builder. При одновременном
включении нативного модуля и tombstones одно падение может дать два отчёта.

## Согласие и символизация

Для отложенного старта удалите оба startup provider по
[инструкции для манифеста](native-collection-consent.md#android-build-time-setup).
После согласия вызовите `startCollection`. Для временной паузы используйте
`pauseCollection` и `resumeCollection`, для выхода из аккаунта — `stopAndClearCollection`.
[Контракт очистки](native-collection-consent.md) и [приватность](privacy.md).

Для символизации нужны mapping и нативные символы от той же сборки.
[История миграций](release-history.md#android-sdk-162-migration) описывает
ограничения configuration cache и известную ошибку номера строки Kotlin в консоли.
