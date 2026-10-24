# Windows 11 x64: локальная приёмка 24 октября 2026

До выпуска 1.0.0 проверена реализация optional desktop-пакета на
пользовательском Windows 11 x64, build 22631.7582. Исходная ревизия —
`86ca9ba936b08edf56ba33ec0c52e1b266425c98` плюс рабочие изменения Windows.
Flutter 3.35.5 / Dart 3.9.2, Visual Studio 2022 17.14, Windows SDK 26100,
Sentry Flutter 9.30.1 / native 0.16.6. CI сохраняет отдельный pin Flutter 3.47.4.
Новые инструменты, кэши и временные файлы размещены под `D:\Tools`.
Общие компоненты Microsoft SDK/installer используют также существующие пути C.

## Реализация

Официальный native backend доставляет SDK envelopes с minidump attachment.
Crashpad `/minidump/` больше не используется. Native SDK владеет crash handling,
сериализацией и persistent retry; собственный HTTP uploader не добавлялся.
Собственный каталог — `%LOCALAPPDATA%/apptracer_desktop/<exe-name>/v1`.
Disabled/deferred не запускают SDK. По умолчанию прежняя очередь удаляется;
`preservePreviousReports: true` восстанавливает её после обычного выхода/crash.
Stop сначала отзывает consent, закрывает native transport и останавливает
daemon, найденный по точному lock-файлу, PID/creation time и стабильному handle.
Отзыв сохраняется между процессами независимо от preserve. Clear удаляет
очередь и оставляет пустой файл против позднего восстановления. После native
init требуется новый процесс; до init результат stop/clear — `disabled`.
Уже принятые сервером данные не удаляются. Системные WER-отчёты не очищаются.

Storage отвергает junction/reparse-point в предках. Один процесс владеет
namespace до выхода; второй отказывает безопасно. Путь установки может быть
read-only. Старые Sentry/Crashpad кэши не импортируются и не удаляются.

Native source mapping выполняется внутри здорового crash daemon по точной
паре PE/PDB GUID+age. Dart mapping проверяет build ID raw stack, загруженного
`data/app.so` и компактной карты; исходный стек сохранён. Это клиентская
символизация, не подтверждение серверной обработки PDB/DWARF. Карты раскрывают
имена функций и пути; полные символы и исходный код в bundle не нужны.

В sentry-native 0.16.6 обнаружено ANSI-кодирование Windows module paths:
кириллица делала event JSON невалидным UTF-8. Обёртка только daemon использует
GetModuleFileNameExW/CreateFileW и UTF-8. Исходники SDK не изменены; при обновлении
pin требуется повторный аудит. App-local MSVC DLL входят в bundle.

## Локальные результаты

Все 24 release-сценария прошли; JSON находятся в `build/windows-local/`:

| Проверки | Результат |
| --- | --- |
| disabled / deferred / smoke | 0 / 0 / ровно 3 Dart-события |
| lifecycle | 18 команд: stop/clear, re-consent, новая учётная запись |
| grouping | same/same/different, после clear новое событие от B без данных A |
| native / revoked / discard / inflight | access violation, идентичный SHA-256/event ID при retry; после отзыва replay отсутствует; запрос отменён |
| dart-retry / online / revoked / discard | persistent Dart очередь; online retry без перезапуска, в локальном прогоне примерно через 15 минут |
| missing-handler / unwritable-storage | безопасный `error`, сетевых запросов нет |
| missing/mismatched native symbols | отчёт сохранён, чужие file/line не применяются |
| junction-storage / junction-queue-entry | отказ при подмене storage; чужой sentinel переживает clear |
| concurrent-owner | второй процесс отказывает; первый продолжает отправку |
| readonly-bundle | ACL запрещает запись; запуск, отправка и clear проходят |
| Dart resolved / missing / mismatched | строки main.dart 45/55/64 только с точной картой; raw stack сохранён |

