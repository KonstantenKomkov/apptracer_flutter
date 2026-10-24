# Выполненные задачи итерации v1

Активный план: [development_v1.md](development_v1.md).

## Windows — завершённый локальный объём, 24 октября 2026

Граница приёмки: Windows 11 x64 22631.7582, Flutter 3.35.5 / Dart 3.9.2,
MSVC 2022 17.14, Sentry Flutter 9.30.1 / native 0.16.6. Инструменты на D.
[Полный протокол](../windows-local-acceptance.md), [команды](../windows-preparation.md).
Чистая Windows 11 x64 VM без toolchain прошла 11 runtime/consumer-проверок;
Windows 10/ARM64 не проверены. Новый CI прошёл все 24 сценария
и независимую PDB/minidump-проверку; публикация отложена пользователем.

<a id="task-3"></a>

### П. 3. Подключить Windows

**Завершено в указанной области.** Автоматическая Dart/FFI-регистрация,
Windows runner, официальный native backend и app-local MSVC runtime.
Обфусцированный release перенесён вне checkout в путь с пробелами/кириллицей;
проверен read-only install. Handled/FlutterError/async и native crash доставлены
в существующий C/C++-проект по решению пользователя. Native exception
0xc0000005 имеет собственные minidump/PDB/source-line и Tracer-свидетельства.

<a id="task-1-windows"></a>

### П. 1.Windows. Среда и привязка проекта

**Завершено.** Toolchain установлен/проверен; Windows/VS в flutter doctor зелёные.
DSN существующего C/C++ Test использован по явному выбору пользователя.
Версии, пути, архитектура и ограничения закреплены в протоколе/матрице.
Рабочие credentials не добавлены в исходники или runtime bundle.

<a id="task-5-windows"></a>

### П. 5.Windows. Dart AOT и native исходные кадры

**Реализовано и проверено локально/live в описанной области.** Точная привязка
ELF build ID для Dart и PE/PDB GUID+age для native, компактные клиентские карты,
отрицательные missing/mismatch-сценарии. main.dart:45/55/64 и
ApptracerNativeCrashProbe:16 восстановлены в SDK events. Native, handled, FlutterError и async source frames непосредственно
сверены в консоли; точный объём проверки полей перечислен в протоколе. Серверная символизация не заявлена.

<a id="task-8-windows"></a>

### П. 8.Windows. Consent, очередь, stop/clear и retry

**Завершено.** 18-шаговый lifecycle, durable revoke, default discard,
native/Dart retry, 15-минутный retry без перезапуска, in-flight cancellation,
смена аккаунта, конкурентный владелец, junction protection и очистка
без повреждения чужого каталога прошли. Native init требует нового процесса
для возобновления; ошибки shutdown/cleanup не маскируются как disabled.

<a id="task-10-windows"></a>

### П. 10.Windows. Пример, команды и CI

**Реализация завершена.** Release/helper, inherited lifecycle pipes, exact-build
maps, 24 локальных release-сценария, сохранение PDB/DWARF/отчётов и новый workflow.
Команды проверены на Windows; текущая версия прошла GitHub Actions preparation
40104502715 / 40105473898 и полный runtime 40105339434. Все 24 сценария и
независимая проверка шести minidump по точному PDB прошли.

<a id="task-12-windows"></a>

### П. 12.Windows. Внешние потребители и документация

**Завершён подготовительный объём.** Два независимых consumer без overrides:
hosted facade 0.2.1 и staged 0.2.2, hosted interface/siblings, obfuscation,
перенос bundle с MSVC DLL, ограниченный runtime PATH, filtering/dedup/source/clear.
Dry-run desktop/facade прошёл; у desktop одно намеренное SDK-pin предупреждение.
Исправление FlutterError требует staged 0.2.2. Инструкции RU/EN, migration,
symbolication, статус и границы согласованы. Ничего не опубликовано.


<a id="task-1-ubuntu"></a>

## П. 1.Ubuntu. Среда, конфигурация и границы поддержки

