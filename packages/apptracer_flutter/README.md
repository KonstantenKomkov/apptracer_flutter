# apptracer_flutter

Неофициальная интеграция Flutter с [Tracer](https://apptracer.ru) — сервисом
мониторинга ошибок от OK.TECH / VK.

> **Это не официальный SDK.** Пакет не связан с VK и OK.TECH, не одобрен и не
> поддерживается ими. Это независимая обёртка над публичными SDK вендора; сами
> SDK пакет не распространяет. С проблемами обращайтесь
> [сюда](https://github.com/KonstantenKomkov/apptracer_flutter/issues), а не в
> поддержку Tracer.

English version: [README.en.md](README.en.md).

## Быстрый старт

Пять минут до первого события в консоли Tracer. Развёрнутые версии всех шагов —
ниже по документу.

**1. Заведите проект в Tracer.** Отдельный на каждую платформу: у Android, iOS
и web свои `appToken`, общего нет.

**2. Настройте платформу.** Пропустить нельзя: токен на каждой платформе
доставляется по-своему, и без этого шага пакет запустится, напечатает, что он
выключен, и не отправит ничего.

| Платформа | Что нужно | Подробно |
|---|---|---|
| Android | Gradle-плагин `ru.ok.tracer` и зависимости SDK — токен приходит оттуда, а не из Dart | [Android](#android) |
| iOS | строка `source` в `Podfile` и статическая линковка | [iOS](#ios) |
| Web | ничего, кроме токена в `TracerOptions` | [Web](#web-и-остальные-платформы) |

**3. Оберните запуск приложения.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      // iOS и web. На Android токен приходит из Gradle-плагина, здесь он
      // игнорируется.
      appToken: String.fromEnvironment('TRACER_APP_TOKEN'),
      release: '1.0.0',
      environment: 'prod',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

Всё, что бросается дальше, — необработанные исключения, ошибки внутри `build()`
и асинхронные ошибки без `await` — уходит в Tracer само. Ничего больше вызывать
не нужно.

**4. Убедитесь, что связка живая.** Повесьте на кнопку строку и нажмите:

```dart
onPressed: () => throw StateError('проверка apptracer_flutter'),
```

В консоли Tracer должно появиться событие. Заголовок у платформ разный, и это
нормально: на Android он читается как
`DartError: StateError: проверка apptracer_flutter`, на iOS консоль всегда
подставляет в начало свой разбор верхнего нативного кадра, поэтому там будет
`+ 0 - StateError: проверка apptracer_flutter`. Читаемый стектрейс Dart в обоих
случаях лежит во вкладке «Логи».

### Если событий нет

Почти всегда дело в одном из четырёх:

* **Платформенная настройка пропущена.** При старте пакет печатает строку о
  том, что он выключен и почему; `Tracer.isEnabled` в этот момент `false`.
  Загляните в лог первым делом.
* **Сборка debug.** Нативный SDK по умолчанию не отправляет ничего из
  debug-сборок — ни с Android, ни с iOS. Проверяйте на release, либо включайте
  `setDebugUpload` (Android, см. ниже).
* **Android: не выставлен `resValues = true`.** Начиная с AGP 9 фича выключена
  по умолчанию, а SDK читает `appToken` именно из сгенерированного ресурса и
  падает в рантайме без него.
* **Android: токен передан в `TracerOptions`.** Там он игнорируется — на Android
  токен берётся только из блока `tracer { }` в Gradle.

### Что дальше

* [Использование](#использование) — ручная отправка, breadcrumbs, кастомные ключи.
* [Согласие пользователя](#согласие-пользователя) — как не собирать ничего, пока
  пользователь не разрешил.
* [Какие данные уходят](#какие-данные-уходят) — полный список, включая то, что
  добавляет от себя нативный SDK.
* [Обфусцированные release-сборки](#обфусцированные-release-сборки) — что станет
  со стектрейсом и как его прочитать.

## Зачем это нужно

Нативные SDK Tracer не видят ошибок Dart.

Android SDK ставит `Thread.UncaughtExceptionHandler`, нативный обработчик
сигналов и ANR-watchdog. Необработанное Dart-исключение не задевает ни один из
них: процесс не падает, и в JVM исключение не попадает. Flutter перехватывает
его внутри Dart — через `FlutterError.onError`,
`PlatformDispatcher.instance.onError` или обработчик ошибок guarded zone. На iOS
то же самое.

Для Flutter-приложения это подавляющее большинство ошибок. Подключите Tracer SDK
сам по себе — и получите нативные краши и ANR при подозрительно пустом
дашборде: исключения, с которыми реально сталкиваются пользователи, туда просто
не доходят.

Пакет цепляется к этим трём точкам входа Dart и передаёт найденное в нативный
SDK, который продолжает сам заниматься нативными крашами, ANR и метрикой
crash-free.

## Что вы получите, кроме ошибок Dart

Список платформ есть на самой странице пакета, повторять его тут незачем.
Ошибки Dart — работа этого пакета, и они одинаково доезжают со всех трёх.
Неровно распределено остальное, потому что этим занимается нативный SDK
вендора:

* **Android** — нативные краши и ANR. ANR только с Android 11: `AnrReporter` в
  `tracer-crash-report` 1.4.0 строит отчёт из `ApplicationExitInfo`, а тот
  появился в API 30, и ниже `setSendAnr(true)` не даёт ничего.
* **iOS** — нативные краши и счётчик зависаний.
* **Web** — только ошибки Dart, нативных крашей там нет по определению.

Десктоп и Аврора не поддерживаются, и в списке платформ пакета их нет. Почему —
в конце раздела [Web](#web-и-остальные-платформы).

На платформе без реализации пакет инертен: `isEnabled` равен `false`,
печатается одна диагностическая строка, ничего не бросается, приложение
стартует. Подробности — в
[platform-matrix.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).

## Платформенная настройка

Шаг 2 быстрого старта целиком. Обязателен: без него пакет стартует, сообщает,
что выключен, и ничего не отправляет.

### Android

Android SDK Tracer читает `appToken` из ресурса, который генерируется во время
сборки, поэтому Gradle-плагин обязателен. Альтернативы в рантайме нет.

`android/settings.gradle.kts` — плагин лежит на Maven Central, а не в Gradle
Plugin Portal:

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("ru.ok.tracer") version "1.4.0" apply false
}
```

`android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("ru.ok.tracer")
}

android {
    buildFeatures {
        // Tracer опирается на ресурсы, встраиваемые при сборке. Начиная с
        // AGP 9 фича по умолчанию выключена, и без неё SDK падает в рантайме.
        resValues = true
    }
}

tracer {
    create("defaultConfig") {
        // Не System.getenv: код исполняется в демоне Gradle, который наследует
        // окружение запустившего его шелла и живёт между сборками, поэтому
        // экспортированный позже токен останется невидимым.
        appToken = providers.environmentVariable("TRACER_APP_TOKEN").orNull
        pluginToken = providers.environmentVariable("TRACER_PLUGIN_TOKEN").orNull
        uploadMapping = true
        uploadNativeSymbols = true
    }
}

dependencies {
    implementation(platform("ru.ok.tracer:tracer-platform:1.4.0"))
    implementation("ru.ok.tracer:tracer-crash-report")
    // По желанию, для нативных крашей:
    implementation("ru.ok.tracer:tracer-crash-report-native")
}
```

Токены читайте из окружения. Токен, попавший в репозиторий, — это утёкший токен.

Включите мягкий рейт-лимит на нефатальные. Жёсткий дефолт Tracer — **8
нефатальных за сессию** (`LIMIT_MAX_NON_FATALS_PER_SESSION`), а каждая ошибка
Dart, которую отправляет этот пакет, — нефатальная, так что упрётесь вы именно
в этот потолок. Рейт-лимит поднимает его до 10 в час, и вендор сам рекомендует
его включать:

```kotlin
class MyApplication : Application(), HasTracerConfiguration {
    override val tracerConfiguration: List<TracerConfiguration>
        get() = listOf(
            CrashReportConfiguration.build {
                setExperimentalNonFatalRateLimitEnabled(true)
            },
        )
}
```

Три важных момента:

* **`TracerOptions.appToken` на Android игнорируется.** Токен приходит из
  Gradle-плагина. Если передать его всё равно, плагин напишет предупреждение, а
  не сделает вид, что значение применилось.
* По умолчанию SDK не отправляет данные из debug-сборок. Включается через
  `CoreTracerConfiguration.Builder.setDebugUpload` в `Application`, реализующем
  `HasTracerConfiguration`.
* `Tracer.stopCollection()` вызывает `Tracer.disable()` нативного SDK, а его
  нельзя отменить до перезапуска процесса. Это сделано намеренно, см.
  [privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).
* `TracerOptions.environment` на Android тоже игнорируется — SDK берёт его из
  Gradle-плагина, по умолчанию это имя build variant. Задавайте в блоке
  `tracer { }`.

### iOS

Под `OKTracer` лежит в собственном spec-репозитории вендора, поэтому
`ios/Podfile` должен объявить его источником. Как только добавлен один
кастомный источник, CDN тоже нужно указать явно:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'
```

`OKTracer` поставляется **статическим** `xcframework`, а CocoaPods не позволяет
таргету с динамическими фреймворками получить статический бинарник транзитивно.
Поменяйте тип линковки внутри `target 'Runner'`:

```ruby
target 'Runner' do
  use_frameworks! :linkage => :static   # было: use_frameworks!
  ...
end
```

Без этого `pod install` падает с ошибкой *«The 'Pods-Runner' target has
transitive dependencies that include statically linked binaries»*. То же самое
требуют статические фреймворки Firebase; Flutter это поддерживает.

Затем `pod install`. На iOS `appToken` **передаётся** из Dart.

### Web и остальные платформы

Web говорит с собственным приёмом Tracer — тем же, что и JS-SDK вендора, — и
хочет `appToken` JS-проекта, ровно как Android и iOS хотят свой. Sentry DSN не
нужен и не выдаётся: проверено 26.08.2026, у JS-проекта его попросту нет.
Разбор протокола — в [web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).

**Десктоп и Аврора в этом релизе не поддерживаются.** Нативного SDK для Flutter
там нет, и ни одна сборка под них ни разу не проверялась на живом проекте.
Транспорт зарегистрировать можно, ошибки Dart, скорее всего, поедут — но
«скорее всего» это и есть всё утверждение целиком:

```yaml
dependencies:
  apptracer_flutter_http: ^0.1.0
```

```dart
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

TracerPlatform.instance = TracerHttpTracer(
  facts: PlatformClientFacts(),
  sdkVersion: '0.1.0',
);
```

## Использование

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      appToken: String.fromEnvironment('TRACER_APP_TOKEN'), // iOS и web
      // dsn нужен только транспорту Sentry, то есть неподдерживаемым платформам
      environment: 'prod',
      release: '1.0.0',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

`appRunner` вызывается **ровно один раз в любом сценарии**: при обычном старте,
при запрете сбора политикой, при падении инициализации нативного SDK и на
платформе без реализации. Сборщик ошибок, способный не дать приложению
запуститься, хуже, чем отсутствие сборщика ошибок.

Ручная отправка обработанной ошибки:

```dart
try {
  await repository.load();
} catch (error, stackTrace) {
  await Tracer.recordError(
    error,
    stackTrace,
    severity: TracerSeverity.warning,
    issueKey: 'ORDERS-LOAD',                       // переопределяет группировку
    customKeys: {'endpoint': '/orders'},
  );
}
```

Логи и ключи:

```dart
Tracer.log('пользователь нажал «оформить»', category: 'ui');
await Tracer.setCustomKey(key: 'checkout_step', value: '3');
await Tracer.removeCustomKey('checkout_step');
```

Breadcrumbs копятся в Dart **и** сразу дублируются в нативный лог-буфер,
поэтому нативный краш — которого Dart-сторона не видит — всё равно приходит с
цепочкой событий.

### Согласие пользователя

```dart
// До первого кадра:
Tracer.initialize(
  options: TracerOptions(isCollectionEnabled: consent.isGranted),
  appRunner: () => runApp(const MyApp()),
);

// Отзыв согласия во время сессии:
await Tracer.stopCollection();
```

`stopCollection` снимает установленные обработчики ошибок Dart и восстанавливает
те, что стояли раньше, — включая ваши собственные. Восстановление происходит
только если текущий обработчик всё ещё тот, который поставил пакет; если после
него встроился кто-то третий, пакет сообщает об этом и оставляет чужой
обработчик на месте, а не удаляет чужую работу.

### Фильтрация данных

```dart
TracerOptions(
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<скрыто>')
      : event,
  beforeBreadcrumb: (crumb) => crumb.category == 'auth' ? null : crumb,
)
```

Верните `null`, чтобы отбросить событие. Если хук бросит исключение, оно будет
залогировано и проигнорировано, а исходное событие всё равно отправится.

### Очень большие стектрейсы

Дословный стектрейс, который пишется в платформенный лог, по умолчанию
ограничен 8 КиБ, разобранные кадры — 128 штуками.

Причина в том, что лог-буфер Android — **кольцевой**, на 64 КиБ: всё
записанное вытесняет что-то более старое. Патологический стектрейс
(`StackOverflowError`, глубокая цепочка async) занимает сотни килобайт и
вымоет из буфера всю цепочку breadcrumbs — событие приедет со стектрейсом и без
контекста.

Обрезается хвост: начало сохраняется, потому что там заголовок `build_id` и
кадры ближе всего к месту броска. Сколько строк выкинуто — написано прямо в
логе. Поднять или снять лимит:

```dart
TracerOptions(
  maxRawStackTraceLogBytes: 32768,  // 0 — без лимита
  maxStackFrames: 256,              // 0 — без лимита
)
```

### Уровень автоматически перехваченных ошибок

Ошибки из `FlutterError.onError`, `PlatformDispatcher.onError` и guarded zone
отправляются с уровнем `error`, а не `fatal`. Ни одна из них не завершает
процесс — именно поэтому нативные SDK их и не видят, — а fatal-событие влияет на
метрику crash-free на Android и iOS. Помечать их фатальными значило бы
отчитываться о крашах, которых не было.

Если команда осознанно решила иначе:

```dart
TracerOptions(reportUnhandledErrorsAsFatal: true)
```

## Какие данные уходят

Сам пакет **не добавляет никаких персональных данных**: ни идентификатора
установки, ни идентификатора устройства, ни идентификатора пользователя, ни
автоматического контекста. Отправляется либо свойство самой ошибки, либо то, что
вы передали явно.

Нативные SDK — отдельная история: Android SDK сам собирает модель устройства,
производителя, ABI, версию ОС, оператора связи и пакет установщика, независимо
от того, стоит ли этот пакет. Полная таблица и способы ограничения — в
[privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).

### Группировка

Если вызывающий код не задал `issueKey`, пакет синтезирует его сам — из типа
ошибки и внутреннего именованного кадра, не длиннее 32 символов.

Это не украшение. На Android Tracer группирует по классу и методу верхнего
кадра и только по ним: измерено на живом проекте 26.08.2026, когда `StateError`
и `TimeoutException`, брошенные из двух замыканий одного `build`, оказались в
одной группе. Во Flutter-приложении почти все обработчики — такие замыкания. На
iOS ситуация другая, но исход тот же: стектрейс Dart не несёт нативных адресов,
и группировать там просто не на чем.

Ни файл, ни номер строки в ключ не входят: сам Tracer их игнорирует, чтобы
правка кода не разносила одну проблему по нескольким группам, и синтетический
ключ это свойство сохраняет. Свой `issueKey`, переданный в `recordError`, всегда
имеет приоритет.

## Обфусцированные release-сборки

При сборке с `--obfuscate --split-debug-info` Dart-стектрейсы превращаются в
адреса:

```
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
#00 abs 0000007938a1c2f0 virt 00000000002cc2f0
```

Пакет всегда отправляет **дословный** стектрейс вместе с заголовком, поэтому он
остаётся расшифровываемым:

```
flutter symbolize -d build/symbols/app.android-arm64.symbols -i trace.txt
```

**У Tracer нет документированного канала для загрузки Dart-файлов
`--split-debug-info`**, поэтому расшифровка сейчас — ручной шаг. Прочитайте
[symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md)
до того, как выкатите обфусцированную сборку: там написано, что работает, что
нет, и как не узнать об этом слишком поздно.

## Зрелость

Версия `0.1.0`. Поведение Dart-стороны подробно покрыто юнит-тестами, но
доставка событий пока не подтверждена на живом проекте Tracer — для этого нужны
доступы, которых у репозитория нет.
[status.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/status.md)
перечисляет, что проверено, а что нет. Версия останется ниже `1.0.0`, пока
реальный проект не подтвердит сквозную доставку на каждой платформе.

## Пакеты

| Пакет | Назначение |
|---|---|
| `apptracer_flutter` | то, от чего зависит приложение |
| `apptracer_flutter_platform_interface` | модели, парсер стектрейсов, контракт платформы |
| `apptracer_flutter_android` | мост на Kotlin к `ru.ok.tracer` |
| `apptracer_flutter_ios` | мост на Swift к `OKTracer` |
| `apptracer_flutter_web` | реализация для web |
| `apptracer_flutter_http` | транспорт по протоколу Sentry на чистом Dart |

## Лицензия

MIT. SDK вендора лицензируются отдельно, см.
[legal.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/legal.md).