Дополнительно: 22 Python unit tests, анализ/тесты desktop, facade и example.
Финальный desktop-прогон: 20 passed, 6 platform-specific skipped, анализ чистый.
Независимый minidump-stackwalk 0.27.0 с dump_syms 2.3.9 восстановил
`ApptracerNativeCrashProbe`, `windows/runner/flutter_window.cpp:16`,
`trust=context`. PE/PDB GUID `2e694834-0134-47c8-b00b-f7b38a90c9f0`, age 2;
код исключения `0xc0000005`. Отчёт: `build/windows-local/native-symbols/report.json`.
Архивы инструментов проверены по SHA-256, зафиксированным в workflow.

## Tracer

По явному решению пользователя использован существующий C/C++-проект Test
с локальными Linux credentials. Значения DSN/token нигде в этом документе
и runtime bundle не сохранены. Серия `windows-20261024-165633`:
три Dart-ошибки, три события группировки от windows-live-A, clear/restart,
событие same-group от windows-live-B и native crash от B. Все восемь ответов
HTTPS — 200; повторный запуск не дал дублей. Диагностический relay пересылал
официальные SDK bytes без изменений. Receipt:
`build/windows-live/windows-20261024-165633/report.json`.

В открытой аутентифицированной консоли непосредственно проверены handled Dart
и native: время серии, user, run key, breadcrumbs и исходные file/line.
Native — 16:56:51 MSK, windows-live-B, Windows/x86_64, release 1.0.0,
unhandled signalhandler и ApptracerNativeCrashProbe:16. Handled — 16:56:45,
desktop-test-user, main.dart:45/89. Список сбоев показывает две новые группы
Windows: 3 события/2 пользователя и 1 событие/1 пользователь.
Снимки UI сохранены в `build/windows-live/*-ui.json`.
Последние FlutterError/async в 16:56:46 также проверены в консоли: ключ серии,
main.dart:55/90 и main.dart:64 соответственно. Для группировки проверен список
счётчиков 3/2 и 1/1; account isolation дополнительно проверена по envelopes
и локальному lifecycle. Полная сверка всех полей каждой карточки не заявляется.
Получение 200 само по себе не заменяет перечисленные console-проверки.

Ограничения C/C++ Tracer UI: `Stacktrace not available` может оставаться над
читаемыми кадрами; OS/device доступны в Data → Other/Context, хотя виджеты пусты.
Заголовок общей группы может показывать старый Linux-стек, поэтому проверяется
конкретное событие. Environment/dist есть в SDK envelope, специальный фильтр
сервиса не принимается как доказательство их поддержки.

## Внешние потребители и выпуск

Два изолированных Flutter Windows consumer, без monorepo overrides: desktop
path + hosted facade 0.2.1; desktop path + staged facade 0.2.2. Interface 0.2.0
и остальные siblings — hosted. Оба obfuscated release с точными Dart maps,
app-local MSVC runtime перенесены вне checkout. Runtime PATH содержит только
Windows/System32: обработаны ровно три события после фильтрации/дедупликации,
исходные кадры и stop/clear корректны. Staged 0.2.2 сохраняет FlutterError;
hosted 0.2.1 показывает обфусцированное имя, известное ограничение старого facade.

Отчёты: `build/windows-consumer-hosted/report.json`,
`build/windows-consumer-candidate/report.json` и `runtime/report.json`.
У candidate сначала был harness-only KeyError SystemRoot до запуска приложения;
после исправления повторно проверен тот же архив, без пересборки.
Publish dry-run: facade — 0 предупреждений, desktop — одно намеренное
предупреждение о точном SDK pin. Ничего не опубликовано.

Оба consumer повторно прошли runtime после исключения полных PDB из поставки;
результаты `runtime_without_pdb` сохранены в отчётах. MSVC создаёт PDB рядом с
EXE в build output; при упаковке он перенесён в отдельный private symbols artifact.
Готовый пример: `build/windows-release/apptracer-windows-x64.zip`, 12 538 631 байт,
SHA-256 `3b62d52ee653735d33b8b9810fd44918e9146986d111d92af6cdef60119aa9d8`.
Проверены smoke/native/lifecycle именно упакованного каталога без PDB;
`manifest.json` содержит SHA-256 каждого runtime-файла.
`verification.json` перечисляет 24 сценария, проверки workflow и secret scan:
значения локальных DSN/token не найдены в 480 проверенных source/archive entries.
Исторический `native-debug.json` сохраняет первоначальный отказ до исправления
UTF-8 и не входит в финальные 24 сценария.

