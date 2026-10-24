# Ubuntu/Linux: реализация и локальная приёмка №13

Дата: **24 октября 2026**. Live-проверка подтвердила Dart delivery и выявила
HTTP 404 у Crashpad `/minidump`. Адаптер переведён на официальный backend `native`:
стек и minidump идут через `/envelope/`. Повторная приёмка этой сборки описана ниже;
старые результаты Crashpad сохранены отдельно. Пользователь подтвердил отображение
native-файлов/строк после символизации в crash daemon. Затем автоматическое
отображение Dart-файлов/строк исправлено и проверено непосредственно в Tracer
для трёх новых событий. Расширенная матрица полей/группировки ещё не завершена,
поэтому задача целиком не архивируется.

Добавлены Linux-регистрация optional `apptracer_flutter_desktop`, GTK runner,
управление очередью и consent, release build helper и Ubuntu CI. Ручной
`apptracer_flutter_sentry`/HTTP backend не используется. Публичный `Tracer` API
не изменён. Пакет остаётся экспериментальным и неопубликованным.

## Среда и SDK

| Компонент | Проверено локально |
| --- | --- |
| ОС сборки | Ubuntu 22.04.3 LTS x86_64 в WSL2 |
| Ядро сборки | `6.18.54.1-microsoft-standard-WSL2` |
| Целевая ОС | Ubuntu 22.04.5 LTS x86_64, отдельная QEMU/KVM VM |
| Ядро целевой ОС | `5.15.0-198-generic`, glibc `2.35` |
| Flutter / Dart | `3.47.4` / `3.13.3`; framework `9584c6713b`, engine `06a2e2a110` |
| Clang / CMake / Ninja | `14.0.0` / `3.22.1` / `1.10.1` |
| GTK / glibc | `3.24.33` / `2.35` |
| Sentry Flutter / Dart | закреплены на `9.30.1` |
| sentry-native | `0.16.6`, backend `native`; первоначальная приёмка использовала Crashpad |
| Java для сборки JNI dependency | OpenJDK 17; runtime приёмка не требует запуска JVM |
| GUI | WSLg присутствует; автоматические пробы выполнены через Xvfb, X11 и software GL |

В исходной WSL отсутствовали Linux Flutter и инструменты сборки, DNS
`10.255.255.254` не разрешал имена. Для подготовки установлен отдельный Flutter
в `~/apptracer-tools/flutter` и build dependencies. DNS временно заменён на
`1.1.1.1`; исходный `/etc/resolv.conf` сохранён в
`/etc/resolv.conf.apptracer-backup`. Автогенерация WSL DNS не отключалась.
Рабочая копия сборки — `~/apptracer-linux`, чтобы Windows и Linux не перезаписывали
друг другу `.dart_tool` и build cache.

Во время проверки C: заполнился, и ext4 WSL перешёл в read-only. Ubuntu остановлена
и перенесена штатной командой `wsl --manage Ubuntu --move D:\WSL\ApptracerUbuntu`.
Регистрация, Linux home и toolchain сохранены; после запуска проверена запись,
повторно выполнены анализ, тесты и release build. На C: освободилось около 12 ГБ.
Дистрибутив Docker не переносился. Диски тестовой VM находятся в ignored
`build/ubuntu-vm/` на D:.

