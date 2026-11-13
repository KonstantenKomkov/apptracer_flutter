# apptracer_flutter_android

Реализация [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) под Android — неофициальной интеграции
Flutter с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Зависеть от этого пакета напрямую не нужно: его подтягивает
`apptracer_flutter`.

## Что он делает

Передаёт ошибки Dart в `ru.ok.tracer:tracer-crash-report`. Нативные краши, ANR
и метрику crash-free этот SDK считает сам — плагин добавляет только ту
половину, которую SDK не видит.

Ошибка Dart заворачивается в синтетический `Throwable`, чей `stackTrace`
собран из кадров Dart. Если отдавать вместо этого стек JVM, у всех ошибок Dart
в приложении окажутся одинаковые кадры, и Tracer схлопнет их в одну проблему.

## Подключение

SDK Tracer подключён здесь как `compileOnly`, поэтому его добавляет само
приложение — вместе с Gradle-плагином `ru.ok.tracer`, откуда берётся
`appToken`. См. [README](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/packages/apptracer_flutter/README.md#android).

Версия пакета **0.3.0** компилируется с SDK **1.6.1**. Используйте BOM и Gradle-плагин
1.6.1, `mavenCentral()` в репозиториях плагинов и зависимостей и `google()` для
Android-зависимостей. VK-репозиторий для 1.6.1 не нужен. Ранее проверенные
1.4.0/1.5.2 остаются допустимыми версиями host SDK; для них сохраните прежнюю
настройку vendor-репозитория, если артефакты требуют её. На старых SDK нет
runtime API `enable()`. Полный stop/clear по-прежнему требует нового процесса.
См. [аудит 1.6.1 и границы приёмки](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/android-sdk-1.6.1.md).

Настройку SDK пакет ставит себе сам, без строчки в манифесте: рейт-лимит на
нефатальные (10 в час вместо жёстких 8 за сессию — а каждая ошибка Dart здесь
нефатальная). Кладёт её `TracerAutoConfigProvider`, который система создаёт
раньше провайдера Tracer. `Application`, реализующий `HasTracerConfiguration`,
эту конфигурацию отменяет — на такой случай в пакете есть
`TracerApplication`, от которого наследуются. Почему так и чем это рискованно —
в `TracerAutoConfig`.

О четырёх вещах плагин скажет в рантайме, а не промолчит. Первые две его
выключают:

* SDK Tracer отсутствует в classpath рантайма;
* Gradle-плагин `ru.ok.tracer` не применён — определяется по отсутствию
  сгенерированного ресурса `tracer_app_token`;
* передан `TracerOptions.appToken` — на Android он игнорируется;
* передан `TracerOptions.environment` — тоже игнорируется, значение берётся из
  Gradle-плагина.

Требует `minSdk 21` — как и `ru.ok.tracer:tracer-commons`.


## Android tombstones (SDK 1.5.2)

Экспериментальные системные отчёты о нативных крэшах **выключены по умолчанию**.
Чтобы включить их без собственного `Application`, добавьте внутрь `<application>`
в `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="ru.apptracer.flutter.experimentalTombstoneEnabled"
    android:value="true" />
```

Нужны Tracer Android **1.5.2 или 1.6.1** и **Android 12 / API 31+**. Функция входит
в `tracer-crash-report`; модуль `tracer-crash-report-native` необязателен
и остаётся полезным для нативных крэшей на старых версиях Android. Tombstones
позволяют символизировать системные библиотеки, но не гарантируют символизацию
Dart AOT. Отчёты восстанавливаются при последующем запуске SDK.

Собственный `Application`, реализующий `HasTracerConfiguration`, заменяет
настройки пакета. В его существующем `CrashReportConfiguration.Builder` вызовите
`setExperimentalTombstoneEnabled(true)` и при необходимости сохраните лимит
нефатальных событий. Наследник `TracerApplication` учитывает флаг манифеста.

Флаг работает при автоматическом и отложенном запуске. Он задаётся на Android
до инициализации SDK, а не через Dart `TracerOptions`. Для отложенного сбора
по-прежнему нужны удаление провайдеров из манифеста и явный `startCollection`;
сам флаг сбор не запускает. После обновления выполните чистую сборку.
Прежняя настройка vendor Nexus относится к старым host SDK; 1.6.1 использует
Maven Central, как описано выше.

### Android 1.6.1: миграция и ограничения

Используйте `apptracer_flutter ^1.1.0` (Android-адаптер `^0.3.0`), BOM и
Gradle-плагин 1.6.1. Добавьте `mavenCentral()` в репозитории плагинов и
зависимостей; VK Nexus для этой версии не требуется. Затем выполните чистую
release-сборку. Старые host SDK 1.4.0/1.5.2 остаются допустимыми с прежними
ограничениями и настройкой их репозиториев.

- `startCollection` может возобновить уже инициализированный SDK 1.6.1 после
  нативного `Tracer.disable()`. В кандидате Android-адаптера 0.4.0 он также
  создаёт новую сессию после успешной полной deferred-очистки на SDK 1.6.1.
  Для SDK 1.4.0/1.5.2 и автоматической инициализации сохраняется требование
  нового процесса. Build-time disable меняется только сборкой.
  Наблюдение состояния само сбор не включает.
- Флаги Gradle DSL называются `uploadMapping` и `uploadNativeSymbols`.
  При обоих `false` нужен только `appToken`; если включён хотя бы один upload,
  нужен `pluginToken`. При `uploadMapping=false` SDK 1.6.1 генерирует нулевой
  `buildUuid`; восстановление JVM-стека в сервисе тогда не обещается.
- **Известный дефект Tracer:** в проверенном Kotlin-крэше класс и метод
  восстановлены, но консоль показывает `.java:14` вместо `.kt:6`. Доставка и
  Java-символизация проверены. Сохраняйте полный `mapping.txt` точной сборки
  и исходный обфусцированный стек для локального R8 Retrace. Дефект принят как
  ограничение выпуска и остаётся открытым.
- Полный Flutter `assembleRelease` не сохраняет configuration cache на
  проверенной комбинации Flutter 3.47.4 / AGP 8.9.1 / Gradle 8.12 / JDK 21,
  в том числе без SDK Tracer. Используйте `--no-configuration-cache` для Gradle
  или `org.gradle.configuration-cache=false` в `gradle.properties`.
- `HeapDumps.runNow`, `DiskUsage.runNow` и ленивый `provideEnabled` относятся к
  опциональным нативным модулям. В опубликованной версии они не представлены
  в Dart API и не подключаются по умолчанию. Heap dump может приостановить VM/UI даже при фоновом вызове;
  offline samples могут удаляться без retry. Их WorkManager lifecycle не входит
  в поддерживаемую deferred-очистку.
- Одновременное включение native module и experimental tombstones может дать
  MINIDUMP и TOMBSTONE для одного падения. В примере tombstone включается отдельно.

Проверено на release/R8 arm64 эмуляторе Android 15 / API 35. Эта приёмка не
сертифицирует физические устройства или native/Dart-символизацию.
[Протокол](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/android-sdk-1.6.1-acceptance.md),
[ограничения diagnostic-модулей](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/android-sdk-1.6.1-diagnostics.md).

## Новые runtime API — ещё не опубликованы

В рабочей версии доступны `Tracer.pauseCollection()` / `resumeCollection()`
для текущей разрешённой Android-сессии SDK 1.6.1. Пауза сохраняет данные и не
отменяет выполняющиеся отправки. Для logout нужен `stopAndClearCollection`;
новый разрешённый `startCollection` восстанавливает сбор на Android 1.6.1
в deferred-режиме. iOS 1.5.2 пока возвращает `restartRequired`.

Добавлены `runHeapDump(tag: ...)`, `runDiskUsage()` и `setHeapDumpEnabled(bool)`.
Модули подключает приложение явно; heap provider также устанавливается хостом
до старта SDK. Deferred-очистка этих модулей не поддержана. `invoked` означает
возврат из нативного метода, а не доставку. Используйте совместные path overrides
фасада, Android и platform interface до подготовки нового выпуска.
[Таблица API, настройка, проверки и открытые части №23](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/task-23-collection-lifecycle.md).
