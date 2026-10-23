# macOS: символы проверенной release-сборки

Дата: **2026-10-23**. Прогресс задачи №5, не завершённая приёмка.
**Принятое ограничение:** по результатам проверок и решению пользователя серверная
символизация native macOS через Sentry Cocoa → Tracer DESKTOP считается
неподдерживаемой в этой интеграции. Доставка SIGABRT и локальное восстановление
по dSYM работают. Уточнение у Tracer не запрашивается и не является условием
продолжения остальных работ. Повторные проверки этой возможности — только при
новых технических данных или изменении интеграции.
**Уточнение конфигурации:** первоначальные live-отчёты получены в проекте с
названием MacOS, для которого пользователь, вероятно, выбрал тип Android.
После обнаружения этого создан новый C/C++-проект `Test`, DSN и plugin token
заменены. Результаты старого проекта ниже сохранены как история диагностики;
они не устанавливают ошибку обработки Cocoa в правильно настроенном проекте.
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
Пользователь прислал новое событие от `16:13:34 МСК` и его Context.
**Проверка серверной символизации не пройдена:** файлы по-прежнему `<unknown>`,
исходных строк нет, имена Flutter остаются частично mangled/приблизительными.
Это новое событие после загрузки, а не просмотр старого отчёта.
Системные библиотеки Apple не входят в шесть загруженных модулей; отсутствие
строк в них само по себе не доказывает ошибку загрузки.

Дополнительно обнаружено расхождение метаданных:

| Поле | SDK / Context | Сводка Tracer |
| --- | --- | --- |
| ОС | `os.name=macOS`, `os.version=27.0.1`, device family `macOS`, arch `arm64` | `Android` |
| Версия / build | release/app_version `1.0.0`, dist/app_build `1` | `1.0.0 (100000000000000)` |
| Native mechanism | `signal`, `handled=false`, `SIGABRT` | Crash / SIGABRT |
| Бинарник | app_id `A070B3E2-E343-368F-AD64-F8D9122EFB30` | Совпадает в присланном Context |
| Запуск | app_start_time `2026-10-23T13:13:32Z` | Совпадает в присланном Context |

Сохранённый локальный envelope той же сборки содержит `platform=cocoa`,
SDK `sentry.cocoa.flutter 8.58.4`, `debug_meta.images` типа `macho`, UUID модулей,
адреса загрузки и инструкции кадров. Значения Android в нём нет. Присланные
пользователем macOS Context, UUID и время подтверждают соответствие нового события
проверенному запуску. UUID в строке User ID — пользовательский идентификатор;
его нельзя считать ID события. Native-сценарий не устанавливает `desktop-test-user`.

Само расхождение не устанавливает причину: нужно сверить тип проекта в Tracer/VK
Cloud, принадлежность DSN и plugin token одному проекту и поддержку символизации
Cocoa/Sentry через `/api/nativesymbol`. Это может быть отдельной проблемой
классификации/отображения. Изменение `platform` на Android или ручное добавление
имён кадров не применялось. Срок готовности native-символов к обработке новых
событий после upload также не подтверждён одним ответом `exists`.

## Дополнительная локальная проверка символов

Для caller-кадров сохранённого локального native-отчёта выполнен `atos` с dSYM
той же сборки и поправкой адреса возврата `instruction_addr - 1`. Это позволяет
избежать попадания адреса сразу после `call` в следующую функцию на границе.
Получены, в частности:

- `closure #1 in MainFlutterWindow.awakeFromNib()` — `MainFlutterWindow.swift:18`;
- `FlutterRunLoop.performExpiredTasks()` — `FlutterRunLoop.swift:148`;
- `FlutterEngineRunTask` — `embedder.cc:3372`;
- `-[FlutterEngine engineCallbackOnPlatformMessage:]` — `FlutterEngine.mm:1320`;
- обработчик FlutterMethodChannel — `FlutterChannels.mm:315`.

В загруженном Breakpad runner-файле также есть FILE `MainFlutterWindow.swift`,
FUNC closure с диапазоном `[0x160c, 0x1700)` и строка `16fc 4 18 1`:
скорректированный относительный адрес `0x16ff` соответствует строке 18.
То есть исходные символы и результат конвертации содержат сведения о файле/строке.
Некоторые оптимизированные/compiler-generated кадры остаются без строки и локально.
Артефакт: `build/macos-acceptance/native-local-symbols-adjusted.json`.

Для диагностики у Tracer подготовлены вопросы (сообщение не отправлялось):

1. Как для Sentry Cocoa/macOS определяется тип платформы, если Context macOS,
   а сводка Android? Зависит ли это от типа проекта?
2. Должен ли обработчик `platform=cocoa` применять Breakpad-символы, загруженные
   через `/api/nativesymbol`, или для него нужен другой документированный путь?
3. Сохраняются ли `debug_meta.images` и native addresses для серверной символизации,
   и как проверить готовность загруженных модулей перед новым событием?

Windows, обфусцированный Dart AOT и серверная символизация Cocoa остаются
открытыми частями №5. Задача не переносится в архив по одному успешному upload.

## Повторная проверка: C/C++-проект Test

После указания типа C/C++ пользователь создал новый проект `Test` и заменил
`TRACER_MACOS_SENTRY_DSN` и `TRACER_MACOS_PLUGIN_TOKEN`. Оба значения прочитаны
без вывода; проверены форма HTTPS DSN, наличие токена и неизменность SHA-256
executable. Пересборки не было, 12 MODULE identifiers повторно сверены с манифестом.

