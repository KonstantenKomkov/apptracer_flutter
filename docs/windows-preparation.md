# Windows x64: подготовка реализации

Дата: 2026-10-23. Частичная реализация №3; задача остаётся открытой.

**Подтверждено на Windows CI:** release-сборка x64 и локальная доставка Dart-событий.
[Полный прогон 39994523733](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39994523733)
успешно выполнил сборку и все три transport-сценария одним циклом.
[Прогон сборки 39992634203](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39992634203)
успешно собрал приложение, но выявил ошибку chunked-декодирования проверочного
приёмника. После исправления приёмника
[прогон 39994294312](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39994294312)
успешно проверил **тот же** release-артефакт: disabled, deferred, smoke.
Исходники пакетов и приложения между сборкой `25fe9ca` и проверкой `d8522a6`
не менялись. Проверены запуск вне checkout в пути с пробелами/кириллицей,
отсутствие отправки в disabled/deferred и ровно три ошибки с user/key/breadcrumbs.
Это loopback-приёмник, не Tracer. Отдельная последующая
[native-проверка](windows-native-acceptance.md) прошла crash/minidump/restart
и восстановление той же очереди после HTTP 503;
stop/clear остаются открытыми.

Добавлены автоматическая Dart-регистрация optional desktop-пакета, Windows runner,
канал явного native crash, выбор `TRACER_WINDOWS_SENTRY_DSN`, сохранение runner PDB
и отдельный Windows workflow. Runner создан шаблоном Flutter 3.47.4, официальный
Sentry Flutter закреплён на 9.30.1. Проверяемая архитектура — только x64.

Поставка SDK управляется CMake официального пакета: `sentry.dll`,
`crashpad_handler.exe`, `crashpad_wer.dll`. При переносе нужен весь каталог Release
с `flutter_windows.dll`, остальными DLL и `data/`. Системный MSVC runtime должен
присутствовать на целевом компьютере. Скрипт не устанавливает его автоматически.

## Локальная проверка на Windows

Сначала выполнить [preflight](windows-preflight.md). Из корня репозитория:

```powershell
./tool/build_windows_desktop.ps1
python tool/check_windows_desktop.py --app packages/apptracer_flutter_desktop/example/build/windows/x64/runner/Release --scenario disabled --output build/windows-acceptance/disabled.json
python tool/check_windows_desktop.py --app packages/apptracer_flutter_desktop/example/build/windows/x64/runner/Release --scenario deferred --output build/windows-acceptance/deferred.json
python tool/check_windows_desktop.py --app packages/apptracer_flutter_desktop/example/build/windows/x64/runner/Release --scenario smoke --output build/windows-acceptance/smoke.json
```

Каждая команда должна завершиться с кодом 0. Скрипт проверяет комплект файлов,
переносит приложение за пределы checkout в путь с пробелами/кириллицей и использует
только локальный приёмник с фиктивным DSN. Disabled/deferred должны стартовать
без SDK и сетевых запросов; smoke — отправить ровно три события с разными
ошибками, userId, ключом запуска и breadcrumbs. GUI-приложение сообщает готовность
через отдельный временный файл, поскольку консоль может отсутствовать.

Build helper включает Git `core.longpaths` только для процесса сборки и задаёт
короткий каталог native-зависимостей в TEMP, отдельный для этого checkout.
Окружение восстанавливается после завершения; глобальная конфигурация Git
не меняется. Каталог можно задать через `-NativeDepsDirectory C:\at-deps`.
Первый Windows CI обнаружил превышение длины путей при checkout вложенных
Sentry/Crashpad submodules; эти настройки устраняют причину этого сбоя.

GitHub Actions `.github/workflows/windows.yml` выполняет эти же проверки,
сохраняет JSON, runtime bundle, PDB и разрешённый lockfile. Временный workflow
повторной проверки готового артефакта удалён после успешного прогона.

## Открытые проверки и ограничения

- Dart analyze/tests на macOS и Windows проверяют регистрацию, инертный bootstrap,
  конфигурацию и отказ по отсутствующим credentials/cleanup. Они не загружают DLL.
- Default `preservePreviousReports: false` на Windows возвращает `unsupported`
  (`windows_previous_report_cleanup_unavailable`) до запуска SDK. Иначе SDK мог бы
  отправить прежние отчёты вопреки выбранной политике. Пример явно использует `true`.
- Windows native stop/clear, запрет replay после stop и отмена запросов — №8.
  Отсутствие purge не маскируется успешным `disabled`.
- Native crash/restart проверен через loopback. Live Tracer, grouping и читаемые
  native/Dart AOT стеки остаются отдельной приёмкой. В UI есть явная кнопка падения с подтверждением.
  Автоматический native crash включается только `TRACER_SCENARIO=native-crash`.
  Проверять без отладчика, затем перезапускать с `TRACER_SCENARIO=idle` и тем же DSN.
- PDB сохраняется от этой сборки, но соответствие ID и загрузка в Tracer — №5.
- MSVC runtime на чистой Windows, readonly install directory и Windows ARM64
  ещё не проверены. Проверка переноса в CI не заменяет чистую пользовательскую ОС.

Бинарники, DSN, plugin tokens и SDK-кэши не коммитятся. Автоматический workflow
не обращается к Tracer и не использует секреты репозитория.
