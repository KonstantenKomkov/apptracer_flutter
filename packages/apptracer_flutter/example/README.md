# Пример apptracer_flutter

Показывает все пути ошибок, которые покрывает `apptracer_flutter`, и заодно
служит той сборкой, на которой CI доказывает, что интеграции под Android, iOS и
web компилируются.

English version: [README.en.md](README.en.md).

## Запуск

В этой папке лежит `Makefile`, где команды под каждую платформу уже прописаны:
`make android`, `make ios`, `make web`; `make` без аргументов покажет весь
список. `.vscode/launch.json` повторяет тот же набор для запуска из редактора —
так что открыть эту папку отдельным проектом достаточно. Из корня репозитория
те же цели называются `make example-android` и так далее.

Ниже — то, что эти цели выполняют на самом деле.

Токены берутся из окружения, в коде их нет.

У каждой платформы свой проект в Tracer, а значит своя пара токенов:

```sh
export TRACER_APP_TOKEN=...        # Android, читается Gradle-плагином
export TRACER_PLUGIN_TOKEN=...     # Android, загрузка mapping и символов
export TRACER_IOS_APP_TOKEN=...    # iOS
export TRACER_IOS_PLUGIN_TOKEN=... # iOS, загрузка dSYM
export TRACER_JS_APP_TOKEN=...     # web
export TRACER_JS_PLUGIN_TOKEN=...  # web, загрузка сорсмап
```

На Android токен приходит из Gradle-плагина, который на этапе сборки пишет его
в строковый ресурс, — `--dart-define` там игнорируется:

```sh
flutter run --release -Ptracer.enabled=true
```

На iOS и web токен передаётся из Dart, каждый свой:

```sh
flutter run -d <iphone> --dart-define=TRACER_APP_TOKEN=$TRACER_IOS_APP_TOKEN
flutter run -d chrome   --dart-define=TRACER_APP_TOKEN=$TRACER_JS_APP_TOKEN
```

Sentry DSN не нужен нигде: web говорит с собственным приёмом Tracer по тому же
`appToken`, а платформы, для которых у вендора нет SDK, этот пример не
поддерживает.

Без токенов приложение всё равно запускается: интеграция сообщает, что она
выключена, а кнопки просто поднимают ошибки локально. Это и есть путь мягкой
деградации, и его стоит увидеть хотя бы раз.

## Android

Gradle-плагин Tracer здесь подключается по флагу, чтобы чекаут без учётных
данных продолжал собираться:

```sh
flutter build apk --release -Ptracer.enabled=true \
  --obfuscate --split-debug-info=build/symbols
```

`android/app/tracer.gradle` валит сборку, если `-Ptracer.enabled=true` передан
без обоих токенов, — вместо того чтобы выпустить релиз, чьи краши уходят в
никуда. Настоящее приложение применяет плагин безусловно, см.
[README](../README.md#android).

После обфусцированной сборки проверьте, что файл символов соответствует
бинарнику:

```sh
../../../tool/verify_build_id.sh
```

Инкрементальная сборка может оставить шаг Dart AOT в состоянии `UP-TO-DATE` и
не перегенерировать файл символов — см.
[symbolication.md](../../../docs/symbolication.md), находка 3.

## iOS

Сборка на устройство требует вашего Team ID. В проекте его нет намеренно:
он привязан к конкретному разработчику, а не к примеру. Скопируйте шаблон и
впишите свой:

```sh
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
```

Team ID лежит в `security find-identity -v -p codesigning`, в скобках после
имени. Файл в `.gitignore`. Без него сборка под симулятор работает как обычно,
а сборка на устройство падает с внятным сообщением Xcode про отсутствие
команды.

Ещё понадобится Apple ID, добавленный в Xcode: **Settings → Accounts**.
Сертификата в связке ключей недостаточно — без учётной записи Xcode не выпустит
профиль и скажет `No Account for Team`.

`ios/Podfile` объявляет spec-репозиторий вендора и использует
`use_frameworks! :linkage => :static`, которого требует статический xcframework
`OKTracer`.

```sh
flutter build ios --simulator --debug
```

## Web

```sh
flutter build web --release --source-maps
TRACER_PLUGIN_TOKEN=... ../../../tool/upload_web_sourcemaps.sh 1.0.0
```

## Автопрогон

```sh
make live-check
```

Запускает `integration_test/live_verification_test.dart` на подключённом
Android-устройстве: нажимает кнопки в порядке, который требуют проверки из
[live-verification-plan.md](../../../docs/live-verification-plan.md), проверяет
то, что видно со стороны Dart, и печатает список того, что осталось сверить в
консоли Tracer глазами. Что именно он не делает и почему — написано в шапке
самого теста.

## Что делают кнопки

| Кнопка | Какой путь проверяет |
|---|---|
| Бросить синхронно | необработанная синхронная ошибка в колбэке |
| Бросить асинхронно | бросок из `Timer.run`, пойманный защищённой зоной |
| Бросить из future без await | асинхронная ошибка без `await` |
| Бросить внутри build() виджета | `FlutterError.onError` |
| Отправить пойманную ошибку | явный `Tracer.recordError` с `issueKey` и кастомными ключами |
| Добавить breadcrumb | `Tracer.log` |
| Задать кастомный ключ | `Tracer.setCustomKey` |
| Остановить сбор | `Tracer.stopCollection`, включая восстановление обработчиков |
| Уронить процесс нативно | SIGSEGV собственному процессу — путь нативного SDK, не Dart |
| Заблокировать главный поток (ANR) | 10 секунд на главном потоке Android — путь ANR-watchdog |

Последние две кнопки видны только на Android и завершают сеанс: после них
приложение надо запускать заново. Под ними лежит `MainActivity` примера, а не
код пакета.
