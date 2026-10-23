# macOS: символы проверенной release-сборки

Дата: **2026-10-23**. Прогресс задачи №5, не завершённая приёмка.
Runner и исходный native-отчёт описаны в [протоколе](macos-local-acceptance.md).
Бинарник не пересобирался: SHA-256 executable
`1e59b68b1cfd02acee404c0eda84d8ae45689b88521460f0403891d774ceff40`,
release `1.0.0`, dist `1`.

## Подготовка и загрузка

Использован официальный `symupload.py` из ранее проверенной поставки
[Tracer Aurora 0.1.15](https://nexus-external.vkteam.ru/repository/raw-tracer-native-public/aurora/tracer-native-aurora-0.1.15.zip).
Это общий инструмент: поставка содержит Darwin dumper для arm64/x86_64 и
`--target-platform darwin`. Протокол загрузки соответствует
[документации desktop](https://apptracer.ru/doc/native-desktop/symbolization/).
Код и бинарники поставки не добавлены в репозиторий и не изменялись;
у arm64 `dump_syms` восстановлен executable bit после распаковки ZIP.

| Файл инструмента | SHA-256 |
| --- | --- |
| symupload.py | `090e33aaf91da11e4e026b9c0af8c587996d854b3fad241f0b8e0ff8654fee73` |
| third_party/symbolstore.py | `147fa1ac04470c779d46d540a4db089b60e3806ec9f1b0a4f3b3f427f26e8b81` |
| dump_syms/macosx/arm64/dump_syms | `ebee9efdbd94ce6a063f1f3caf216c8f81ae3d20633db4157b4fd42ed17bcfe7` |

Подготовлены по две архитектуры шести модулей: runner, App, FlutterMacOS, Sentry,
sentry_flutter, package_info_plus. Для всех **12 MODULE identifiers** проверено
совпадение с UUID соответствующих dSYM (UUID без дефисов + `0` в Breakpad).
Каждый файл содержит FILE, FUNC и записи строк. Для arm64 runner:
`A070B3E2E343368FAD64F8D9122EFB300`, 5 FILE, 25 FUNC, 26 записей строк;
в символах есть `MainFlutterWindow.swift` и `MainFlutterWindow.awakeFromNib()`.
Не каждый оптимизированный кадр имеет исходную строку.

В `13:12:29 UTC` начата загрузка через vendor `do_upload` на
`https://plugin-api.apptracer.ru`, с проверкой TLS и без force-upload.
`TRACER_MACOS_PLUGIN_TOKEN` прочитан из игнорируемого `.env.tracer`, не выводился.
Токен передавался в памяти, а не в аргументах процесса; для запросов задан timeout
45 секунд. Все 12 upload-ответов содержат `success: true`. Повторный запрос
`/api/nativesymbol/exists` для этих модулей вернул HTTP 200 и `items: []`:
необходимость загрузки отсутствующих символов больше не заявлена.

Это подтверждение загрузки, не доказательство использования символов обработчиком
Cocoa/Sentry в Tracer. Для этого выполнена отдельная native-проба после загрузки.

## Локальные артефакты и воспроизведение

В игнорируемом `build/macos-acceptance/`:

- `symbols-manifest.json` — пути DWARF, SHA-256 и UUID dSYM;
- `breakpad-symbols/` — 12 подготовленных `.sym`;
- `symbol-preparation.json` — MODULE, число FILE/FUNC/строк и размеры;
- `symbol-upload.json`, `symbol-upload.log` — результат и очищенный лог загрузки;
- `symbol-availability.json` — повторная проверка всех 12 модулей;
- `live-native-symbols.json` — повторное падение и restart после загрузки.

Из корня репозитория подготовка без сети воспроизводится так (переменная
`TRACER_SYMUPLOAD` указывает на проверенный vendor script):

```sh
export TRACER_SYMUPLOAD=/tmp/apptracer-sdk-audit/aurora/symupload/symupload.py
python3 - <<'PY'
import os
import subprocess
from pathlib import Path
release = Path('packages/apptracer_flutter_desktop/example/build/macos/Build/Products/Release')
files = sorted(release.glob('**/*.dSYM/Contents/Resources/DWARF/*'))
if len(files) != 6:
    raise SystemExit('Expected six DWARF files from this release build')
command = ['python3', os.environ['TRACER_SYMUPLOAD'], '--no-upload',
           '--target-platform', 'darwin', '-o', 'build/macos-acceptance/breakpad-symbols']
for file in files:
    command.extend(['-d', str(file.resolve())])
subprocess.run(command, check=True)
PY
```

Переданы конкретные DWARF-файлы: эта версия vendor script пропускает `.dSYM`
при рекурсивном обходе каталога. Один exit code не считается успешной подготовкой:
дополнительно проверены количество файлов, MODULE identifiers и содержимое символов.
Для новой сборки нужны новый каталог результата и новая сверка UUID; смешивание
артефактов разных сборок недопустимо.

## Проверка после загрузки

Метка повторной native-пробы — `macos-symbols-d24abc0f9b22`, начало
`13:13:32 UTC` (`16:13:32 МСК`). SHA-256 executable сверён до запуска. Процесс
с включённым SDK завершился ожидаемым SIGABRT (`-6`), затем новый процесс `idle`
успешно включил SDK и оставался работоспособным 25 секунд.
В Tracer следует открыть последнее событие в группе `SIGABRT`, а не исходный
отчёт до загрузки. Появление файлов/строк и восстановленных имён функций
пока ожидает подтверждения пользователя. Системные библиотеки Apple не входят
в шесть загруженных модулей; отсутствие строк в них не доказывает ошибку загрузки.

Windows, обфусцированный Dart AOT и серверная символизация Cocoa остаются
открытыми частями №5. Задача не переносится в архив по одному успешному upload.