Windows preparation с native backend прошёл в GitHub Actions:
[40104502715](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40104502715)
на `196e75d` и повторный PR-прогон
[40105473898](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40105473898)
на `db8b602`. Flutter 3.47.4 / Dart 3.13.3: анализ, тесты, obfuscated release,
точные Dart/native maps, три режима Dart-карт и disabled/deferred/smoke прошли.
Общий [CI 40105473906](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40105473906)
также зелёный: семь пакетов, Android/Web examples и publish dry-run.
Полный [Windows runtime 40105339434](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40105339434)
на `db8b602` также прошёл: все 18 сценариев, 22 Python tests и независимая
проверка minidump/PDB/source frames. Вместе с preparation проверены все 24
сценария текущего native backend. Повторный прогон исправляет сравнение
текстовых Windows-путей в test receiver: теперь проверяется идентичность
файла, включая короткие имена и различие регистра. Сам crash envelope
в первом прогоне был получен; ошибка относилась к его проверке.
Исторические CI runs в отдельных документах относятся к Crashpad.
Локальная копия всех 18 JSON и шести symbolication reports:
`build/windows-followup/ci-40105339434/evidence.json`;
runtime artifact SHA-256
`7ac7c0d6c5266a48054b8d7f4d47f8357482a234432e2de235e4808984ce8cfd`.
Точный CI PDB GUID `2708c64f-7b1e-4078-8875-7b7ccb4cb2c4`, age 1;
все шесть minidump дают `ApptracerNativeCrashProbe`, flutter_window.cpp:16,
`trust=context`. Общий PR также прошёл macOS и Ubuntu workflows; общий
receiver с проверкой идентичности файлов не нарушил Linux-приёмку.

CI runtime-архив без полных PDB:
`build/windows-release/apptracer-windows-ci-x64.zip`, 12 821 894 байта,
SHA-256 `8016c7becb5ce0ac54cf8e19e4b118c99906bc3a131784a93322cc1d9480b0ec`.
В нём 26 runtime-файлов и manifest с их SHA-256. Исходный Actions artifact
12563888956 имеет SHA-256
`84053aba9f91e6c3447c617089b6164b5df03009a1ec4e0b99f6941dd31bf894`.

Финальный staged consumer после исправления совместимости ELF reader с Dart
3.13 повторно прошёл analyze/tests, оба dry-run и runtime. Отчёт:
`build/windows-consumer-final-candidate/report.json`; три события, исходные
кадры, stable FlutterError, filtering/deduplication и stop/clear подтверждены.
Bundle SHA-256 `8e0610cd45058ac669b528d5712374b6e871fd4222ccf7b701a61e06cae8aea1`.
На этапе staged-приёмки публикация была отложена. Позже в тот же день
пользователь утвердил стабильный выпуск 1.0.0; фактический результат ниже.

## Чистая Windows VM

Отдельная установка Microsoft Windows 11 Enterprise Evaluation,
версия 10.0.26300, build 26300,
x64 из официального Microsoft evaluation ISO. SHA-256 ISO:
`bc3f24086ebadc94489066b5ad78089e2cf5c3491e90e790bb81a2b199c10e38`.
UEFI/TPM 2.0, 4 vCPU, 5 GiB RAM; диск VM физически расположен на D,
в `D:/WSL/ApptracerUbuntu/ext4.vhdx`. Flutter, Dart, Visual Studio, SDK,
CMake, Ninja, Java и Git в гостевой системе не установлены. Проверки исполнялись
с неповышенным токеном пользователя tracertest. Embedded Python использован
только как тестовый драйвер, средства сборки в VM не переносились.

