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

**1. Заведите проект в [консоли Tracer](https://apptracer.ru).** Отдельный на
каждую платформу. Каждый проект выдаёт **свою пару** — `appToken` и
`pluginToken`: приложение на Android, iOS и web означает три проекта и три
пары. Оба значения лежат в разделе **Настройки → Проект → API**.

**2. Подключите SDK Tracer к сборке.** Пакет — обёртка: сами SDK вендора он не
распространяет и за собой не тянет, их добавляет приложение.

### Android

В `android/settings.gradle.kts` — плагин лежит на Maven Central, а не в Gradle
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

В `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("ru.ok.tracer")
}

android {
    // SDK читает appToken из ресурса, который генерируется при сборке.
    // С AGP 9 фича выключена по умолчанию, и без неё SDK падает в рантайме.
    buildFeatures {
        resValues = true
    }
}

tracer {
    create("defaultConfig") {
        appToken = "ваш-app-token"
        pluginToken = "ваш-plugin-token"
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

Токен на Android приходит отсюда, а не из Dart: SDK читает его из ресурса,
который Gradle-плагин генерирует во время сборки. Альтернативы в рантайме нет —
поэтому плагин и обязателен.

Строками эти два ключа стоят только ради наглядности, и они не равноценны.
`appToken` так и можно оставить: плагин всё равно вшивает его в APK, прятать
нечего. А `pluginToken` — секрет, он подписывает загрузку маппингов и символов
и в приложение не попадает, так что в репозитории ему не место:

```kotlin
pluginToken = providers.environmentVariable("TRACER_PLUGIN_TOKEN").orNull
```

Откуда возьмётся само окружение — ваше дело. Локально обычно хватает файла вне
репозитория:

```sh
# ~/.tracer-env — вне любого git-репозитория, chmod 600
export TRACER_ANDROID_APP_TOKEN=...
export TRACER_ANDROID_PLUGIN_TOKEN=...
# Если приложение выходит ещё и на iOS или web — там свои проекты, а значит
# свои пары токенов, и путать их не стоит:
export TRACER_IOS_APP_TOKEN=...
export TRACER_IOS_PLUGIN_TOKEN=...
```

```sh
source ~/.tracer-env && \
  TRACER_APP_TOKEN=$TRACER_ANDROID_APP_TOKEN \
  TRACER_PLUGIN_TOKEN=$TRACER_ANDROID_PLUGIN_TOKEN \
  flutter build apk --release
```

В CI — секретами сборочной системы, например в GitHub Actions:

```yaml
- run: flutter build apk --release
  env:
    TRACER_APP_TOKEN: ${{ secrets.TRACER_ANDROID_APP_TOKEN }}
    TRACER_PLUGIN_TOKEN: ${{ secrets.TRACER_ANDROID_PLUGIN_TOKEN }}
```

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

Ещё четыре момента, о которые легко споткнуться:

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

В `ios/Podfile` — `OKTracer` лежит в spec-репозитории вендора, а поставляется
статическим `xcframework`, поэтому нужны и свой источник, и смена типа
линковки:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'

target 'Runner' do
  use_frameworks! :linkage => :static   # было: use_frameworks!
  # ...
end
```

Затем `pod install`. Токен передаётся из Dart, шагом ниже.

`OKTracer` поставляется **статическим** `xcframework`, а CocoaPods не позволяет
таргету с динамическими фреймворками получить статический бинарник транзитивно
— отсюда и смена типа линковки. Без неё `pod install` падает с ошибкой *«The 'Pods-Runner' target has
transitive dependencies that include statically linked binaries»*. То же самое
требуют статические фреймворки Firebase; Flutter это поддерживает.

Затем `pod install`. На iOS `appToken` **передаётся** из Dart.

### Web

Добавлять нечего: реализация на чистом Dart уже внутри пакета. Токен —
`appToken` JS-проекта, передаётся шагом ниже.

**3. Оберните запуск приложения.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      iosAppToken: 'токен-iOS-проекта',
      webAppToken: 'токен-JS-проекта',
      release: '1.0.0',
      environment: 'prod',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

Поля Android здесь нет: его SDK читает токен из ресурса, который создаёт
Gradle-плагин, и переопределить это из Dart нечем. Если платформа одна, хватит
общего `appToken` — он используется там, где своего не задано.

**`appToken` — не секрет,** и прятать его особого смысла нет: Gradle-плагин
вшивает его в APK (он лежит в `resources.arsc` и `classes.dex` — можно
распаковать и убедиться), а на web он и так в JS-бандле. Он опознаёт проект, а
не даёт доступ к нему. Поэтому берите любой способ, какой привычнее:

* строкой в коде или в отдельном файле с настройками рядом с исходниками — так
  же устроен `firebase_options.dart` у Firebase;
* `--dart-define=TRACER_APP_TOKEN=…` вместе с
  `appToken: String.fromEnvironment('TRACER_APP_TOKEN')`, если не хотите
  держать его в git;
* из собственного конфига в рантайме — `TracerOptions` принимает обычную
  строку, откуда вы её взяли, ему всё равно.

**А вот `pluginToken` — секрет.** Им подписывается загрузка маппингов и
символов, он нужен только сборке и в приложение не попадает: в APK его нет.
Ему место в окружении сборки и в секретах CI, а не в репозитории.

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
* **iOS или web: `appToken` приехал пустым.** Чаще всего это выбранный вариант
  с `--dart-define`, где флаг забыли при сборке: `String.fromEnvironment` без
  него возвращает пустую строку. Пакет честно сообщает, что `appToken` не
  задан, и остаётся выключенным.

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

## Чем это отличается от firebase_crashlytics

Вопрос законный: Crashlytics бесплатен, официален и делает то же самое.

| | apptracer_flutter | firebase_crashlytics |
|---|---|---|
| Кто делает | независимая обёртка, с VK и OK.TECH не связана | Google, официальный плагин |
| Платформы | Android, iOS, web | Android, iOS, macOS |
| Куда уходят отчёты | серверы Tracer (VK / OK.TECH) | инфраструктура Google |
| Перехват ошибок Dart | `FlutterError.onError`, `PlatformDispatcher.onError`, guarded zone | `FlutterError.onError`, `PlatformDispatcher.onError` |
| Обфусцированный Dart | вручную: `flutter symbolize` по сохранённому файлу символов | `firebase crashlytics:symbols:upload` на Android, на Apple автоматически |

**Про данные.** Утверждать можно немногое, и лучше без юридических формулировок:
Crashlytics отправляет отчёты в инфраструктуру Google, Tracer — в свою. Если
важно, чтобы данные не уходили за пределы российского периметра, это и есть
причина смотреть в сторону Tracer. При этом крашлог не обезличен сам по себе —
персональные данные в него кладёте вы: `userId`, кастомные ключи, breadcrumbs,
текст исключения. Что именно уходит с устройства из этого пакета и что
добавляет от себя SDK вендора, перечислено в
[privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md). Подходит ли это под 152-ФЗ в вашем
случае — вопрос к вашему юристу, а не к README.

**Про обфускацию, честно.** Здесь Crashlytics объективно лучше. Он читает
обфусцированный релиз сам, а тут это ручная работа: канал загрузки символов
Dart у Tracer есть, загрузка проходит — но символы не применяются, потому что
нативный репортёр пишет `libapp.so` с нулевым build id. Измерено 27.08.2026,
разбор в [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md). Пока это не
починят на стороне вендора, рабочий путь один: хранить файл символов сборки и
разбирать трейс через `flutter symbolize`.

## Что вы получите, кроме ошибок Dart

Ошибки Dart — работа этого пакета, и они одинаково доезжают со всех платформ.
Неровно распределено остальное, потому что этим занимается нативный SDK
вендора:

* **Android** — нативные краши и ANR. ANR только с Android 11: `AnrReporter` в
  `tracer-crash-report` 1.4.0 строит отчёт из `ApplicationExitInfo`, а тот
  появился в API 30, и ниже `setSendAnr(true)` не даёт ничего.
* **iOS** — нативные краши и счётчик зависаний.
* **Web** — только ошибки Dart, нативных крашей там нет по определению.

Десктоп и Аврора не поддерживаются, и в списке платформ пакета их нет. Почему —
в разделе [Десктоп и Аврора](#десктоп-и-аврора).

На платформе без реализации пакет инертен: `isEnabled` равен `false`,
печатается одна диагностическая строка, ничего не бросается, приложение
стартует. Подробности — в
[platform-matrix.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).

## Десктоп и Аврора

В этом релизе они **не поддерживаются**. Нативного SDK для Flutter там нет, и ни одна сборка под них ни разу не проверялась на живом проекте.
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