**Завершено 24 октября 2026.** Зафиксированы Ubuntu 22.04.5 x86_64 VM,
glibc 2.35, GTK 3/X11, kernel 5.15, Flutter 3.47.4 / Dart 3.13.3,
Sentry Flutter 9.30.1 / native 0.16.6 и native envelope backend. DSN C/C++-проекта
и plugin token проверены без записи значений в документацию. Граница optional
пакета, регистрация, native/Dart API, consent, очередь и символы описаны по
фактическим результатам, включая отсутствующие server widgets и crash-free.
Обновлены [аудит](../desktop-aurora-sdk-audit.md),
[матрица](../platform-matrix.md) и [протокол](../linux-preparation.md).
Windows/Аврора остаются в общем №1; целевая среда Авроры не выводится из Ubuntu.

<a id="task-12-ubuntu"></a>

## П. 12.Ubuntu. Документация, внешний потребитель и подготовка выпуска

**Завершено 24 октября 2026.** Два новых внешних Ubuntu release-потребителя
без monorepo overrides: desktop path + hosted facade 0.2.1 и desktop path +
staged facade 0.2.2; все остальные siblings из pub.dev. Проверены CMake/native
handler, изолированная сборка с обфускацией, карты точной сборки, перенос bundle
и запуск обоих вариантов на чистой Ubuntu 22.04.5 x64 VM без build toolchain.
Фильтрация/дедупликация, поля, исходные кадры и stop/clear прошли.

Оба staged publish dry-run приняты: у facade 0 предупреждений, у desktop одно
документированное предупреждение точного SDK pin. Plugin token не найден в
проверенных bundle/экспортируемых исходниках. RU/EN README, инструкции внешней
установки, status/матрица, symbolication/privacy и аудит согласованы.
Добавлены воспроизводимый helper и отдельный Ubuntu consumer CI job;
команды прошли локально, новый hosted job отдельно не запускался.

**Свидетельства:** [полный протокол, SHA-256 и границы](../ubuntu-consumer-acceptance.md).
Стабильное имя обфусцированного FlutterError требует staged facade 0.2.2;
hosted 0.2.1 успешно доставляет события, но показывает обфусцированное имя.
Зафиксирован порядок будущего выпуска: facade 0.2.2 → desktop 0.1.0-dev.1.
Версии в рабочем дереве и `publish_to: none` сохранены до release commit.
Финальная публикация и проверка hosted desktop-пакета — отдельное действие,
не незавершённая Ubuntu-реализация. Общий №12 для остальных платформ открыт.

## Дополнительно выделенный выполненный объём — сверка 24 октября 2026

Следующие подзадачи выделены из общих №5/8/10/11 по существующим протоколам,
коду и сохранённым отчётам. Это не новые runtime/live-прогоны. Общие задачи
остаются в активном плане; номера и границы платформенной приёмки сохранены.

<a id="task-5-ubuntu"></a>

## П. 5.Ubuntu. Dart/native символизация и исходные кадры в Tracer

**Завершено 24 октября 2026 для Ubuntu 22.04.5 x64 VM в рамках №13.**
Сохранены ELF и символы точных release-сборок; helpers проверяют build ID
binary/symbols/stack/minidump. Локально восстановлены три обфусцированных
Dart AOT стека и native `apptracer_native_crash()`, `my_application.cc:21`,
с `trust=cfi`. Проверены отсутствующие и несовпадающие карты.

Native crash daemon восстанавливает кадры по точным Breakpad-картам;
Dart-адаптер — по компактной карте перед сериализацией SDK. В новых событиях
Tracer подтверждены `main.dart:45/55/64` и native `my_application.cc:21`.
Upload четырёх модулей через vendor tool успешен, но самостоятельное серверное
восстановление строк не заработало: принятый результат использует клиентские карты.

**Свидетельства:** [протокол, build ID, event IDs и команды](../linux-preparation.md),
`tool/symbolize_linux_{dart,native}.py`, `tool/prepare_linux*_symbols.py`,
`lib/src/linux_dart_symbols.dart` и `linux/native_symbols.cc` desktop-пакета.
Локальная расшифровка и негативные сценарии дополнительно прошли в
[CI 40093674274](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40093674274).

