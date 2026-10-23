# macOS: локальная проверка официального SDK

Дата: **2026-10-23**. Задачи [№2 и №4](tasks/development_v1.md).
Код адаптера: `dd26f96`; runner, регистрация и проверочный инструмент добавлены
следующим коммитом №4, содержащим этот протокол.

**Release-сборка, локальная доставка и появление трёх Dart-событий в Tracer подтверждены.**
Локальные сценарии ниже проверены собственным loopback-приёмником; отдельный
результат live-проверки приведён далее. Полная приёмка №4/11 остаётся открытой:
стек и поля карточек, native crash в Tracer ещё не подтверждены. Native purge/полный
lifecycle №8 также не завершены.

## Среда и состав

| Параметр | Фактически проверено |
| --- | --- |
| Host/runtime | macOS 27.0.1 (`26A434`), arm64 |
| Flutter / Dart | 3.47.4 / 3.13.3 |
| Xcode | 27.0 (`27A266a`) |
| CocoaPods | 1.17.0, с очищенными `GEM_HOME/GEM_PATH` |
| SDK | sentry_flutter/sentry 9.30.1, Sentry/HybridSDK 8.58.4 |
| Дополнительный плагин | package_info_plus 10.2.2 |
| Минимальный target runner | macOS 12.0; запуск на 12.0 не проверялся |
| Архитектуры файла | universal arm64 + x86_64; runtime проверен только arm64 |
| Release sandbox | app-sandbox + network.client; локальная подпись также содержит get-task-allow, distribution signing не проверялся |
| Запуск | прямой запуск executable из временной копии `.app`, вне IDE/checkout, без отладчика; путь содержит пробелы и кириллицу |

SHA-256 проверенного `Contents/MacOS/apptracer_desktop_example`:

```text
1e59b68b1cfd02acee404c0eda84d8ae45689b88521460f0403891d774ceff40
```

Пакет desktop подключён только в отдельный example. Регистрация macOS через
`dartPluginClass: SentryDesktopTracer` подтверждена в готовом приложении:
backend — `sentry-sdk`. Основной пакет не получил Sentry dependency.

## Результаты

| Сценарий | Результат |
| --- | --- |
| Handled Dart error | Одно событие, SDK `sentry.dart.flutter`, исходный стек, release/dist, ключ запуска, userId, breadcrumb |
| FlutterError | Одно событие; дополнительный перехватчик Sentry не создаёт дубль |
| Unhandled async error | Одно событие; процесс продолжает работать |
| Disabled bootstrap | Приложение готово, сбор выключен, 0 запросов за окно проверки |
| Deferred bootstrap | Приложение готово, сбор выключен, 0 запросов за окно проверки |
| Native SIGABRT | Процесс завершился; после нового запуска пришло одно fatal событие `sentry.cocoa.flutter`, platform `cocoa`, mechanism signal/SIGABRT, handled=false, правильный ключ запуска, 12 debug images |
| Дополнительная телеметрия smoke | Только три `event` item; sessions/performance/logs/metrics/replay не наблюдались |
| iOS regression | Существующий example собран для симулятора Debug; в приложении Flutter, App, OKTracer и TracerResources frameworks; iOS plugins: apptracer_flutter_ios и integration_test, Sentry отсутствует |

Локальные идентификаторы событий (не ссылки на события в Tracer):

- Dart: `fce684788b4c443b86ccdaa2ece9b49b`.
- FlutterError: `e620617b1076450dbb73fdd7516d4786`.
- Async: `4ead763461d3452fa92bf19dbc4d37e6`.
- Native: `59e37e5779424f83935b831819ef7fe8`.

Полные отчёты находятся локально в `build/macos-acceptance/{smoke,disabled,deferred,native-crash}.json`.
Это генерируемые артефакты, в Git они не добавлены. Инструмент сохраняет сообщения
тестовых событий; рабочие DSN и plugin tokens не используются.

## Live-проверка Tracer: 23 октября 2026

