# Аврора: подготовка нативной сборки

Целевая версия фасада — **2.0.0**. Приёмка плагина и RPM ведётся в
[плане №1, №6–12](tasks/development_v1.md#task-1).

<a id="emulator-audit"></a>

## Проверка на эмуляторе 24 ноября 2026

| Компонент | Проверка | Результат |
| --- | --- | --- |
| Эмулятор | ADT 0.7.13, `/etc/os-release`, `uname -m` внутри QEMU | Aurora 5.2.1.200 (Khabarovsk), release, aarch64 |
| Библиотеки гостевой ОС | `getconf GNU_LIBC_VERSION`, `rpm -q libopenssl` | glibc 2.38, libopenssl 1.1.1w+git2-1.3.2.omp |
| Flutter fork ОМП | Официальный архив macOS arm64, `flutter --version` и `aurora_embedder/pubspec.yaml` | Flutter 3.41.4 (`a0d3b222d7`), Dart 3.11.1, engine `4627d0f74a`, embedder 3.9.4 |
| Tracer Native 0.1.15 | Проверка SHA-256 по lock-файлу, `dlopen(RTLD_NOW)` и поиск восьми функций в процессе гостевой ОС | `native_api_resolved: true`, build-id библиотеки `cccc68dd0127cd85200d275f452695760db925f7` |
| Системный обработчик | Проверка пакета и `/proc/sys/kernel/core_pattern` до и после установки | В исходном образе обработчик был `\|/bin/false`. Установлен crash-dumper 0.1.4-1.1.11.omp. Применён его файл sysctl, вызов при SIGABRT виден в журнале |

Команды для проверки библиотеки с Mac ARM и Docker. Из корня репозитория
соберите диагностическую утилиту для Linux aarch64. Образ Debian используется
только как компилятор. Загрузку проверяет динамический загрузчик гостевой Авроры.

```sh
python3 tool/prepare_aurora_sdk.py
mkdir -p build/aurora-emulator
docker run --rm --platform linux/arm64 --network=none \
  -v "$PWD/tool/aurora:/src:ro" -v "$PWD/build/aurora-emulator:/out" \
  python:3.10-bookworm g++ -std=c++11 /src/sdk_probe.cc -ldl -o /out/probe

emu="$HOME/AuroraEmulator-5.2.1.200"
"$emu/bin/adt" device list
tool/aurora/check_emulator.sh build/aurora-emulator/probe \
  -p 2223 -i "$emu/ssh/id_rsa" -o "UserKnownHostsFile=$emu/ssh/known_hosts" \
  defaultuser@127.0.0.1
```

Используйте SSH-порт своего экземпляра. Скрипт работает от имени обычного
пользователя и удаляет временные файлы при выходе. Ожидаемый ответ утилиты:

```json
{"native_api_resolved":true,"sdk_initialized":false,"collection_contract_supported":false}
```

Для подготовки чистого тестового образа внутри эмулятора выполните
`sudo pkcon -y install crash-dumper` и
`sudo /usr/lib/systemd/systemd-sysctl /usr/lib/sysctl.d/crash-dumper.conf`.
Эти команды включают системный обработчик для всего эмулятора. У отдельного
тестового процесса без установленного RPM обработчик сообщил
`Application has empty version`. Затем через `adt device deploy` установлен
тестовый нативный RPM `ru.apptracer.EmulatorAudit-2.0.0-1.aarch64`,
подписанный тестовым ключом ОМП. При вызове `std::abort()` приложение завершилось
с кодом 134. В `~/.cache/ru.apptracer/EmulatorAudit/` появились `time`,
`version` со значением `2.0.0-1` и `minidump` размером 15 752 байта
с сигнатурой `MDMP`. Приложение проверяет механизм ОС. Для №6 отдельно
требуются Flutter MethodChannel, импорт дампа SDK до следующего `tracer_init`
и отчёт в нужном проекте Tracer.

## Что можно воспроизвести сейчас

Из корня репозитория:

```sh
python3 tool/prepare_aurora_sdk.py
```

Команда загружает закреплённую поставку Tracer 0.1.15 в игнорируемый
`build/aurora-sdk/0.1.15`, проверяет SHA-256 ZIP и всех файлов, ELF ABI и build-id.
Повторный вызов проверяет существующий каталог без сети и не перезаписывает его.
Повреждённая поставка приводит к ошибке; её удаление/замену скрипт не делает.
Можно использовать локальный архив:

```sh
python3 tool/prepare_aurora_sdk.py --archive /path/to/tracer-native-aurora-0.1.15.zip
python3 tool/prepare_aurora_sdk.py --verify-only
```

Бинарники и исходные ресурсы SDK не включены в репозиторий. Хеши полного комплекта,
включая инструменты символизации, закреплены в `tool/aurora/sdk.lock.json`.
Скрипт не исполняет программы вендора, не получает tokens и не отправляет данные.
Подготовка SDK не устанавливает право перераспространять его: условия поставки
библиотеки в RPM всё ещё требуют проверки, как указано в исходном аудите.

Дополнительная проверка реальных ELF (без их загрузки в процесс):

```sh
python3 tool/inspect_aurora_elf.py > build/aurora-elf-inspection.json
```

На Linux используется `readelf`, на macOS — `llvm-objdump` из Xcode. Проверены
все три библиотеки: 20 экспортируемых `tracer_*` функций, включая обязательные
init/log/key/user/upload/import. У aarch64 и x86_64 нужны `libc.so.6`,
`libssl.so.1.1`, `libcrypto.so.1.1` и соответствующий ELF loader; armv7hl
дополнительно требует `libm.so.6`. Во всех трёх есть ссылки на `GLIBC_2.38`.
Во всех трёх также подтверждены версии символов OpenSSL 1.1.0/1.1.1.
Это требования конкретной поставки, не утверждение об их наличии на устройстве.
Совместимость только по архитектуре или успешной линковке объявлять нельзя.

## CMake и ABI

`tool/aurora/TracerNative.cmake` предоставляет две функции для будущего runner:

```cmake
include("/path/to/repository/tool/aurora/TracerNative.cmake")
apptracer_import_aurora_sdk("$ENV{APPTRACER_AURORA_SDK_ROOT}")
# После создания своего нативного target:
target_link_libraries(my_plugin PRIVATE apptracer_aurora_headers ${CMAKE_DL_LIBS})
apptracer_install_aurora_sdk("share/my_application/lib")
```

Импорт использует **целевую** архитектуру `CMAKE_SYSTEM_PROCESSOR`, проверяет хеши
header и выбранной `.so`, включает `AURORA` и путь include. Соответствие `arm64` →
`aarch64` задано явно; доступны aarch64/x86_64, неизвестные ABI отклоняются.
armv7hl из поставки проверяется как файл, но не включается в начальную матрицу.
Названия runner, каталог RPM и loader path определяются реальным Aurora-проектом.
Для Flutter-моста выделен headers-only target: SDK следует загружать через
`dlopen` с обработкой ошибки, чтобы отсутствие `.so` не завершало приложение
до `main()`. Прямой импорт `apptracer_aurora_sdk` доступен для диагностики линковки.
Этот модуль не является готовым Flutter runner или спецификацией RPM.

На macOS/Linux можно скомпилировать проверку сигнатур API и диагностическую утилиту:

```sh
cmake -S tool/aurora -B build/aurora-host \
  -DAPPTRACER_AURORA_SDK_ROOT="$PWD/build/aurora-sdk/0.1.15"
cmake --build build/aurora-host
APPTRACER_AURORA_SDK_ROOT="$PWD/build/aurora-sdk/0.1.15" \
  python3 -m unittest discover -s tool/aurora/tests -v
```

Объект `aurora_sdk_api_check` не линкуется с ELF на macOS и не доказывает целевой ABI.
`apptracer_aurora_sdk_probe` только загружает указанную библиотеку через `dlopen` и
ищет необходимые exports; ни init, ни import dumps, ни upload он не вызывает.
В целевой Linux/Aurora-среде его нужно собрать её компилятором и выполнить:

```sh
./apptracer_aurora_sdk_probe /absolute/path/to/libtracernative.so
```

Успех подтверждает только загрузку и наличие API. JSON явно содержит
`sdk_initialized: false` и `collection_contract_supported: false`.
Тесты на host используют искусственные библиотеки, все функции которых завершают
процесс при вызове: проверяется, что диагностика не вызывает SDK. Дополнительно
проверяются неполная библиотека, плохой архив, изменённый header, symlink/traversal,
выбор архитектуры и точность установленной копии библиотеки.

CI `aurora-preparation.yml` повторяет host-проверки на Ubuntu и сохраняет
JSON manifest и диагностический журнал подготовки. [Прогон 39992802784](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39992802784)
успешен: загрузка и хеши, C++-сборка, 7 тестов. Это **не** сборка под Aurora,
установка RPM или проверка crash-dumper.

[Расширенный прогон 39996142549](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39996142549)
также успешен: добавлена проверка exports и зависимостей реальных ELF всех трёх
архитектур. Результат сохранён в артефакте `aurora-elf-inspection.json`.

## Что блокирует следующие этапы

1. Для Flutter RPM на этом Mac используется Aurora SDK (BT) 5.2.1.200 и
   [Flutter для ОС Аврора 3.41.4](https://developer.auroraos.ru/doc/extended/flutter/flutter_development/install). Современный плагин должен использовать
   `aurora_client_wrapper`, namespace `cw` и `pluginEntryPoint`, без регистрации
   на обычном upstream Linux. См. [миграцию ОМП](https://developer.auroraos.ru/doc/extended/flutter/migration_guide/3.32.7_to_3.35.7).
   При подготовке доступ по HTTPS к репозиториям Flutter/wrapper на hub.mos.ru
   вернул 403; их исходники и сборка в этой среде не проверены.
2. У проверенного Tracer 0.1.15 отсутствуют публичные Dart exception/stack API,
   remove-key/reset-user, shutdown/purge. Нельзя реализовать обещанный публичный
   контракт только заменой их логированием или `tracer_disable_upload`.
   См. [аудит](desktop-aurora-sdk-audit.md), B5. Старт будущего адаптера должен
   оставаться запрещённым для неподдерживаемого контракта, пока нет решения.
3. Требуются app/plugin tokens C/C++ проекта, реальные каталоги приложения,
   правила системных dumps, RPM, native crash/restart установленного Flutter-приложения,
   символизация и проверка Tracer. Отсутствие credentials не блокирует host-проверки.

Источник закреплённой поставки: [Tracer Aurora quick start](https://apptracer.ru/doc/native-aurora/quick-start/).
Полноценная реализация №6–9 и приёмка остаются в активном плане.