23 октября 2026 в `13:38:07 UTC` начата загрузка символов с новым токеном:
12 HTTP 200 с `success: true`. Повторная проверка доступности — HTTP 200,
недостающих модулей 0. После этого последовательно выполнены:

| Сценарий | Начало МСК | Метка | Локальный результат |
| --- | --- | --- | --- |
| Dart smoke | 16:38:56 | `macos-cpp-690a2cd66a-dart` | SDK enabled, приложение работало 20 секунд; сценарий handled/FlutterError/async |
| Native crash | 16:39:16 | `macos-cpp-690a2cd66a-native` | SDK enabled, ожидаемый SIGABRT (`-6`), restart idle успешен, наблюдение 25 секунд |

Артефакты без credentials: `build/macos-acceptance/cpp-project-acceptance.json`
и `cpp-symbol-upload.log`. Имена проекта и типа записаны по настройке пользователя;
права чтения параметров проекта через API не получены. SDK отправляет события
непосредственно по HTTPS, его ответы при этой проверке не наблюдались.

**Результат:** в ответ на запрос проверки Test пользователь прислал native
`SIGABRT / Signal 6, Code 0`. Доставка подтверждена; файлы по-прежнему `<unknown>`,
исходных строк нет. В тексте нет метки запуска, времени или подписи платформы;
сопоставление основано на ответе пользователя на запрос этой пробы. Три Dart-события
и их поля в Test ещё не подтверждены. Отрицательный результат символизации теперь
получен и после смены проекта, но точная причина на стороне обработки не установлена.

## Проверка альтернативного Apple dSYM endpoint

В `14:08:52 UTC` проверен отдельный путь, описанный в
[официальном Apple Bash uploader](https://apptracer.ru/doc/ios/bash/):
`POST /api/symbol/upload`, параметр `symbolToken`, поля
`versionName=apptracer_desktop_example`, `versionCode=1.0.0`, ZIP с runner dSYM.
Это диагностическая проверка совместимости, не объявление поддержки macOS этим API.
Выбран только runner (архив 1 976 002 байта); SHA-256 DWARF совпадает с исходным
манифестом. SDK, приложение и отправка событий не менялись.

С новым macOS plugin token сервер ответил **HTTP 400**:

```json
{"errorCode":"REQUEST","code":0,"message":"Application type should be IOS, but is DESKTOP"}
```

Это подтверждает тип **DESKTOP** проекта, которому принадлежит текущий plugin token,
и неприменимость Apple upload endpoint к этому проекту. Загрузка не удалась;
повторный crash после отклонённой загрузки не выполнялся. Артефакты без токенов:
`build/macos-acceptance/cpp-runner-dsym-upload.json`, `cpp-runner-dsym.zip`.
Не выполнять циклические повторы того же upload/crash без новых данных.

Причина неприменения символов сервером не установлена. По решению пользователя
дальнейшее выяснение прекращено: возможность отмечена как неподдерживаемая
в проверенной связке. Успешный `/api/nativesymbol/upload` не считается
подтверждением серверной символизации. Это граница поддержки нашей интеграции,
а не утверждение о всех версиях SDK и всех форматах Tracer.

## Текст для обращения в Tracer

Исторический черновик, не отправлялся. По решению пользователя обращение отменено;
ответа поддержки не ожидаем. Сохранён только как техническое описание проверок.

> Проверяем Flutter macOS arm64 в C/C++-проекте Test (backend подтверждает тип
> DESKTOP). Используем официальный sentry_flutter 9.30.1 / Sentry Cocoa 8.58.4
> с DSN Tracer. Native SIGABRT доставляется после перезапуска, но стек остаётся
> без файлов/строк и с частично нерасшифрованными Swift-именами.
>
> В локально принятом envelope той же сборки: platform=cocoa,
> sdk.name=sentry.cocoa.flutter, contexts.os.name=macOS, arch=arm64,
> debug_meta.images с type=macho, debug_id/image_addr/image_size/code_file;
> кадры содержат instruction_addr/image_addr/package.
>
> Через vendor symupload.py подготовлены и загружены 12 Breakpad-модулей для
> шести dSYM (arm64/x86_64). Все upload-ответы success:true, повторный
> /api/nativesymbol/exists не запрашивает ни один модуль. Новый crash создан
> после загрузки: 23.10.2026 около 16:39 МСК,
> probe_run=macos-cpp-690a2cd66a-native. В его стеке файлы остаются unknown.
>
> UUID runner A070B3E2-E343-368F-AD64-F8D9122EFB30 совпадает с dSYM;
> Breakpad MODULE ID — A070B3E2E343368FAD64F8D9122EFB300. Локальный atos
> восстанавливает MainFlutterWindow.swift:18 и строки Flutter. Загруженный
> .sym содержит соответствующие FILE/FUNC/line records.
>
> Альтернативная загрузка исходного runner dSYM через /api/symbol/upload
> отклонена HTTP 400: Application type should be IOS, but is DESKTOP.
>
> Поддерживает ли DESKTOP ingest символизацию Sentry Cocoa/Mach-O по debug_meta?
> Должны ли применяться символы /api/nativesymbol, какой формат идентификаторов
> ожидается и как проверить готовность загруженных модулей к обработке событий?
> Если этот маршрут не поддерживается, какой официальный SDK/формат рекомендуется
> для native macOS в C/C++-проекте?