VM использует официальный
[Ubuntu Jammy cloud image](https://cloud-images.ubuntu.com/jammy/), snapshot
`20261020`, SHA-256 `2099e63da0b822ef8e05e3d596c1b402eaaae658fc08ab919cb8495bfcdc488b`.
Она запущена через KVM внутри WSL, но имеет собственное generic Ubuntu kernel,
root filesystem и runtime dependencies. В госте нет Flutter/Dart, Java, GCC,
Clang, CMake и Ninja. GUI-пробы используют Xvfb/X11 и software GL; интерактивная
Wayland-сессия не проверялась.

Поддержка Linux/C++ через Sentry заявлена в
[документации Tracer](https://apptracer.ru/doc/other-platforms/quick-start/).
Это основание выбора транспорта, **не подтверждение фактической доставки**.
Использованы исходники закреплённого SDK:
[sentry-dart 9.30.1](https://github.com/getsentry/sentry-dart/tree/9.30.1/flutter),
[sentry-native 0.16.6](https://github.com/getsentry/sentry-native/tree/0.16.6).

## Воспроизведение

На Ubuntu 22.04 x86_64 установить Flutter 3.47.4 и зависимости:

```sh
sudo apt-get update
sudo apt-get install -y clang llvm-14 cmake ninja-build pkg-config libgtk-3-dev \
  libgles2 libcurl4-openssl-dev liblzma-dev xvfb openjdk-17-jdk
bash tool/build_linux_desktop.sh

export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
bundle=packages/apptracer_flutter_desktop/example/build/linux/x64/release/bundle
for scenario in disabled deferred smoke; do
  xvfb-run -a python3 tool/check_linux_desktop.py --app "$bundle" \
    --scenario "$scenario" --output "build/linux-acceptance/$scenario.json"
done
for scenario in lifecycle native native-inflight native-revoked native-discard dart-retry dart-online dart-revoked dart-discard missing-handler unwritable-storage readonly-bundle missing-native-symbols mismatched-native-symbols; do
  xvfb-run -a python3 tool/check_linux_runtime.py --app "$bundle" \
    --scenario "$scenario" --output "build/linux-acceptance/$scenario.json"
done

python3 tool/symbolize_linux_dart.py \
  --report build/linux-acceptance/smoke.json --binary "$bundle/lib/libapp.so" \
  --symbols packages/apptracer_flutter_desktop/example/build/symbols/dart/app.linux-x64.symbols \
  --output build/linux-acceptance/dart-symbols.json
```

Build helper задаёт `SENTRY_NATIVE_BACKEND=native`, исправляет унаследованный Windows `JAVA_HOME`,
сохраняет ELF/Dart symbols и проверяет совпадение build-id Dart binary/symbols.
Кроме того, helper создаёт `bundle/lib/symbols` для восстановления native-кадров
самим crash daemon. Каталог входит в поставку; Dart AOT mapping туда не попадает.
Runner устанавливает bundle в build-каталог, а не `/usr/local`, и сохраняет
исполняемые права `sentry-crash`. Скопировать необходимо **весь bundle**:
executable, `lib/`, `bin/`, `data/`. В нём есть `libsentry.so`,
`libflutter_linux_gtk.so`, `libapp.so` и `lib/sentry-crash`. Неиспользуемый Android JNI bridge
исключён из Linux bundle примера: он требовал `libjvm`/`libjawt` даже при отсутствии
вызовов JNI. JDK нужен сборке, но не целевому runtime. Для чистой Ubuntu Server:

```sh
sudo apt-get install -y libgtk-3-0 libcurl4 libegl1 libgles2 libgl1-mesa-dri xvfb xauth
```

Проверяются `ldd` runner, всех `lib/*.so` и crash daemon: ни одной отсутствующей
библиотеки. `libGLESv2` также загружается Flutter динамически и должна быть
установлена, даже если её нет в выводе `ldd` runner.

Для ручного запуска пример читает только `TRACER_LINUX_SENTRY_DSN` из окружения
либо одноимённого `--dart-define`. Windows/macOS DSN на Linux не выбирается.
Plugin token не передавать приложению. Автоматические пробы используют только
фиктивный loopback DSN, переселяют bundle в путь с пробелами/кириллицей и выделяют
собственный `XDG_DATA_HOME`.

Workflow [linux.yml](../.github/workflows/linux.yml) закрепляет `ubuntu-22.04`
и Flutter, выполняет analyze/tests, release и эти сценарии, сохраняет bundle,
symbols, lockfile и JSON. Workflow подготовлен; удалённый запуск GitHub Actions
в этой работе не выполнялся.

## Первоначальные локальные результаты (Crashpad)

Этот раздел фиксирует предыдущую сборку. Он не заменяет повторную приёмку
backend `native`; актуальные команды выше уже используют новый backend.

| Проверка | Локальный результат |
| --- | --- |
| Release, obfuscation и split-debug-info | Пройдены |
| Analyze адаптера и примера | Без замечаний |
| Unit tests адаптера | 14 пройдены; 2 Cocoa envelope-теста пропущены на Linux, выполняются на macOS |
| Widget test подтверждения native crash | Пройден |
| Python regression suite | 19 пройдены |
| Disabled/deferred | Приложение готово, `sentry-sdk`, нет отправок |
| Dart smoke | Ровно 3 события: handled, FlutterError, async; user, run key, breadcrumbs |
| Lifecycle | 18 шагов: prestart clear, start, stop, повторный start, clear, crash после clear, новая учётная запись, отмена удерживаемого Dart HTTP-запроса, restart |
| Native | SIGSEGV без отладчика; minidump соответствует ELF runner; HTTP 503, restart и повторная доставка того же SHA-256 |
| Отзыв/удаление pending native | После HTTP 503 prestart stop запрещает replay при preserve=true; preserve=false также удаляет сохранённый minidump |
| Native in-flight | Stop завершает принадлежащий очереди Crashpad; сервер наблюдает закрытие сокета до своего ответа |
| Persistent Dart | После сетевого обрыва envelope сохранён; restart с preserve=true доставляет событие с прежним userId ровно один раз |
| Dart offline → online без restart | Плановый повтор примерно через 15 минут прошёл на VM; ровно одно событие после восстановления сети |
| Отзыв/удаление pending Dart | Prestart stop запрещает replay при preserve=true; preserve=false отбрасывает отчёт |
| Чистая Ubuntu VM | Release вне checkout; все runtime ELF разрешаются без JDK, Flutter и компиляторов |
| Локальные символы | 3 Dart AOT события до исходных строк; native crash до `apptracer_native_crash():21`, `trust=cfi` |
| Нет Crashpad | `error`, нет отправок; удалены все варианты handler (`bin/`, `lib/`, корень) |
| Недоступная очередь | `error`, нет отправок; файл вместо каталога данных |
| Read-only bundle | Запуск, Dart delivery и clear пройдены; очередь находится вне каталога установки |
| Storage tests | Отзыв отменяет preserve; clear блокирует поздний writer; symlink отвергается без удаления его цели |

Итоговая проверенная сборка: runner build-id `bc8ea719fde3704845b42b656650ce87d49bd478`,
Dart build-id `bdd0aff668aa3e5fca14387503e16a24`. Идентификаторы относятся только
к этой сборке; после изменения исходников нужно сохранить новый комплект.
Символы хранятся в `example/build/symbols/`, не коммитятся. Загрузка и проверка
серверной символизации в Tracer остаются №5. Локальный Dart AOT helper
использует LLVM DWARF, проверяет build-id ELF/symbols/raw stack и восстанавливает
имена и строки исходников трёх smoke-событий. Виртуальные PC из stack не нужно
повторно смещать. `flutter symbolize` этой версии не распознаёт секцию
`_kDartSnapshotText`, поэтому результат LLVM сохраняется отдельно.

Для native minidump локально восстановлены `apptracer_native_crash()` —
`linux/runner/my_application.cc:21` — и вызывающий `probe_method_call`, строка 26.
Оба кадра имеют `trust=cfi`; найденный сканированием адрес не считается доказательством.
Release runner сохраняет DWARF и frame pointers; sibling-call optimization
отключена, чтобы вызов `raise` не удалял crash-пробу из стека.
Инструменты: [Mozilla dump_syms 2.3.9](https://github.com/mozilla/dump_syms/releases/tag/v2.3.9)
и [rust-minidump 0.27.0](https://github.com/rust-minidump/rust-minidump/releases/tag/v0.27.0).
Загрузчик закрепляет SHA-256 архивов. Команды, после сборки и с тем же `bundle`:

```sh
python3 tool/prepare_linux_symbol_tools.py --output build/linux-symbol-tools
xvfb-run -a python3 tool/check_linux_runtime.py --app "$bundle" --scenario native \
  --output build/linux-acceptance/native.json --dump-directory build/linux-acceptance/minidumps
for elf in "$bundle/apptracer_desktop_example" /usr/lib/x86_64-linux-gnu/libc.so.6 "$bundle"/lib/*.so; do
  build/linux-symbol-tools/dump_syms --store build/linux-acceptance/symbols/breakpad "$elf"
done
for dump in build/linux-acceptance/minidumps/*.dmp; do
  python3 tool/symbolize_linux_native.py --dump "$dump" \
    --runner "$bundle/apptracer_desktop_example" --symbols build/linux-acceptance/symbols/breakpad \
    --stackwalk build/linux-symbol-tools/minidump-stackwalk --output build/linux-acceptance/native-symbols.json
  break
done
```

Для системных ELF нужны файлы именно той ОС, где получен minidump. Локальная
native-символизация выполнена для дампа WSL2; runtime crash/retry дополнительно
пройден в чистой VM. ELF build-id проверяется до вызова stackwalker; helper
требует исходную строку функции пробы именно в аварийном потоке.

JSON, symbols и `ubuntu-22.04-x64-bundle.tar.gz` сохранены в
`build/linux-acceptance/` рабочего checkout на Windows. Архив сохраняет Linux
исполняемые права и пригоден для переноса на целевую Ubuntu.

Финальный VM-прогон: `build/ubuntu-vm/run-1792832101821464956/reports/`.
Все 15 JSON также скопированы в `build/linux-acceptance/`; сводка —
`acceptance-summary.json`, окружение — `vm-environment.txt`, зависимости —
`vm-ldd.txt`. SHA-256 bundle:
`6a694f1a94456960fbed2033cdf2a1c2fa5d8e6c42c4ecfb4cad3f6b7487ffa7`.
После приёмки VM штатно выключена; диски и артефакты сохранены на D:.

## Live Tracer: 24 октября, C/C++-проект

Пользователь заполнил `TRACER_LINUX_SENTRY_DSN` и `TRACER_LINUX_PLUGIN_TOKEN`
в игнорируемом `.env.tracer`. Секреты не выводились, plugin token использован
только инструментом загрузки, приложение получило DSN через окружение.
Исходный release bundle не пересобирался.

Символы четырёх модулей загружены через проверенный vendor `symupload.py`
из закреплённой поставки `0.1.15`: четыре HTTP 200 с `success:true`, затем
`/api/nativesymbol/exists` вернул `items:[]`. Для `libapp.so` использован DWARF
из точного `app.linux-x64.symbols`, с сохранением ELF build-id и имени модуля.
Он содержит 765 FILE и 12423 FUNC; runner — 4 FILE и 16 FUNC. Для stripped
Flutter/libsentry доступны PUBLIC/CFI, но исходных строк нет.

Прямой запуск в чистой VM:

| Проба | МСК | `probe_run` | Результат |
| --- | --- | --- | --- |
| Dart smoke | 12:26:22 | `linux-cpp-20261024-0926-0c583c-dart` | SDK enabled; 3 события подтверждены скриншотом пользователя |
| Native crash/restart | 12:26:49 | `linux-cpp-20261024-0926-0c583c-native` | SIGSEGV `-11`, restart enabled; 1 dump остался pending |

Скриншот пользователя от 12:33 показывает handled/async/FlutterError и
диагностическое событие в проекте `Test`. У всех строк `<unknown>` и
`Stacktrace not available`: загрузка символов **не подтверждает** серверную
символизацию. Пользовательские поля и исходные строки в карточках ещё не приняты.

Проверка сети VM подтвердила DNS и TLS. Затем изолированный диагностический
HTTP relay переслал неизменённые SDK payloads на настоящий HTTPS endpoint Tracer:
Dart `/envelope/` вернул **200**, Crashpad `/minidump/` — **404**,
`No endpoint POST /api/<project>/minidump`. Именно это препятствует native delivery
текущего Flutter-адаптера; loopback принимал маршрут и не мог выявить ограничение.

Дополнительные эксперименты, не включённые в адаптер:

- Публичный `sentry_capture_minidump` отправил сохранённый dump в envelope:
  HTTP 200, event ID `3972d79bbefb4b5fed400288afd71f29`, метка с суффиксом
  `-minidump-envelope`. Обработка minidump сервером не подтверждена.
- Отдельная C-проба того же sentry-native `0.16.6`, собранного с backend `native`
  вместо Crashpad, отправила SIGSEGV как native stack + minidump envelope:
  HTTP 200, метка `linux-cpp-20261024-0926-0c583c-native-backend`.
  Пользователь подтвердил карточку SIGSEGV с функцией `apptracer_native_candidate_crash`.
  После загрузки символов самой C-пробы, libsentry и daemon повторная карточка
  (`-native-backend-symbols`) также показывает `unknown` вместо файлов/строк.
  Доставка подтверждена, серверная символизация — нет.

Артефакты без credentials: `build/linux-live/symbol-manifest.json`,
`symbol-upload.json`, `live-run.json`, `transport-diagnostic.json`,
`minidump-envelope-diagnostic.json`, `native-backend-candidate.json`.
Приложения и диагностические процессы изолированы. По результатам этой проверки
начат перевод Flutter-адаптера на backend `native`.

## Переход Flutter-адаптера на native backend

Используется тот же закреплённый SDK, режим `NATIVE_WITH_MINIDUMP`. Handler
`lib/sentry-crash` устанавливается как executable; при его отсутствии запуск
возвращает `error`. CMake примера требует явного выбора backend через build helper.

При проверке найдено отличие SDK 0.16.6: crash daemon отключает собственный retry
и сохраняет неотправленный native envelope под обычным UUID в `cache/`.
При разрешённом сохранении отчётов адаптер до native init переводит такие файлы
с парным UUID minidump в retry queue SDK. Вложение восстанавливается с заголовком
официального `SentryEnvelopeItem`; исходные байты event и minidump, event ID и возраст
не меняются. Новый файл публикуется атомарно; повтор после прерванной публикации
не создаёт дубликат. Операция выполняется под блокировкой после остановки старого daemon;
отозванные отчёты и default disposal удаляются раньше. Формат cache привязан
к этой версии SDK и требует повторного аудита при обновлении.

Артефакты новой сборки сохраняются отдельно в `build/linux-native-acceptance/`,
live receipts и символы — в `build/linux-native-live/`.
Все **15 release-сценариев** финальной сборки пройдены на чистой Ubuntu VM;
сводка — `build/linux-native-acceptance/acceptance-summary.json`, копии отчётов —
`vm-reports/` в том же каталоге. После проверки VM штатно выключена,
диск и артефакты сохранены. Удалённый GitHub Actions не запускался.

Финальная сборка backend `native`:

- Bundle SHA-256: `eca52c0c5eba68ff3a971bda0dfd66baa700a72e0a081ccbe737788057710dd6`.
- Runner build ID: `bc8ea719fde3704845b42b656650ce87d49bd478`.
- Dart build ID: `fed6889c5704bdde60d6ce8804d49225`.
- Целевая VM: `build/ubuntu-vm/run-1792836348613163205/reports/`.

| Повторная проверка | Результат |
| --- | --- |
| Analyze адаптера/примера | Без замечаний |
| Unit/widget/Python | 16 adapter tests; 2 macOS-only skipped; 1 widget; 20 Python tests |
| Disabled, deferred, smoke | Нет отправок до старта; затем 3 Dart-события с полями |
| Lifecycle | Все 18 шагов, включая смену учётной записи и закрытие удерживаемого сокета |
| Native crash/retry | Envelope с SIGSEGV и minidump; после restart тот же event ID и SHA-256 дампа |
| Native/Dart revoke/discard | Отзыв запрещает replay; default disposal удаляет старые отчёты |
| Native in-flight | Удерживаемый запрос отменён до ответа сервера |
| Dart retry без restart | 15-минутный прогон пройден; после восстановления сети ровно одно событие с прежним user ID |
| Missing handler, unwritable storage, read-only bundle | Ожидаемые состояния и отсутствие запрещённых отправок |
| Символизация локально | 3 Dart AOT стека с исходниками; native `apptracer_native_crash():21`, `trust=cfi` |

Прежние архивы и неуспешные промежуточные прогоны сохранены отдельно; они не
подменяют результаты финального bundle. Проверка native cache выявила и устранила
потерю minidump при простом повторе одного event. Тест также покрывает восстановление
после прерывания публикации retry-файла и сохранение исходного mtime для retention SDK.

Пользователь подтвердил новую Flutter-карточку SIGSEGV: в ней видны `main`,
`g_application_run`, `_ZL17probe_method_callP16_FlMethodChannelP13_FlMethodCallPv`
и `_ZL22apptracer_native_crashv`. Это краш Flutter runner, а не отдельной C-пробы.
Сервер принял envelope с native event и minidump (HTTP 200); исходные файлы/строки
в карточке всё ещё `unknown`. Локально точный дамп восстанавливается до строки 21.

Нулевой shutdown timeout выявил раннее закрытие сокета до HTTP acknowledgement
у crash daemon. Используется 2000 мс; при `stop` consent отзывается до shutdown,
а начатый запрос приложения должен завершиться или отмениться до возврата `stop`.
Проверка успешного native upload дополнительно требует отсутствия pending envelope.

Успешная Flutter live-проба финального bundle: `linux-flutter-native-20261024-1006-370d6d`,
event ID `d36d340f-7d63-4a84-25c3-720e6a90e477`, HTTP 200 с полученным ответом,
native user `linux-flutter-native-user`, minidump 7972696 байт; pending envelope нет.
Прямой HTTPS-запуск: `linux-native-direct-20261024-1006-584d64`, три Dart smoke
и SIGSEGV `-11` с последующим restart; очередь native после restart пуста.
HTTP receipt относится к диагностическому relay; прямой запуск не перехватывал ответы.

Для разбора серверной символизации: debug ID runner в SDK event
`19a78ebc-e3fd-4870-45b4-2b656650ce87` соответствует загруженному Breakpad ID
`19A78EBCE3FD487045B42B656650CE870`. `symupload` подтвердил `success:true`,
последующий `/api/nativesymbol/exists` — `items:[]`. Runner содержит DWARF,
его symbols — 4 FILE и 16 FUNC; локальный stackwalker находит исходную строку.
Проверялись новые события после загрузки символов: по
[правилам Tracer](https://apptracer.ru/doc/intro/crashid/) старые события
не пересимволизируются. Таким образом, отсутствие plugin token, несовпадение
runner build ID и проверка только старой карточки не объясняют полученный результат.

## Исправление native `unknown`: символизация в crash daemon

Причина отсутствия исходных строк локализована на границе symbolication:
`sentry-native 0.16.6` создаёт native-кадры с адресом, module и function, но без
`filename`/`lineno`; сервер в показанных пользователем новых событиях не заполнял
эти поля даже после успешной загрузки совпадающих символов. Это не доказывает
конкретную внутреннюю ошибку сервера: доступа к его обработчику нет.

Linux-плагин теперь также регистрирует FFI CMake hook. Он добавляет
`linux/native_symbols.cc` в **отдельный процесс `sentry-crash`** и GNU linker wrapper
для `sentry_value_set_by_key`. В SDK 0.16.6 установка `debug_meta` происходит после
сборки кадров и до сериализации event. В этой точке wrapper восстанавливает
native function/file/line по Breakpad MODULE/FILE/FUNC/line records. Обновление SDK
требует повторного аудита этой последовательности и crash/retry-проб.

Подбор карты требует совпадения полного пути module с `debug_meta`, затем имени
module и debug ID в пути **и** MODULE header. Адрес вычисляется из instruction
address и module base; для return frames учитывается предыдущая инструкция.
При отсутствии/несовпадении карты исходные SDK-кадры остаются без исходных строк.
Работа выполняется вне signal handler упавшего приложения, без subprocess,
сетевого поиска символов и инструментов сборки на целевой машине. Официальный
SDK продолжает формировать minidump, сериализовать event и доставлять envelope.

`tool/prepare_linux_runtime_symbols.py` создаёт `bundle/lib/symbols` из native ELF
той же сборки. Для внешнего runner передать `--executable <имя-файла>` и сохранить
DWARF до запуска helper. Поставка карты не требует plugin token. Карта содержит
имена native-функций и пути исходников; Dart AOT deobfuscation map из split-debug-info
туда не включается. Системные/Flutter-модули без своих source maps могут оставаться
`unknown`; это исправление относится к native-коду, для которого есть точная карта.

Release-артефакт исправления хранится отдельно от прежней приёмки:
`build/linux-symbolication-acceptance/ubuntu-22.04-x64-bundle.tar.gz`, SHA-256
`e25943f3861ade153810c349160a324ca4549cc8f3c8fe0ec141148d111b6de8`.
В обычной сборке прошли analyze, 16 adapter tests (2 macOS skips), 1 widget test,
20 Python tests, WSL smoke/lifecycle/native-inflight. Native crash/retry в чистой
Ubuntu VM автоматически передаёт исходные строки, сохраняя их при retry вместе
с event ID и minidump SHA-256.
На этом артефакте пройдены **16 VM-сценариев**: disabled/deferred/smoke,
lifecycle, native/retry/in-flight/revoke/discard, Dart retry/revoke/discard,
missing handler, unwritable storage, read-only bundle, missing native symbols
и mismatched native symbols. Отчёты и SHA-256 находятся в
`build/linux-symbolication-acceptance/acceptance-summary.json` и `vm-reports/`.
15-минутный Dart retry без restart относится к прежнему артефакту native backend;
для изменения только native symbolication этот длительный тест не повторялся.

Реальное падение этого bundle в чистой Ubuntu VM отправлено в Tracer:
`linux-native-symbols-20261024-1049-b9b971`, event ID
`5a76e661-a60a-42ad-41c5-f7d301a0aa3b`, HTTP 200 с acknowledgement, minidump
6407520 байт, pending envelope нет. Диагностический TLS relay пересылает SDK payload
без модификации. В отправленном event автоматически восстановлены:

| Function | Source |
| --- | --- |
| `main` | `linux/runner/main.cc:5` |
| `probe_method_call(_FlMethodChannel*, _FlMethodCall*, void*)` | `linux/runner/my_application.cc:26` |
| `apptracer_native_crash()` | `linux/runner/my_application.cc:21` |

Пользователь подтвердил отображение всех трёх кадров с указанными файлами/строками
в событии Tracer от **24.10.2026 13:49:17 МСК**. В карточке видны `FATAL`, C/C++,
версия `1.0.0`, user `linux-flutter-native-user`, одно событие и одно устройство.
Это подтверждает доставку и отображение результата клиентской native-symbolication;
серверная symbolication этим не объявляется исправленной. Ранее отправленные
события не изменялись. Для системных/Flutter-кадров без карт остаются `unknown`.
В заголовке карточки сохраняется `Stacktrace not available`, хотя перечисленные
кадры отображаются в событии; причина этой надписи отдельно не установлена.

## Проверка трёх Dart-событий в консоли

24 октября карточка `StateError — Bad state: desktop handled probe` проверена
в открытом пользователем Яндекс Браузере через Windows accessibility API.
Событие от **13:06:36 МСК** относится к запуску
`linux-native-direct-20261024-1006-584d64-dart`.

- Версия `1.0.0`, user ID `desktop-test-user` и ключ `probe_run` совпали с пробой.
- Во вкладке «Логи» сохранён breadcrumb `desktop probe started`, category `probe`,
  level `info`, data `source=release-app`.
- В «Данных» видны `fatal=false`, `issueKey=desktop-handled-probe`, mechanism
  `apptracer`; `__sentry_fingerprint` и `__resolved_sentry_fingerprint` содержат
  `desktop-handled-probe`. Это подтверждает значения полей; полная матрица
  группировки ещё не проверена.
- `contexts.apptracer.dart_stack_trace` сохранён. Пользователь скопировал его
  полный текст: build ID `fed6889c5704bdde60d6ce8804d49225`, virtual PCs
  `0x4719d6` и `0x471850`.

Build ID проверен по самим ELF `libapp.so` и `app.linux-x64.symbols`, после чего
LLVM 14 восстановил **именно стек из карточки Tracer**:
`_handled` → `example/lib/main.dart:45:5`,
`_runScenario` → `example/lib/main.dart:89:11`.
Исходная ошибка и нужные символы не потеряны; в серверном представлении стека
исходные строки по-прежнему отсутствуют. Локальная расшифровка не является
исправлением автоматической Dart AOT-symbolication в консоли.
Доказательства: `build/tracer-console-audit/handled-{keys,logs,data}-ui.json`
и `handled-dart-decoded.json`.

Дополнительно проверена карточка **`vF — desktop FlutterError probe` от 12:26:25 МСК**.
Это более ранняя сборка с build ID `bdd0aff668aa3e5fca14387503e16a24`; её результат
не подменяет проверку последней сборки `fed6889c5704bdde60d6ce8804d49225`.
Подтверждены user `desktop-test-user`, `fatal=false`, library `desktop acceptance`
и полный исходный стек. Build IDs сохранённых ELF и split-debug-info совпали;
LLVM восстановил `0x2fcb9a` → `_flutterError`, `main.dart:55:25`,
`0x46a4a6` → `_runScenario`, `main.dart:90:5`.
Доказательства: `flutter-data-ui.json` и `flutter-dart-decoded.json` в том же
каталоге аудита.

Затем проверен **`wF — desktop FlutterError probe` от 13:06:36 МСК** последней
Dart-сборки `fed6889c5704bdde60d6ce8804d49225`. Сохранены `fatal=false`, library
`desktop acceptance`, runtime `Flutter / Dart AOT` и полный исходный стек.
По совпадающим ELF/split-debug-info восстановлены `0x2fa03e` → `_flutterError`,
`main.dart:55:25`, и `0x471866` → `_runScenario`, `main.dart:90:5`.
Доказательства: `flutter-current-data-ui.json` и `flutter-current-dart-decoded.json`.
Это локальная расшифровка реального события; серверные source frames не исправлены.
Также проверено **`StateError — Bad state: desktop async probe` от 13:06:36 МСК**
с тем же build ID. Сохранены `fatal=false` и все 17 адресных кадров исходного стека.
Первый кадр `0x2f9bea` восстановлен в `_asyncError.<anonymous closure>`,
`example/lib/main.dart:64`. Остальные кадры относятся к Future, Zone, Timer и isolate;
у 16 из 17 кадров восстановлены ненулевые source lines, у служебного `_Closure.call`
есть функция/файл с line=0. Доказательства: `async-data-ui.json` и
`async-dart-decoded.json`. `fatal=false` соответствует default
`reportUnhandledErrorsAsFatal=false`: async error сам по себе не означает смерть процесса.

Таким образом, оригинальные стеки всех трёх Dart-проб последней сборки сохранены
в Tracer и локально восстанавливаются по точным символам. Это не подтверждает
автоматическую серверную символизацию. Ключи/breadcrumb проверены непосредственно
для handled-пробы; соответствующие вкладки FlutterError/async и расширенная
матрица группировки ещё не приняты.

## Автоматическое отображение Dart-файлов и строк: исправление

Контрольная серия `linux-dart-display-114438` сравнила четыре новых события через
официальный SDK. Добавление module/package, смена event platform на native и
передача relative PC с base=0 не восстановили source lines в Tracer. Вариант
с заранее заполненными function/file/line отобразился корректно. Проверка
выполнена через открытый браузер; это наблюдение о результатах обработки,
а не доступ к внутреннему коду сервера. См. также официальные
[правила символизации новых событий](https://apptracer.ru/doc/intro/crashid/).

В `linux_dart_symbols.dart` добавлена автоматическая символизация **перед
сериализацией официальным Sentry SDK**. Адаптер сопоставляет build ID исходного
стека, реально загруженного `libapp.so` из SDK debug images и локальной карты.
DSO-relative PC сверяется с absolute PC минус base; повторного вычитания base
или поправки native return-address для Dart нет. По диапазонам FILE/FUNC/line
восстанавливаются имена, файлы и строки только сохранённых фильтром кадров.
Оригинальный `contexts.apptracer.dart_stack_trace` остаётся без изменений.
После асинхронного чтения карты повторно проверяется разрешение на сбор.

Компактную карту создаёт `tool/prepare_linux_dart_runtime_symbols.py` из
split-debug-info той же сборки с помощью закреплённого `dump_syms`. Путь:
`bundle/lib/apptracer-dart-symbols/<build-id>.json.gz`. Helper примера включает её
по умолчанию. Карта раскрывает имена функций и пути исходников и **ослабляет
обфускацию**; полный DWARF и текст исходников в bundle не помещаются. Отключение:

```sh
TRACER_BUNDLE_DART_SYMBOLS=0 bash tool/build_linux_desktop.sh
```

Для внешнего bundle helper можно вызвать отдельно с `--bundle`, `--symbols`
и `--dump-syms`. Без карты, с повреждённой картой или несовпадающим build ID
приложение доставляет исходный event без ложных source lines. Карта читается
только после разрешённого старта при обработке AOT-события и кэшируется.
Для работы на целевом компьютере не нужны LLVM, Flutter, Python или plugin token.
Старые события Tracer не переписываются; обновить нужно весь bundle и отправить
новые события. Без поставки карты автоматическое восстановление этим механизмом
не выполняется.

Проверенный артефакт:
`build/linux-dart-display/acceptance/ubuntu-22.04-x64-bundle.tar.gz`, SHA-256
`57c33481cfa1aae0172d4f57b41e8e4b644ca44b589fca33b4b85ba3b4246173`.
Dart ELF build ID `af8e18a2dccf4f2706afbd3a82a6750c`;
карта 468945 байт, 768 файлов, 12459 функций, 45324 диапазона строк.
20 adapter tests пройдены (2 macOS skips), 1 widget test и 22 Python tests;
analyze без замечаний. В чистой Ubuntu VM пройдены **13 проверок**: disabled,
deferred, smoke, lifecycle, native, native-inflight, Dart retry/revoke/discard,
read-only bundle, Dart source map resolved/missing/mismatched. Retry сохраняет
event ID и exception frames. Отчёты: `acceptance-summary.json`, `vm-reports/`
в каталоге артефакта. Прежний 15-минутный retry без restart не повторялся.

Живая серия `linux-dart-fixed-20261024-1155-b210aa` отправлена из чистой VM:
три ответа HTTP 200, исходные стеки сохранены, pending envelopes нет.
Relay переслал payload SDK без изменений. В браузере самостоятельно проверены
**новые события от 24.10.2026 14:56:01–14:56:02 МСК**, включая поля в «Stacktrace»:

| Событие | Event ID | Автоматически отображённый source frame |
| --- | --- | --- |
| handled | `801b1836d74b46daa5a6268823279a63` | `_handled` → `example/lib/main.dart:45` |
| FlutterError | `09392b62c204430b832d341480fe4448` | `_flutterError` → `example/lib/main.dart:55` |
| async | `41bd2a39094e49efbd9d44c64bfe80bb` | `_asyncError.<anonymous closure>` → `example/lib/main.dart:64` |

Для всех трёх подтверждены `desktop-test-user`, точный `probe_run` и breadcrumb
`probe | desktop probe started | level=info | data={source=release-app}`.
Снимки accessibility tree: `build/tracer-console-audit/fixed-{handled,flutter,async}-{stack,keys,logs}-ui.json`.
В async служебный `_Closure.call` по-прежнему без source line — её нет в DWARF;
заголовок карточки сохраняет `Stacktrace not available`, хотя файлы и строки
показаны в событии. FlutterError runtime type остаётся обфусцированным (`yF`)
в заголовке; восстановление имени типа в это исправление не входило.

## Финальная проверка метаданных и группировки — 24 октября 2026

Исправлено имя `FlutterError` при AOT-обфускации: нормализатор проверяет тип
объекта, а не его переименованный `runtimeType`. Другие исключения внутри
`FlutterErrorDetails` сохраняют свой тип. В pinned C-мосте Sentry загрузка
native contexts в Dart не поддерживается. Поэтому после согласия адаптер
читает allowlist из `/etc/os-release`, версию ядра и DMI model/vendor;
архитектура берётся из Dart ABI. Одинаковые данные передаются в официальный
native scope и в Dart event. Hostname, serial и machine-id не читаются.
Lifecycle-проба теперь явно задаёт `environment=desktop-acceptance` и позволяет
проверить `issueKey`; release/dist равны `1.0.0`/`1`.

Финальная Ubuntu 22.04.5 x64 VM-сборка:

- SHA-256 bundle archive:
  `10d877c42c1545d5c7232e32065ad848e0d703b2db45f3bd8eedbdd3b812f6fa`.
- Dart ELF build ID: `29203546f35c990aff19ef5426aa6c25`.
- Native runner build ID: `bc8ea719fde3704845b42b656650ce87d49bd478`.
- Локально: 82 facade-теста, 22 desktop-теста (ещё 2 macOS skip), widget test,
  22 Python-теста; анализ изменённых пакетов без замечаний.
- На чистой VM без toolchain прошли 14 сценариев: disabled/deferred/smoke,
  lifecycle, grouping, native/native-inflight, три Dart retry/revoke/discard,
  readonly bundle и три режима Dart-карты (resolved/missing/mismatched).
  Результаты: `build/ubuntu-vm/run-1792844483095611242/reports`.

Live run `linux-final-20261024-1223-a7e30a`: 8 неизменённых SDK envelopes через
диагностический TLS relay получили HTTP 200, без дублей и без очереди после
успешной доставки/restart. Это три Dart smoke-пробы, три ошибки аккаунта A,
одна ошибка аккаунта B после clear/restart и его native crash. Все восемь
содержат Ubuntu 22.04, kernel `5.15.0-198-generic`, x86_64, QEMU/Standard PC,
правильные environment/dist. `FlutterError` в обфусцированной сборке имеет
стабильное имя. Dart source lines остаются `main.dart:45/55/64`, native —
`my_application.cc:21`.

Самостоятельно в консоли проверены две группы одного текста: 3 события / 2
пользователя для одного fingerprint и 1 событие / 1 пользователь для другого.
Поиск `linux-final-account-B` возвращает ровно его Dart-событие 15:23:36 МСК
и SIGSEGV 15:23:41. В native-карточке проверены userId, ключи `probe_run` и
`account_marker`, breadcrumb B без A, а также три исходных native-кадра.
OS/device данные проверены в Dart- и native-карточках. Исходящие SDK envelopes
аккаунта B также проверены на отсутствие A. Локальные UIA-снимки и receipt:
`build/linux-final-acceptance/`.

**Разделение с ограничениями сервиса:** Tracer извлекает `os.name`, `os.version`
и `device.arch` в «Данные → Other», остальные OS/device поля — в Context.
Стандартные виджеты ОС/устройства остаются пустыми, `Stacktrace not available`
сохраняется над реально отображаемыми исходными кадрами. Клиентское исправление
не меняет серверный parser/UI. Environment/dist проверены в SDK payload;
фильтр Environment для C/C++ не заявлен сервисом как поддерживаемый
([документация Tracer](https://apptracer.ru/doc/intro/crashes/)). Сохранение Context
соответствует [описанному Sentry-мосту](https://apptracer.ru/doc/other-platforms/quick-start/).
Эти ограничения не следует выдавать за исправленные или обходить подменой платформы.

Код опубликован для проверки в отдельной ветке
[`codex/task13-ubuntu-acceptance`, PR #2](https://github.com/KonstantenKomkov/apptracer_flutter/pull/2),
commit `04569a097380545a7f9a14aeee1e812c207d13c1`. Ubuntu CI включает
21 release-сценарий, в том числе реальный 15-минутный retry без restart.
Статус и артефакты:
[Ubuntu CI 40093674274](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40093674274).
Workflow завершился успешно: все 21 сценарий подтверждены по сохранённым логам,
обе проверки восстановления исходных строк также прошли. Артефакт
`ubuntu-22.04-x64-preparation` (ID `12560780565`, хранение до 07.11.2026):
SHA-256 `387fd4faae11aa3804c5dbb02a771818b4288338a6d23f94e1601d420c89374d`.
На том же commit зелёные общий CI `40093674303`, Windows `40093674245`,
macOS desktop `40093674366` и macOS Dart AOT `40093674357`.
Основная ветка и публикация пакетов не изменены.

## Жизненный цикл и ограничения

До согласия не запускаются SDK/crash daemon и не открывается очередь. Linux lifecycle
использует официальный `SentryNative.createOptions` и public native consent API,
а стандартная автозагрузка native SDK удалена из списка integrations. Это
привязано к точной версии SDK; обновление требует повторного аудита.

Очередь: `$XDG_DATA_HOME/apptracer_desktop/<executable-name>/v1/queue`, fallback —
`$HOME/.local/share`. Имя executable должно быть постоянным и уникальным для
приложения. Процесс держит эксклюзивную блокировку namespace. Смена пути установки
не меняет очередь; симлинки в пути отвергаются. При `preservePreviousReports:false`
старые отчёты удаляются до native init. Пример явно задаёт `true` для crash/restart.

Официальный Dart SDK сериализует события; envelope передаётся через
`sentry_envelope_deserialize`/`sentry_capture_envelope` официальному native SDK.
Включены `SENTRY_CACHE_KEEP_OFFLINE` и HTTP retry с backoff. Собственного
HTTP-транспорта нет; восстановление парного minidump в cache описано выше.
API retry экспериментальный и закреплён
версией native SDK.

Теперь Dart и native envelopes используют транспорт sentry-native 0.16.6:
сетевые обрывы сохраняются для повторной доставки, HTTP 5xx отбрасываются.
Первый плановый retry без перезапуска — через 15 минут, затем backoff, максимум
6 попыток. Поэтому `dart-online` занимает около 15 минут; при restart сохранённая
очередь отправляется раньше. Native retry проверяется сетевым обрывом и restart.
Прежняя проверка Crashpad после HTTP 503 относится только к старому backend.

`stop` отзывает native consent, сохраняет маркер `revoked` до `Sentry.close`
и отменяет отправки. Мост находит `sentry-crash` того же UID по открытому
`<UUID>.run.daemon.lock` непосредственно в собственной заблокированной очереди.
Старый Crashpad распознаётся по точному `--database` для этой очереди. Мост закрепляет процесс
pidfd, повторно проверяет принадлежность, останавливает и ждёт завершения.
Это требует Linux x86_64, kernel ≥5.3 и доступного `/proc`; ошибки не выдаются
за успешную остановку. Чужие очереди/UID/процессы не затрагиваются.
`clear` дополнительно удаляет очередь и
заменяет её пустым файлом против поздних writers. Следующий процесс удаляет
отозванные данные даже при `preservePreviousReports:true`. После native startup
повторное включение требует рестарта; чужой SDK/адаптер не закрывается.
Результат stop — `restartRequired / linux_stopped_restart_required`, clear —
`restartRequired / linux_cleared_restart_required`; до native init — `disabled`.
Уже принятые сервером данные не отзываются.

**Открытые ограничения:**

- Не проверены физический компьютер и все GTK/Wayland окружения.
- Для новой сборки с компактной картой автоматические Dart source frames,
  userId/key/breadcrumb всех трёх проб подтверждены в консоли. Без карты
  серверное восстановление строк по загруженным символам не заработало.
  Группировка, смена аккаунта и доставка OS/device metadata дополнительно
  проверены финальной серией выше; ограничения виджетов сервиса сохраняются.
- Flutter SIGSEGV доставлен и подтверждён пользователем. После upload сервер
  оставлял исходные файлы/строки `unknown`; теперь crash daemon передаёт точные
  native file/line до доставки, и пользователь подтвердил их отображение в новом
  событии. Это клиентская символизация; Dart AOT проверен отдельно выше;
  системные/Flutter-кадры без карт и надпись `Stacktrace not available` остаются.
- Другие дистрибутивы, ARM64 и Аврора этой проверкой не покрываются.

Ревью выполнено: исправлены JNI/JAVA_HOME, CMake install prefix, права handler,
проверка всех копий Crashpad, отмена Dart socket до ожидания serial queue,
повторная проверка согласия непосредственно перед native init и безопасный
отказ при некорректном типе маркера отзыва.
Регрессии старых Python parsers проверены; Windows/macOS lifecycle сохраняет
свои отдельные реализации и протоколы приёмки.
