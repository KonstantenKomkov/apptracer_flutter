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

Нужны они в разное время. `appToken` — приложению, чтобы отправлять события;
без него ничего не работает. `pluginToken` — сборке, чтобы залить символы, и до
первого релиза он не нужен вовсе.

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
        appToken = "ANDROID_APP_TOKEN"
        pluginToken = providers.gradleProperty("androidPluginToken").orNull
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

Два ключа подставляются по-разному не для красоты. `appToken` плагин всё равно
вшивает в APK, прятать нечего — пусть лежит строкой. `pluginToken` подписывает
загрузку маппингов и символов, в приложение не попадает и в репозитории ему не
место.

Положите его в `~/.gradle/gradle.properties`:

```properties
androidPluginToken=...
```

Этот файл лежит вне репозитория, и Gradle читает его сам — способ запуска не
меняется ничем: и `flutter build`, и кнопка Run в IDE увидят значение.

В CI файла нет, и заводить его не надо: то же свойство приходит переменной
`ORG_GRADLE_PROJECT_androidPluginToken` — Gradle подставляет такие переменные в
свойства проекта, — или флагом `-PandroidPluginToken=…`. В GitHub Actions:

```yaml
- run: flutter build apk --release
  env:
    ORG_GRADLE_PROJECT_androidPluginToken: ${{ secrets.ANDROID_PLUGIN_TOKEN }}
```

Класс `TracerApplication` из пакета подключается одним из двух способов —
результат одинаковый, выберите любой.

**А. В манифесте.** У тега `<application>` в
`android/app/src/main/AndroidManifest.xml` уже есть `android:name` — в шаблоне
Flutter он равен `"${applicationName}"`. Поменяйте **только это значение**,
соседние атрибуты ваши и остаются как были:

```xml
<application
    android:name="ru.apptracer.flutter.TracerApplication"
    android:label="my_app"
    android:icon="@mipmap/ic_launcher">
```

**Б. Плейсхолдером из Gradle**, если манифест трогать не хочется. В
`android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        manifestPlaceholders["applicationName"] =
            "ru.apptracer.flutter.TracerApplication"
    }
}
```

В Groovy-файле (`android/app/build.gradle`) тот же вызов пишется иначе:

```groovy
android {
    defaultConfig {
        manifestPlaceholders += [
            applicationName: "ru.apptracer.flutter.TracerApplication",
        ]
    }
}
```

Способ Б удобнее, когда манифест общий для сборок с Tracer и без него. В примере
этого репозитория взят он — только подставляется собственный наследник,
`TracerHostApplication`.

`TracerApplication` включает мягкий рейт-лимит на нефатальные, и это не
мелочь: жёсткий дефолт Tracer — **8 нефатальных за сессию**
(`LIMIT_MAX_NON_FATALS_PER_SESSION`), а каждая ошибка Dart, которую шлёт этот
пакет, — нефатальная. То есть упрётесь вы именно в этот потолок, и упрётесь
молча. Рейт-лимит поднимает его до 10 в час, и вендор сам рекомендует его
включать.

Если свой `Application` уже есть — наследуйтесь и дополняйте список, а не
заменяйте его:

```kotlin
class MyApplication : TracerApplication() {
    override val tracerConfiguration: List<TracerConfiguration>
        get() = super.tracerConfiguration + CoreTracerConfiguration.build {
            setDebugUpload(true)
        }
}
```

Поведением пакета по умолчанию это, к сожалению, быть не может: SDK читает
конфигурацию только у объекта `Application`, а плагин — не он.

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

Затем `pod install`. `appToken` передаётся из Dart, шагом ниже.

`pluginToken` iOS-проекта здесь не участвует: он нужен при загрузке `dSYM`, без
которой нативные краши в консоли остаются нечитаемыми.

Загружаются они сами. При `pod install` пакет добавляет в `Runner.xcodeproj`
фазу сборки, и она отправляет `dSYM` при каждой **release**-сборке — так же, как
это делает Firebase Crashlytics. Вызывать ничего не нужно, нужен только токен, и
взять его фаза может из двух мест.

Первое — файл `ios/tracer_plugin_token`, рядом с `Podfile`. Создайте его и
положите внутрь одну строку: `pluginToken` iOS-проекта из консоли Tracer.
Выглядит файл так:

```
e4f1b0c2-8a7d-4c19-9f3e-2b6d5a0c7e18
```

Файл содержит секрет, поэтому добавьте его в `.gitignore`.

Второе — переменная окружения, и в CI обычно берут её: фаза читает
`TRACER_IOS_PLUGIN_TOKEN`, а если её нет — `TRACER_PLUGIN_TOKEN`. Тогда файл не
нужен.

Без токена фаза пишет предупреждение и пропускает загрузку, а при неудачной
отправке — предупреждение и продолжает: ронять архив из-за сетевой ошибки хуже,
чем собрать его без символов.

Отключается двумя способами: удалить фазу в Xcode (она подписана
`[apptracer_flutter]`) или выставить `TRACER_SKIP_IOS_PHASE=1` — тогда
`pod install` не тронет файл проекта.