**Ограничения:** карты раскрывают имена/пути; для Dart предусмотрен opt-out.
Кадры без карт могут оставаться unknown. Серверная символизация и исправление
подписи `Stacktrace not available` не заявляются. Windows и macOS live Dart AOT
остаются в [№5](development_v1.md#task-5).

<a id="task-8-macos"></a>

## П. 8.macOS. Остановка, очистка и восстановление очереди

**Выполнено 23 октября 2026; выделено в архив 24 октября.** На macOS arm64
реализованы инертная регистрация, собственная native lifecycle integration
с публичными Cocoa API, отмена сети до close, сохранённый отзыв очереди,
удаление собственного cache/async.log. Пройдены 55 release-шагов: deferred,
повторные вызовы, offline/in-flight, разрешённое восстановление, default purge,
crash после stop и смена пользователя. SDK/Swift storage-проверки и четыре
runtime-регрессии прошли; проверки включены в macOS CI из №10.macOS.

**Свидетельства и границы:** [протокол](../macos-lifecycle-acceptance.md),
реализация `a373234`, [CI-приёмка](../macos-ci-consumer-acceptance.md).
После native init повторный старт требует нового процесса. Исторические cache,
проверенные версии ОС и границы очистки описаны в протоколе; Intel и минимальная
ОС не приняты. Общая [№8](development_v1.md#task-8) остаётся для Windows/Авроры.

<a id="task-8-ubuntu"></a>

## П. 8.Ubuntu. Consent, очистка, retry и изоляция аккаунтов

**Завершено 24 октября 2026 для Ubuntu 22.04.5 x64 VM в рамках №13.**
До согласия SDK/очередь/метаданные не запускаются. Собственная очередь имеет
блокировку и сохранённый маркер отзыва; clear удаляет данные и блокирует позднюю
запись. Native consent отзывается до close. Собственный `sentry-crash`
останавливается через pidfd с проверками UID и принадлежности очереди;
предусмотрена очистка прежнего Crashpad. Чужие процессы/очереди не затрагиваются.

**Приёмка:** 18-шаговый lifecycle, разрешённое восстановление Dart/native,
revoke/discard, in-flight cancellation, restart и изоляция аккаунтов.
15-минутный retry Dart без restart и отдельные native-сценарии прошли в Ubuntu CI.
После native init возвращается `restartRequired`; новый процесс не отправляет
отозванные данные даже при `preservePreviousReports:true`.

**Свидетельства:** [протокол](../linux-preparation.md),
`build/linux-final-acceptance/ci-evidence.json` и `acceptance-summary.json`,
[CI 40093674274](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40093674274).
Требуются Linux x64, kernel ≥5.3 и доступный `/proc`; уже принятые сервером
данные не отзываются. HTTP 5xx отбрасываются native SDK, проверенный retry
относится к сетевому обрыву. Windows/Аврора остаются в [№8](development_v1.md#task-8).

<a id="task-10-ubuntu"></a>

## П. 10.Ubuntu. Пример, release CI и артефакты

**Завершено 24 октября 2026 в рамках №13.**
[`linux.yml`](../../.github/workflows/linux.yml) собирает Ubuntu 22.04 x64 release
на Flutter 3.47.4, запускает перенесённый bundle под Xvfb, выполняет analyze,
unit/widget/Python-проверки и **21 release-сценарий**, включая 15-минутный retry,
consent/clear, grouping, native crash и отсутствующие/чужие карты символов.
Локальное восстановление Dart/native исходных строк — отдельные шаги CI.
Живые ingest/upload credentials не требуются.

**Свидетельства:** [успешный CI 40093674274](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40093674274)
на `04569a097380545a7f9a14aeee1e812c207d13c1`; сохранённые статусы и сценарии —
`build/linux-final-acceptance/ci-runs.json` / `ci-evidence.json`.
Артефакт `ubuntu-22.04-x64-preparation`, ID `12560780565`, содержит bundle,
символы, lockfile, toolchain и отчёты; срок хранения до 07.11.2026.
[Протокол](../linux-preparation.md) содержит локальные команды, результаты чистой
VM без toolchain и отдельные границы WSL2. Общий CI, Windows и два macOS workflow
на том же commit успешны по сохранённым результатам.

Windows lifecycle, Аврора и окончательная сверка общих инструкций остаются
в [№10](development_v1.md#task-10). Это не новая live-приёмка и не публикация.

<a id="task-11-ubuntu-live"></a>
<a id="task-11-ubuntu"></a>

## П. 11.Ubuntu-live. Проверенная live-серия в Tracer

**Завершено 24 октября 2026 для Ubuntu 22.04.5 x64 VM в рамках №13.**
Подзадача фиксирует проверенные live-сценарии, а не все общие критерии №11.
В трёх Dart-пробах подтверждены исходные строки `main.dart:45/55/64`, userId,
ключ запуска и breadcrumb. Native Flutter runner SIGSEGV доставлен с исходными
кадрами, в том числе `my_application.cc:21`; это отдельная crash-проба.

Финальная серия `linux-final-20261024-1223-a7e30a`: восемь неизменённых SDK
envelopes получили HTTP 200, без дублей и pending queue после успешной доставки.
В консоли проверены две группы с 3/1 событиями и 2/1 пользователями, новый
аккаунт после clear/restart, его Dart/native события и breadcrumb без старого
аккаунта. OS/device metadata видны в Other/Context. Native source frames и
пользовательские поля проверены в карточке события.

**Свидетельства:** [полный протокол и event IDs](../linux-preparation.md),
`build/linux-final-acceptance/acceptance-summary.json`, receipts/UIA-снимки
в том же каталоге и `build/tracer-console-audit/`.

**Дополнение после внешней приёмки:** release-фильтрация, отсутствие дублей
и лишних SDK telemetry items проверены на двух внешних потребителях, в том
числе на чистой VM. Обновлены `status.md` и `platform-matrix.md`; crash-free
не заявляется, unhandled Dart не выдаётся за падение процесса. Таким образом,
Ubuntu-объём №11 закрыт совокупностью live №13 и VM/CI/runtime-протоколов.
[Дополнительный протокол](../ubuntu-consumer-acceptance.md).

**Границы принятого результата:** offline/revoke/in-flight приняты отдельными VM/CI-пробами,
а не всеми сценариями через live endpoint. Crash-free не заявляется. Сервисные
OS/device widgets, Environment filter C/C++ и подпись `Stacktrace not available`
остаются ограничениями. Расширенные macOS-критерии и Windows/Аврора остаются
в [№11](development_v1.md#task-11).

<a id="task-5-windows-native"></a>

## П. 5.Windows-native. PDB и локальная символизация нативного падения

**Завершено 23 октября 2026.** Самостоятельная локальная подзадача №5.
Live-символизация в Tracer и Windows Dart AOT остаются открытыми.

**Критерий и результат:** точная Windows x64 release-сборка/PDB сопоставлена
с native minidump по GUID/age, сформировано локальное дерево Breakpad.
В двух сценариях (online и повторная отправка сохранённого дампа после HTTP 503)
верхний кадр восстановлен до `(anonymous namespace)::ApptracerNativeCrashProbe()`,
`flutter_window.cpp:16`. Кадр получен из crash context (`trust=context`), а не
сканированием стека. Тестовый runner теперь падает в собственной noinline-функции.

**Проверки:** 14 host Python-тестов; реальная Windows release-сборка и
disabled/deferred/smoke в [CI 40009549554](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40009549554);
crash/restart, offline-restart, проверка символов и сохранение полного артефакта
в [CI 40010387576](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40010387576).
Реализация: `1a0d6ab`, закрепление отдельных symbol tools — `d0c1ebf`,
источник crash context — `1657514`. Отдельное ревью и исправления выполнены.

**Артефакты и ограничения:** `windows-native-evidence` содержит minidumps только
собственных тестовых запусков, EXE/PDB, symbol tree и JSON стеков; хранение CI —
14 дней. Инструменты Mozilla dump_syms 2.3.9 / rust-minidump 0.27.0 загружаются
из официальных releases с проверкой SHA-256. Symbol servers и реальные Tracer
credentials не используются. Полная расшифровка системных/Flutter кадров не
заявляется. [Протокол и команды](../windows-symbols-acceptance.md).
Общий №5, Windows stop/clear №8 и сквозная приёмка №11 не закрыты.

<a id="task-5-macos-dart"></a>

## П. 5.macOS-Dart. Локальная символизация обфусцированного Dart AOT

**Завершено 23 октября 2026.** Самостоятельная локальная подзадача №5;
Windows и live AOT-приёмка в Tracer остаются открытыми.

**Критерий и результат:** отдельный obfuscated release отправил ровно три
handled/FlutterError/async события в loopback. Совпадение UUID исходного стека,
SDK debug image, `App.framework` и `.symbols` проверено; первые кадры
восстановлены до функций и `main.dart:45/55/64`. Добавлены инструмент
`tool/symbolize_macos_dart.py`, полный проверочный сценарий и отдельный CI.
Артефакт содержит исходные стеки, символы arm64/x86_64, ZIP точного приложения,
SHA-256/UUID и JSON отчёт. Runtime принят на macOS 27 arm64; x86_64 только собран.

**Проверки:** release build, реальный запуск после переноса приложения,
10 Python-тестов (включая новые проверки чужих/отсутствующих символов и
повреждённых адресов), отдельное ревью изменений. Значения DSN/токенов не нужны.
[Протокол и команды](../macos-dart-symbols-acceptance.md).
Реализация: `e76bf55`; [CI 40007734317](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40007734317)
также успешно прошёл сборку, расшифровку трёх реальных событий и сохранение
артефакта на macOS 15 arm64.

**Ограничение:** Flutter 3.47.4 / native_stack_traces 0.6.1 не расшифровал эти
стеки (`Cannot locate isolate instructions section in snapshot`); используется
проверенный `atos` по virtual PCs с предварительной проверкой UUID. Исходный
стек не переписывается. Новых проверок серверной native macOS символизации
не проводилось; принятое ограничение сохраняется. Общий №5 не закрыт.

<a id="task-2"></a>

## П. 2. Общий адаптер официального Sentry SDK для desktop

**Завершено 23 октября 2026.** Реализован отдельный optional пакет
[`apptracer_flutter_desktop`](../../packages/apptracer_flutter_desktop/README.md)
на официальных `sentry_flutter 9.30.1` / `sentry 9.30.1`. Основная реализация —
`dd26f96`; последующие lifecycle-проверки — `a373234`, Windows-регистрация и
защита default policy — `b6ccc5b`. Пакет экспериментальный и не опубликован.

**Результат:** единый владелец SDK, конфигурация DSN/release/environment/dist,
преобразование `TracerEvent`, severity/fatal, исходного Dart-стека, breadcrumbs,
ключей, userId и fingerprint/issueKey. `Tracer` сохраняет appRunner, зону и
Dart/Flutter-перехватчики; вторые перехватчики не устанавливаются. Фильтрованные
данные не восстанавливаются из Scope. Пустой/неверный DSN не запускает SDK,
ошибка native init не препятствует запуску приложения; чужой SDK не перехватывается.

Включён явный список необходимых integrations; автоматические sessions,
performance, profiling, replay, logs/metrics, screenshots и лишние breadcrumbs
отключены. Граница фильтрации native crash описана: Dart `beforeSend` не является
нативным фильтром. Старый `apptracer_flutter_sentry` сохранён отдельно, переход
на новый пакет документирован, одновременное использование запрещено.
Основной dependency graph Android/iOS/Web не изменён; пример desktop изолирован.

**Проверки и свидетельства:**

- Analyze, 10 тестов desktop-адаптера и тест примера; в исходной проверке №2/4 —
  80 регрессионных тестов основного пакета и сборка существующего iOS example
  для симулятора. [Протокол №4](../macos-local-acceptance.md).
- Тесты используют официальный SDK: сериализацию и Scope merge, redaction,
  отсутствие лишних обработчиков, invalid DSN, init/close failure, отмену старта,
  Unicode/AOT raw stack, удаление user/key и запрет записи при незавершённом init.
- В C/C++-проекте Test подтверждена live-доставка через SDK с DSN Tracer:
  две серии handled/FlutterError/async и два native SIGABRT, всего 8 новых событий
  без дублей/потерь. Агент самостоятельно сверил пары в консоли; подтверждены
  группировка и поля. [Протокол и event IDs](../macos-lifecycle-acceptance.md).
- Windows x64: [CI 39994523733](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39994523733)
  прошёл release build, disabled/deferred и три Dart-события в loopback;
  [native-протокол](../windows-native-acceptance.md) подтверждает minidump/restart
  и сохранение дампа после HTTP 503. Это дополнительная проверка общего адаптера,
  а не подтверждение live Tracer на Windows.

**Граница закрытия:** завершён общий адаптер SDK по критерию №2 ниже.
Первоначальная отметка «не архивируется» относилась к более раннему состоянию
проверок; macOS lifecycle и повторная live-серия с тех пор пройдены.
Платформенные stop/clear, очистка очереди и запрет replay остаются отдельной
[№8](development_v1.md#task-8); Windows пока возвращает `unsupported` для default
policy удаления старых отчётов и native purge. Полная приёмка всех платформ —
[№11](development_v1.md#task-11), символизация — [№5](development_v1.md#task-5),
совместимость минимальных SDK и выпуск — №10/12. Подключение optional пакета в
общий mobile/desktop consumer добавляет транзитивные Sentry-зависимости и требует
отдельной проверки; это не изменение основного mobile dependency graph.
Закрытие №2 не объявляет Windows/Аврору поддержанными и не закрывает №1 или №8.

**Контекст.** `apptracer_flutter_sentry` — собственная реализация протокола без зависимости
на официальный SDK. Нужен адаптер между `TracerPlatform` и SDK, с единым управлением ошибками.

**Исходный объём работ (выполнен).**

1. Реализовать адаптер официального SDK в согласованной в №1 структуре пакетов;
   определить судьбу старого транспорта и путь перехода для его git-потребителей.
2. Добавить явную конфигурацию Sentry DSN, release, environment и build/dist при необходимости.
   Не смешивать DSN с нативным app token; неверная или пустая конфигурация оставляет сбор выключенным.
3. Отобразить `TracerEvent`, severity/fatal, исходный Dart-стек, breadcrumbs, ключи,
   userId и issueKey в API SDK. Проверить группировку и отображение полей в №11.
4. Назначить одного владельца Dart-перехватчиков и зоны: исключить повторный `appRunner`,
   двойные события и обход `beforeSend`/`beforeBreadcrumb`. Для нативных событий отдельно
   определить доступную фильтрацию: Dart callback не гарантирован при падении процесса.
5. Не включать лишние автоматические интеграции SDK. Проверить отсутствие отправки
   диагностических событий в другой проект или endpoint при штатной конфигурации Tracer.
6. Проверить преобразование событий и отказ инициализации тестами через границу адаптера;
   не подменять проверку официального SDK тестами старого сборщика envelopes.

**Критерий приёмки.** Событие проходит через официальный SDK с DSN Tracer;
адаптер сохраняет публичные гарантии, обработчики не дублируются, ошибки запуска
не мешают приложению. Настройки сторонних платформ не меняются неявно.

<a id="task-4"></a>

## П. 4. Подключить macOS

**Завершено 23 октября 2026.** Проверен runner на macOS 27.0.1 arm64:
release `.app`, официальный Sentry SDK, sandbox network.client, запуск вне IDE
и checkout, включая путь с пробелами/кириллицей. Target — macOS 12.0;
запуск на 12.0 и x86_64 не проверялся и не объявляется поддержанным.

Реализация: `caa6def` (runner/регистрация/пример/приёмник), адаптер — `dd26f96`.
[Полный протокол](../macos-local-acceptance.md) содержит версии SDK, SHA-256
бинарника, команды, локальные event IDs и метки live-запусков.

**Исходная задача:** добавить runner и регистрацию, настроить Apple-зависимости,
минимальную ОС и sandbox, проверить Dart/Flutter/async/native ошибки и restart
без отладчика на заявленных архитектурах, сохранить существующую iOS-интеграцию.

**Критерий приёмки:** release-приложение macOS отправляет события в Tracer через SDK,
работает с принятой конфигурацией sandbox, а существующая iOS-интеграция собирается.
Нативный crash и символизация подтверждаются отдельно от Dart-событий.

**Проверки и результат:**

- Release build, анализ, 6 SDK-тестов, UI-тест native crash confirmation,
  80 регрессионных тестов основного пакета; локальные smoke/disabled/deferred/
  native-crash сценарии. Повторный обзор протокола и diff перед закрытием.
- Пользователь подтвердил три Dart/Flutter/async отчёта в Tracer версии 1.0.0,
  без дублей в первом запуске; все 17 кадров совпали с SDK envelopes.
- В FlutterError подтверждены userId, точный ключ запуска, исходный Context
  и breadcrumb с категорией, уровнем и данными.
- Нативный SIGABRT завершил процесс, последующий запуск успешно включил SDK;
  пользователь подтвердил отчёт `SIGABRT / Signal 6, Code 0` со стеком до `abort`.
- Существующий iOS example собран для симулятора без Sentry в его plugins/frameworks;
  автоматические миграции тулчейна не включены в изменения iOS-исходников.

**Ограничения:** закрыта задача подключения runner и доставки, а не вся поддержка
macOS. Native-файлы/строки в Tracer пока `<unknown>` (символизация №5); поля
native-карточки и расширенные сценарии — №11. Stop/purge/offline/account switch —
№8, до их приёмки пакет экспериментальный. Distribution signing, macOS x86_64,
минимальная ОС, release/runtime iOS не подтверждены. Windows/Аврора остаются
в активном плане. На момент приёмки №4 прогресс №2 ещё не был закрыт;
его самостоятельное завершение зафиксировано [выше](#task-2).

**Позднейшее уточнение конфигурации:** название первого проекта MacOS не означало
тип macOS; пользователь сообщил о вероятном выборе Android. Результат №4 относится
к runner и доказанной доставке через SDK. После создания C/C++-проекта `Test`
повторная live-приёмка ведётся в №5/11; результаты старого проекта на него
автоматически не переносятся.

<a id="task-10-macos"></a>

## П. 10.macOS. Пример, сборка, CI и общие регрессии

**Завершено 23 октября 2026.** Самостоятельная macOS-подзадача исходного №10;
общий пункт №10 продолжает учитывать Windows и Аврору.

**Объём и критерий приёмки:** воспроизводимая release-сборка macOS-примера,
анализ и тесты, реальные loopback/lifecycle-сценарии без рабочих credentials,
сохранение сборки/символов с идентификаторами и регрессии существующих пакетов.

**Результат:** добавлен отдельный
[`macos.yml`](../../.github/workflows/macos.yml): Flutter 3.47.4,
macOS 15 arm64, анализ/тесты адаптера и примера, Swift storage/session tests,
release build, четыре loopback-сценария и 55 lifecycle-шагов. Артефакт содержит
ZIP с исполняемыми файлами и dSYM, SHA-256/UUID, версии инструментов и JSON
проверок; живые ключи не нужны. Те же проверки локально прошли на macOS 27
arm64. [Hosted run 39994869570](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/39994869570)
успешен, включая runtime и загрузку артефакта. Анализ/регрессии семи общих и
существующих платформенных пакетов прошли локально (175 passed, включая отдельный
запуск browser-only fixture в Chrome). [Подробный протокол](../macos-ci-consumer-acceptance.md).
Это не новая live-приёмка Tracer и не подтверждение Intel.

**Реализация и свидетельства:** `cc7fc12` — workflow; `ca23fc2` — код полной
проверки. [CI 40003260512](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40003260512)
завершился успешно, артефакт `macos-arm64-acceptance` сохранён на 14 дней.
[Протокол](../macos-ci-consumer-acceptance.md) содержит результаты и границы.

**Ограничения:** проверены macOS 15/27 arm64; это не приёмка Intel, всех старых
версий macOS или новая live-серия Tracer. Windows/Аврора и общая готовность примеров
остаются в [№10](development_v1.md#task-10), live-приёмка — в №11.

<a id="task-12-macos"></a>

## П. 12.macOS. Внешний потребитель, упаковка и миграция

**Завершено 23 октября 2026.** Самостоятельная macOS-подзадача исходного №12;
общий выпуск всех платформ этим результатом не закрывается.

**Объём и критерий приёмки:** изолированный внешний macOS-потребитель с
опубликованными общими зависимостями без монорепозиторных overrides; release
build и реальное событие через автоматически зарегистрированный адаптер;
проверка состава пакета и staged dry-run, документация установки, перехода,
данных SDK и ограничений lifecycle. Публикация в этот объём не входит.

**Результат:** внешний release-потребитель собран из
изолированного desktop export без overrides. Facade 0.2.1, interface 0.2.0 и
все публичные sibling-пакеты разрешены с pub.dev; одна локальная ошибка с
userId/key/breadcrumb подтверждает автоматическую регистрацию адаптера.
Добавлен воспроизводимый `tool/check_macos_consumer.py` и шаг CI.
Staged publish dry-run допускает только одно задокументированное предупреждение
о точном pin sentry_flutter 9.30.1; публикация не выполнялась, в репозитории
остаётся `publish_to: none`. Обновлены RU/EN README, privacy, publishing и
[миграция](../desktop-migration.md). Это path-consumer, не проверка опубликованной
desktop-версии.
Проверка внешнего consumer также прошла на macOS 15 arm64 hosted runner:
[CI 40003260512](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40003260512),
код `ca23fc2`.

**Реализация:** `0f12b71`; полный hosted workflow проверен на `ca23fc2`.
[Протокол](../macos-ci-consumer-acceptance.md) фиксирует версии зависимостей,
локальные/CI результаты, артефакты и команды повторения. [Publishing guide](../publishing.md)
разделяет подготовку кандидата и фактический выпуск.

**Ограничения:** desktop-пакет остаётся `0.1.0-dev.1`, `publish_to: none`.
Единственное разрешённое предупреждение dry-run относится к намеренному
точному pin SDK; это не результат «без предупреждений». Проверена установка
из изолированной path-копии, не опубликованной desktop-версии. Финальные версии,
общий комплект Windows/Авроры и прочие критерии остаются в
[№12](development_v1.md#task-12); публикация — отдельное действие.

<a id="task-13"></a>

## П. 13. Подключить Ubuntu/Linux

**Завершено 24 октября 2026 для Ubuntu 22.04.5 x86_64 VM.** Реализация и
приёмка выполнены самостоятельно по поручению пользователя. Общая поддержка
всех Linux-дистрибутивов, архитектур и графических окружений не заявляется.

**Результат:** optional desktop-адаптер регистрируется на Linux и использует
официальные Sentry Flutter 9.30.1 / native 0.16.6. Backend `native` отправляет
SDK envelope со стеком и minidump через поддерживаемый Tracer endpoint.
Очередь сохраняется вне установки; consent/stop/clear, restart-required,
отмена собственных uploader и изоляция аккаунтов проверены. До согласия
SDK/очередь/метаданные не запускаются. Пример работает вне checkout на VM
без Flutter, компилятора и Java.

Native-кадры восстанавливаются в crash daemon по точным Breakpad-картам;
Dart AOT — перед SDK-сериализацией по отдельной компактной карте с совпадающим
build ID. В Tracer подтверждены main.dart:45/55/64 и my_application.cc:21,
пользователь/ключи/логи. FlutterError сохраняет имя после обфускации.
Группировка реальных событий даёт 3/1 для двух fingerprint; поиск нового
аккаунта показывает только его Dart/native события. Linux OS/device metadata
передаются после согласия и видны в Other/Context.

**Проверки:** 82 facade, 22 desktop (+2 macOS skip), 1 widget, 22 Python;
14 сценариев чистой VM. На code commit `04569a097380545a7f9a14aeee1e812c207d13c1`
[Ubuntu CI 40093674274](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40093674274)
прошёл все 21 release-сценарий, включая 15-минутный online retry, негативные
карты и локальную символизацию. Общий CI, Windows и оба macOS workflows также
зелёные. Код доступен в [PR #2](https://github.com/KonstantenKomkov/apptracer_flutter/pull/2);
main не изменялась, пакеты не публиковались.

**Артефакты и ограничения:** точные SHA/build ID, восемь live HTTP 200 receipts,
консольные проверки и команды сохранены в [протоколе](../linux-preparation.md).
Компактная Dart-карта раскрывает имена/пути и ослабляет обфускацию; есть opt-out.
Кадры без карт остаются unknown. Tracer C/C++ сохраняет подпись
`Stacktrace not available` при наличии исходных кадров и не заполняет свои
OS/device widgets из этих contexts; Environment filter также не заявлен для
C/C++. Это открытые ограничения сервиса, а не исправленные возможности SDK.
Физический компьютер, Wayland, ARM64, другие дистрибутивы и Аврора не проверены.
Общие №5/8/10/11/12 и публикация остаются за рамками закрытия №13.

<a id="task-11-windows"></a>

## П. 11.Windows. Локальная и live-приёмка

**Завершено 24 октября 2026 в области Windows 11 x64.** Все 24 локальных
release-сценария прошли, включая offline/retry/revoke/in-flight и clear/restart.
Восемь событий серии windows-20261024-165633 приняты существующим C/C++ Test:
handled/FlutterError/async, native access violation, группировка и новая учётная
запись после очистки. В консоли проверены точные Dart/native исходные строки,
поля native/handled, run keys последних FlutterError/async, две группы 3/2 и 1/1.
Account isolation после clear дополнительно проверена по SDK envelopes и
локальному lifecycle. Два external consumer проверили фильтрацию/дедупликацию.

[Протокол](../windows-local-acceptance.md) разделяет live, локальный receiver,
client-side symbolication и ограничения Tracer UI. Crash-free/sessions не заявлены.
Текущий remote CI и чистая Windows 11 x64 VM без toolchain также прошли.
Другие версии/архитектуры
и публикация не выданы за выполненные проверки.