Использован `TRACER_MACOS_SENTRY_DSN` из игнорируемого `.env.tracer`. Значение DSN
не выводилось и не добавлялось в Git. Запуск исходного release executable:
commit `caa6def810428b0d9a3e724c1841bdab006d4b89`, начало `12:41:53 UTC`,
сценарий `smoke`, метка `probe_run=macos-live-c28b9953f13e`.
SDK сообщил `enabled=true backend=sentry-sdk state=enabled`; приложение оставалось
работоспособным в течение 20 секунд, затем проверочный процесс был остановлен.
Локальная запись запуска: `build/macos-acceptance/live-smoke.json`.

Пользователь подтвердил доставку снимком консоли от 15:53:18 МСК: три отчёта
версии `1.0.0`, по одному событию и одному устройству для каждого:

- `StateError — Bad state: desktop handled probe`;
- `FlutterError — desktop FlutterError probe`;
- `StateError — Bad state: desktop async probe`.

В списке у всех трёх строк показано `Stacktrace not available`; фрагменты кадров
видны в заголовках. Это наблюдение списка, а не доказательство отсутствия стека
в карточке. В сохранённых envelopes локального запуска того же executable
`exception.values[].value` содержит только сообщение, а
`exception.values[].stacktrace.frames` содержит 2/2/13 кадров соответственно:
функции, имена файлов, пути и номера строк. Исходный Dart-стек дополнительно лежит
в `contexts.apptracer.dart_stack_trace`. Причина отображения в Tracer пока не установлена;
на основании одного списка формат отправки не менялся.

В [документации Tracer](https://apptracer.ru/doc/other-platforms/quick-start/)
описано отображение Context/Extra в «События → Данные → Context», breadcrumbs —
в «События → Логи». Следующая проверка — карточка события, стек, исходный Context,
userId и `probe_run`. Их наличие, группировка повторных событий и native crash
в Tracer данным снимком не подтверждены. Метка запуска на снимке не раскрыта;
сопоставление основано на подтверждении пользователя и трёх названиях проб.

## Воспроизведение

Из `packages/apptracer_flutter_desktop/example`:

```sh
flutter pub get
env -u GEM_HOME -u GEM_PATH flutter build macos --release --no-pub
flutter analyze
flutter test --reporter expanded
```

Из корня репозитория, последовательно для каждого сценария:

```sh
python3 tool/check_macos_desktop.py \
  --app packages/apptracer_flutter_desktop/example/build/macos/Build/Products/Release/apptracer_desktop_example.app \
  --scenario smoke --output build/macos-acceptance/smoke.json
```

Повторить с `disabled`, `deferred`, `native-crash` и соответствующим output.
Native-crash намеренно вызывает `abort()` в собственном процессе примера.
Скрипт привязывает ephemeral receiver к 127.0.0.1, назначает фиктивный DSN,
разбирает настоящие SDK envelopes и проверяет события/количество/ключ запуска.

Из `packages/apptracer_flutter/example` для iOS regression:

```sh
env -u GEM_HOME -u GEM_PATH flutter build ios --simulator --debug --no-codesign
```

Прямой `xcodebuild` до подготовки Flutter первоначально не прошёл из-за старой
CocoaPods resources phase и отсутствующего подготовленного Flutter framework.
Штатная Flutter-команда после `pod install` успешно подготовила SPM framework и
собрала приложение. Автоматические изменения iOS project/scheme/plist, сделанные
тулчейном при проверке, не включены в desktop-коммит; код iOS-интеграции не менялся.

## Ревью и пределы проверки

Проверены diff, plist entitlements, регистрация и состав dependencies. Релевантные
проверки: анализ без замечаний, 6 SDK-тестов адаптера, 1 UI-тест подтверждения
native crash, 80 регрессионных тестов основного пакета, release macOS build,
4 локальных runtime сценария и iOS simulator build. Парсер приёмника дополнительно
проверен на length-delimited attachment с newline и UTF-8 event.

Disabled/deferred — ограниченное наблюдение текущего процесса; оно не доказывает
очистку старых файлов, отсутствие всех фоновых запросов или поведение после logout.
Не проверены: поля и стек карточек Tracer, grouping повторных событий, native ingest
и символизация в Tracer, release iOS,
runtime macOS x86_64, распространение подписанного приложения, native purge,
offline/in-flight/account-switch и crash после stop. Эти проверки остаются в
№5/8/11. Windows и Аврора не считаются проверенными результатами macOS.
