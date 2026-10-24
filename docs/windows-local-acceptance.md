# Windows 11 x64: локальная приёмка 24 октября 2026

Проверена текущая неопубликованная реализация optional desktop-пакета на
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
| dart-retry / online / revoked / discard | persistent Dart очередь; online retry без перезапуска после штатных 15 минут |
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

Новый workflow подготовлен для 24 сценариев и source maps; текущая версия ещё
не запускалась в GitHub Actions. Исторические CI runs относятся к Crashpad.
Windows 10, ARM64 и чистая Windows VM без установленного toolchain не проверены;
ограниченный PATH на разработческой машине не заменяет чистую VM.
Публикация facade 0.2.2/desktop и hosted desktop-проверка остаются отдельным выпуском.
