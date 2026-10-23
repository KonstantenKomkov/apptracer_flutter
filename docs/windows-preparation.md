# Windows x64: подготовка реализации

Дата: 2026-10-23. Частичная реализация №3; задача остаётся открытой.

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
Push-Location packages/apptracer_flutter_desktop/example
flutter pub get
flutter build windows --release
Pop-Location
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

GitHub Actions `.github/workflows/windows.yml` выполняет эти же проверки,
сохраняет JSON, runtime bundle, PDB и разрешённый lockfile. До получения результата
workflow наличие YAML не считается успешно выполненной проверкой Windows.

## Открытые проверки и ограничения

- Dart analyze/tests на macOS проверяют регистрацию, инертный bootstrap,
  конфигурацию и отказ по отсутствующим credentials/cleanup. Они не загружают DLL.
- Default `preservePreviousReports: false` на Windows возвращает `unsupported`
  (`windows_previous_report_cleanup_unavailable`) до запуска SDK. Иначе SDK мог бы
  отправить прежние отчёты вопреки выбранной политике. Пример явно использует `true`.
- Windows native stop/clear, запрет replay после stop и отмена запросов — №8.
  Отсутствие purge не маскируется успешным `disabled`.
- Live Tracer, native crash/restart, grouping и читаемые native/Dart AOT стеки
  остаются отдельной приёмкой. В UI есть явная кнопка падения с подтверждением.
  Автоматический native crash включается только `TRACER_SCENARIO=native-crash`.
  Проверять без отладчика, затем перезапускать с `TRACER_SCENARIO=idle` и тем же DSN.
- PDB сохраняется от этой сборки, но соответствие ID и загрузка в Tracer — №5.
- MSVC runtime на чистой Windows, readonly install directory и Windows ARM64
  ещё не проверены. Проверка переноса в CI не заменяет чистую пользовательскую ОС.

Бинарники, DSN, plugin tokens и SDK-кэши не коммитятся. Автоматический workflow
не обращается к Tracer и не использует секреты репозитория.