Если релиз собирается в CI и хочется, чтобы пайплайн **падал**, когда символы не
уехали, вызовите ту же загрузку явно — эта команда возвращает ненулевой код:

```sh
flutter build ipa
dart run apptracer_flutter:upload_symbols ios --token=IOS_PLUGIN_TOKEN
```

Наконец, тот же запрос вручную — если ничего ставить не хочется:

```sh
archive=build/ios/archive/Runner.xcarchive
plist=$archive/Products/Applications/Runner.app/Info.plist

cd $archive/dSYMs && zip -qry /tmp/dsym.zip ./*.dSYM

curl --location --http1.1 \
  --form versionName="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" \
  --form versionCode="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" \
  --form file=@/tmp/dsym.zip \
  "https://plugin-api.apptracer.ru/api/symbol/upload?symbolToken=IOS_PLUGIN_TOKEN"
```

Ответ `{"success":true}` — принято.

**Это делается на каждый релиз.** У каждой сборки свои `dSYM` с собственными
UUID, поэтому символы прошлой версии новой не подходят. Версия здесь читается из
собранного `Info.plist`, а не пишется руками: она обязана совпасть с той, что
шлёт приложение, иначе символы лягут к другой версии — молча.

И делать это надо **до того, как придут первые краши**: Tracer применяет символы
только к событиям, полученным после загрузки, пересимволизации у него нет.
Поэтому место этой команде — в релизном пайплайне или в Run Script фазе Xcode,
а не в списке дел, который можно забыть.

`OKTracer` поставляется **статическим** `xcframework`, а CocoaPods не позволяет
таргету с динамическими фреймворками получить статический бинарник транзитивно
— отсюда и смена типа линковки. Без неё `pod install` падает с ошибкой *«The 'Pods-Runner' target has
transitive dependencies that include statically linked binaries»*. То же самое
требуют статические фреймворки Firebase; Flutter это поддерживает.

Затем `pod install`. На iOS `appToken` **передаётся** из Dart.

### Web

Добавлять нечего: реализация на чистом Dart уже внутри пакета. Токен —
`appToken` JS-проекта, передаётся шагом ниже.

`pluginToken` JS-проекта, как и на iOS, нужен не для событий, а для загрузки
сорсмап — без них стектрейс из release-сборки остаётся минифицированным. Тут у
вендора инструмента нет, поэтому команда пакета — основной путь:

```sh
flutter build web --release --source-maps
dart run apptracer_flutter:upload_symbols web --token=WEB_PLUGIN_TOKEN
```

Она берёт из `build/web` только `.js` и `.map`, пакует их так, чтобы пути
совпали с путями в кадрах, и подставляет версию из `pubspec.yaml` — она должна
совпасть с `release` в `TracerOptions`.

Тот же запрос вручную:

```sh
flutter build web --release --source-maps
cd build/web && zip -qr /tmp/sourcemaps.zip . -i '*.js' '*.map'

curl --location \
  -F sourcemapToken=WEB_PLUGIN_TOKEN \
  -F versionName=1.0.0 \
  -F file=@/tmp/sourcemaps.zip \
  https://plugin-api.apptracer.ru/api/sourcemap/upload
```

Архив собирается **изнутри** `build/web`, чтобы пути в нём совпали с путями в
кадрах: Tracer сопоставляет сорсмапы по пути файла, а не по Debug ID.
`versionName` должен совпасть с `release`, который передан в `TracerOptions`.

Как и на iOS — на каждый релиз и до выкладки: сорсмапы применяются только к
тому, что пришло после их загрузки.

**3. Оберните запуск приложения.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      iosAppToken: 'IOS_APP_TOKEN',
      webAppToken: 'WEB_APP_TOKEN',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

Поля Android здесь нет: его SDK читает токен из ресурса, который создаёт
Gradle-плагин, и переопределить это из Dart нечем. Если платформа одна, хватит
общего `appToken` — он используется там, где своего не задано.

