# Windows x64: сборка и проверка

Обновлено 24 октября 2026. Текущая реализация использует официальный
Sentry Flutter 9.30.1 / sentry-native 0.16.6 с backend `native` и
`sentry-crash.exe`. Реализованы stop/clear, отзыв replay и автоматические
исходные кадры Dart/native. [Приёмка и границы](windows-local-acceptance.md).
Прежние [Crashpad CI](windows-native-acceptance.md) и
[PDB-проверки](windows-symbols-acceptance.md) сохранены как история.

## Инструменты и сборка

На пользовательском компьютере Flutter находится в `D:\Tools\flutter`,
Build Tools — `D:\Tools\VisualStudio\BuildTools`, pub cache — `D:\Tools\PubCache`,
TEMP — `D:\Tools\Temp`, native sources — `D:\Tools\apptracer-native`.
Общие компоненты Windows SDK/installer используют также существующие пути C.
Старые Flutter/Visual Studio на C не удалялись.

Из корня репозитория:

```powershell
. ./tool/use_windows_tools.ps1
./tool/build_windows_desktop.ps1 -NativeDepsDirectory D:\Tools\apptracer-native -Obfuscate
$example = 'packages/apptracer_flutter_desktop/example'
$bundle = "$example/build/windows/x64/runner/Release"
$dumper = 'D:\Tools\Symbols\dump-syms\dump_syms.exe'
python -X utf8 tool/prepare_windows_runtime_symbols.py --bundle $bundle --pdb "$example/build/symbols/native/apptracer_desktop_example.pdb" --dump-syms $dumper
python -X utf8 tool/prepare_linux_dart_runtime_symbols.py --windows --bundle $bundle --symbols "$example/build/symbols/dart/app.windows-x64.symbols" --dump-syms $dumper
$env:TRACER_WINDOWS_SENTRY_DSN = '<Sentry DSN проекта Tracer>'
& "$bundle/apptracer_desktop_example.exe"
```

Helper выбирает native backend и включает `core.longpaths` только для процесса.
Карты исходников опциональны: пропустить две команды `prepare_*`, если нельзя
раскрывать имена функций/пути файлов. Полные PDB/DWARF хранить отдельно:
MSVC оставляет runner `.pdb` рядом с EXE в build output, его не нужно включать
в распространяемый архив. Каталог `symbols/<name>.pdb/` — компактная карта,
его не путать с полным PDB-файлом. Готовый архив этой проверки полных PDB не содержит.
Plugin token не нужен для клиентских карт и не передаётся приложению.

Переносить весь Release: EXE, Flutter/Sentry/helper DLL, `sentry-crash.exe`,
`sentry-wer.dll`, app-local MSVC DLL, `data/` и выбранные карты `symbols/`.
Очередь — `%LOCALAPPDATA%/apptracer_desktop/<exe-name>/v1`, независимо от каталога
установки. Старые кэши Sentry/Crashpad не импортируются и не удаляются.

## Воспроизводимая проверка

```powershell
python -X utf8 -m unittest discover -s tool/tests -v
foreach ($scenario in @('disabled', 'deferred', 'smoke')) {
  python -X utf8 tool/check_windows_desktop.py --app $bundle --scenario $scenario --output "build/windows-local/$scenario.json"
  if ($LASTEXITCODE -ne 0) { throw $scenario }
}
foreach ($scenario in @('lifecycle', 'grouping', 'native', 'native-revoked', 'native-discard', 'native-inflight', 'dart-retry', 'dart-online', 'dart-revoked', 'dart-discard', 'missing-handler', 'unwritable-storage', 'missing-native-symbols', 'mismatched-native-symbols', 'junction-storage', 'junction-queue-entry', 'concurrent-owner', 'readonly-bundle')) {
  python -X utf8 tool/check_windows_runtime.py --app $bundle --scenario $scenario --output "build/windows-local/$scenario.json"
  if ($LASTEXITCODE -ne 0) { throw $scenario }
}
foreach ($mode in @('resolved', 'missing', 'mismatched')) {
  python -X utf8 tool/check_linux_dart_display.py --windows --app $bundle --mode $mode --output "build/windows-local/dart-$mode.json"
  if ($LASTEXITCODE -ne 0) { throw $mode }
}
```

Все приёмники здесь локальные, с фиктивным DSN. Скрипты переносят bundle в
уникальный путь с пробелами/кириллицей и используют отдельный LOCALAPPDATA.
`dart-online` ждёт штатного retry SDK до 950 секунд. Native-сценарии намеренно
роняют только тестовое приложение; закрывается только его daemon.

Обновлённые `.github/workflows/windows.yml` и `windows-runtime.yml` собирают
обфусцированный release с точными картами и повторяют эти проверки без секретов.
Свежие GitHub Actions runs и артефакты перечислены в
[протоколе](windows-local-acceptance.md). Для отдельного runtime workflow можно
передать `build_run_id` успешного preparation run той же ветки; workflow
проверяет происхождение артефакта и совпадение исходников пакетов.
Установка во внешнее приложение —
[migration guide](desktop-migration.md#windows-consumer).