Все 11 проверок прошли: disabled/deferred/smoke, lifecycle, native crash/retry,
native-revoked, dart-retry, readonly-bundle, concurrent-owner и два внешних
consumer (hosted facade 0.2.1 и staged facade 0.2.2). Готовые приложения
перенесены без полных PDB, с app-local MSVC DLL; пример взят из CI 40104502715,
candidate — из финального локального consumer-прогона. Payload SHA-256:
`781f0aae5f26dfd72177bc366d2ddc219107233b5055bd026553aa01a62d4876`.

Отчёты: `build/windows-clean-vm/evidence.json`, `environment.json`, `summary.json`
и отдельные runtime JSON. Архив исходных отчётов SHA-256:
`1db1907d108f503fc3743d4d8aaa23a60f045dea157eaed0f19ad4524d9dcd93`.
Первичная настройка Windows потребовала восстановления
DNS внутри WSL и штатного обновления/перезапуска; эти этапы не засчитывались
как runtime-проверки. После настройки ОС исходная конфигурация DNS восстановлена.
Первый подготовительный запуск остановился до приложения: копия с ISO сохраняла
read-only attributes. Атрибуты исправлены только внутри копии тестовых файлов,
после чего тот же CI payload проверен повторно; исходный отказ сохранён в
`build/windows-followup/vm-first-attempt.zip`.
Первый lifecycle-прогон выявил слишком короткое ожидание завершения аварийного
процесса после stop/clear: штатный `WerFault.exe` ещё собирал отчёт. Повтор
подтвердил все 18 шагов; Windows crash timeout в тестовом receiver увеличен
с 20 до 120 секунд, Linux остаётся 20 секунд. Настройки WER и код SDK не менялись.
Полный финальный прогон использует этот receiver; диагностические попытки
сохранены отдельно в `build/windows-followup/vm-*-attempt.zip` и
`vm-focused-passed.zip`. Загрузка с дополнительными Hyper-V enlightenments
вложенной VM не удалась; приёмка выполнена с исходным `-cpu host`.

Повторный CI 40113884393 подтвердил lifecycle и native-сценарии, но выявил
короткий лимит `dart-online` в receiver: 950 секунд. В
[sentry-native 0.16.6](https://github.com/getsentry/sentry-native/blob/0.16.6/src/sentry_retry.c)
проверка очереди идёт каждые 15 минут, а первая повторная отправка разрешена
после достижения событием возраста 15 минут. По этому алгоритму poll,
запланированный чуть раньше записи события, переносит отправку на второй цикл:
обычно 15–30 минут после первой сетевой ошибки, затем растущий backoff.
Лимит `dart-online` увеличен до 1850 секунд; проверка выполняется без restart
и без изменения расписания SDK. Остальные условия, включая event ID и user,
сохранены. Failed evidence: `build/windows-followup/ci-40113884393-failed.zip`.

Windows 10 и ARM64 не проверены. Выпуск стабильных facade/desktop 1.0.0 описан в [publishing.md](publishing.md).

## Опубликованный потребитель 1.0.0

24 октября 2026 facade и desktop **1.0.0** опубликованы на pub.dev как стабильные
пакеты. [Публикация и контрольные суммы](publishing.md#stable-100--2026-10-24).
`check_windows_consumer.py --hosted-desktop 1.0.0 --facade-version 1.0.0`
создал новое Windows-приложение: все семь Tracer-зависимостей получены с pub.dev,
без path/git/overrides. Analyze и обфусцированная release-сборка прошли.
Перенесённый bundle с ограниченным PATH доставил ровно три события; подтверждены
фильтрация, дедупликация, исходные Dart-кадры, имя FlutterError и stop/clear.
Незапрошенная телеметрия отсутствует. Native daemon и MSVC runtime включены.

Отчёт: `build/windows-consumer-published/report.json`. Bundle SHA-256:
`7d8e0fa411d4520fe0a12e47957a7332e65da3e03b9d84f07e61291c2001ed65`.
Эта проверка дополняет прежние 24 сценария и 11 проверок чистой Windows VM;
Windows 10/ARM64 по-прежнему не проверены.