`appRunner` — это запуск вашего приложения, отданный пакету функцией: обычно
`() => runApp(const MyApp())`. Пакет вызывает её сам, уже внутри охраняемой
зоны. Только так в зону попадают асинхронные ошибки, которых никто не
`await`-ил, и только так `WidgetsFlutterBinding.ensureInitialized()` оказывается
в той же зоне, что и `runApp`, — иначе Flutter пожалуется на несовпадение зон.

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
* [Release-сборки со `--split-debug-info`](#release-сборки-со---split-debug-info) —
  что станет со стектрейсом и как его прочитать.

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
| Чьи SDK и куда уходят отчёты | нативные SDK VK / OK.TECH, приём — `*.apptracer.ru`: сети «Odnoklassniki Services» и «VK Services», RU, AS47764 | SDK Google, приём в инфраструктуре Google |
| Платформы | Android, iOS, web | Android, iOS, macOS |
| Куда уходят отчёты | серверы Tracer (VK / OK.TECH) | инфраструктура Google |
| Перехват ошибок Dart | `FlutterError.onError`, `PlatformDispatcher.onError`, guarded zone | `FlutterError.onError`, `PlatformDispatcher.onError` |
| Обфусцированный Dart | вручную: `flutter symbolize` по сохранённому файлу символов | `firebase crashlytics:symbols:upload` на Android, на Apple автоматически |
| Нативные символы каждой сборки | Android — сам Gradle-плагин; iOS — сборочная фаза, которую пакет прописывает сам; web — команда пакета | Apple — сама, сборочной фазой Xcode; Android — командой Firebase CLI |

**Про данные.** Это и есть основная причина выбирать Tracer: у Crashlytics SDK
и приём принадлежат Google, у Tracer — VK / OK.TECH, с приёмом в российских
сетях (по whois — AS47764, Москва), так что трансграничной передачи
не происходит — но обезличенным крашлог от этого не становится, персональные
данные в него кладёте вы, и что именно уходит с устройства, перечислено в
[privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).

## Что вы получите, кроме ошибок Dart

Ошибки Dart — работа этого пакета, и они одинаково доезжают со всех платформ.
Неровно распределено остальное, потому что этим занимается нативный SDK
вендора:

* **Android** — нативные краши и ANR. ANR только с Android 11: `AnrReporter` в
  `tracer-crash-report` 1.4.0 строит отчёт из `ApplicationExitInfo`, а тот
  появился в API 30, и ниже `setSendAnr(true)` не даёт ничего.
* **iOS** — нативные краши и счётчик зависаний.
* **Web** — только ошибки Dart, нативных крашей там нет по определению.

На платформе без реализации пакет инертен: `isEnabled` равен `false`,
печатается одна диагностическая строка, ничего не бросается, приложение
стартует. Подробности — в
[platform-matrix.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).

## Использование

`appRunner` — та самая функция запуска из шага 3 — вызывается **ровно один раз
в любом сценарии**: при обычном старте, при запрете сбора политикой, при падении
инициализации нативного SDK и на платформе без реализации. Сборщик ошибок,
способный не дать приложению запуститься, хуже, чем отсутствие сборщика ошибок.

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

Это не аналитика: ни то, ни другое само по себе никуда не уходит. Breadcrumbs —
хронология того, что было перед падением, ключи — срез состояния на его момент;
и то и другое едет прицепом к отчёту об ошибке, а без ошибки просто вытесняется
из буфера. Ключ живёт до конца сеанса, поэтому его и снимают: иначе
`checkout_step=3` приедет с падения в настройках и собьёт с толку, а лишние
ключи вытеснят нужные — Tracer держит не больше 30.

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

Дословный стектрейс — исходный текст трейса, как его напечатал Dart, тот самый,
который умеет расшифровать `flutter symbolize`, — пишется в платформенный лог и
по умолчанию ограничен 8 КБ; разобранные кадры — 128 штуками.

Причина в том, что лог-буфер Android — **кольцевой**, на 64 КБ: всё
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
кадра и только по ним.

Ни файл, ни номер строки в ключ не входят: сам Tracer их игнорирует, чтобы
правка кода не разносила одну проблему по нескольким группам, и синтетический
ключ это свойство сохраняет. Свой `issueKey`, переданный в `recordError`, всегда
имеет приоритет.

## Release-сборки со `--split-debug-info`

При сборке со `--split-debug-info` — с `--obfuscate` или без него —
Dart-стектрейсы превращаются в адреса:

```
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
#00 abs 0000007938a1c2f0 virt 00000000002cc2f0
```

Пакет по умолчанию отправляет **дословный** стектрейс вместе с заголовком,
поэтому он остаётся расшифровываемым.

Текст лежит в логе события, во вкладке с логом, под строкой
`--- apptracer_flutter: verbatim Dart stack trace ---`. Скопируйте оттуда сам
трейс — от строки с `build_id:` до последнего кадра `#NN abs …` — и сохраните
в файл; служебные строки, которые пакет дописал сверху, включать не нужно.
Дальше:

```
flutter symbolize -d build/symbols/app.android-arm64.symbols -i trace.txt
```

Файл символов нужен **от той же сборки**: `build_id` в трейсе должен совпасть с
`app.<платформа>-<архитектура>.symbols`, который `--split-debug-info` положил
рядом с артефактом. Символы соседнего релиза не подойдут, поэтому архивируйте
их на каждую сборку. Если в конце трейса стоит
`... [apptracer_flutter] truncated, N more line(s)`, лог обрезал хвост:
расшифруются только уцелевшие кадры, а поднять предел можно через
`TracerOptions.maxRawStackTraceLogBytes`.

**У Tracer нет канала для загрузки Dart-файлов `--split-debug-info`** — это
подтвердил вендор, — поэтому расшифровка остаётся ручным шагом.
Прочитайте
[symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md)
до того, как выкатите такую сборку: там написано, что работает, что нет, и как
не узнать об этом слишком поздно.

## Лицензия

MIT. SDK вендора лицензируются отдельно, см.
[legal.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/legal.md).
