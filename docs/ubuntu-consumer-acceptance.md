# Ubuntu: внешний потребитель и подготовка выпуска

Дата: **24 октября 2026**. Дополнение к [платформенной приёмке №13](linux-preparation.md)
закрывает Ubuntu-части №1/11/12. Рабочая база — `c8572c2` с текущими изменениями;
в отчётах явно записаны `source_dirty:true` и SHA-256 экспортированных файлов.
Пакеты не опубликованы; версия facade 0.2.2 проверяется в изолированной копии.

## Что проверено

[`tool/check_linux_consumer.py`](../tool/check_linux_consumer.py) экспортирует
исходники пакетов вне checkout без `pubspec_overrides.yaml`, создаёт новое
Flutter-приложение стандартной командой `flutter create --platforms=linux`,
применяет документированные настройки CMake и собирает обфусцированный release.
Это новый потребитель с другим executable, а не копия готового example runner.
Сборочная среда: Ubuntu 22.04 WSL2, Flutter 3.47.4 / Dart 3.13.3, Clang/LLVM 14,
CMake 3.22, OpenJDK 17 для транзитивной JNI build dependency.

Проверены два графа без overrides:

| Режим | Desktop | Facade | Остальные пакеты |
| --- | --- | --- | --- |
| Hosted baseline | изолированный path, 0.1.0-dev.1 | pub.dev 0.2.1 | pub.dev: interface/HTTP/iOS/Web 0.2.0, Android 0.2.1 |
| Кандидат | изолированный path, 0.1.0-dev.1 | изолированный path, staged 0.2.2 | те же hosted siblings |

`dart pub publish --dry-run` desktop проходит с **одним ожидаемым предупреждением**
о точном pin `sentry_flutter: 9.30.1`; прочие предупреждения/ошибки проверка
отклоняет. Staged facade 0.2.2 имеет **0 предупреждений**. В staged копии
изменены только версия и заголовок changelog; исходное исправление `FlutterError`
уже содержалось в рабочем facade. Автоматической публикации нет.

Release-приложение переносится в путь с пробелами/кириллицей и отправляет
события в локальный HTTP-приёмник через официальный native SDK. Подтверждены:

- автоматическая регистрация и ровно один вызов `appRunner`;
- ровно три итоговых события: редактированное, с исходным Dart-кадром и FlutterError;
- повторная запись одного error/stack не создаёт дубликат;
- отброшенные событие/breadcrumb, сообщение и custom key не возвращаются из Scope;
- удалённый фильтром стек не восстанавливается из карты символов;
- исходные строки внешнего `main.dart` по карте именно этой сборки, userId и breadcrumb;
- отсутствие дополнительных session/metric/trace envelope items;
- stop/clear возвращает `restartRequired`, запись после stop не отправляется.

В hosted 0.2.1 имя FlutterError в данной обфусцированной сборке — **`MB`**;
в staged 0.2.2 — **`FlutterError`**. Это подтверждённая причина включить facade
0.2.2 в комплект выпуска для полного Ubuntu-поведения, принятого в №13.
Источник строк восстанавливается в обоих режимах независимо от названия типа.

## Чистая Ubuntu VM

Оба готовых bundle отдельно перенесены на Ubuntu **22.04.5 x86_64** QEMU/KVM,
kernel `5.15.0-198-generic`, glibc 2.35, X11/Xvfb. На гостевой системе нет
`flutter`, `dart`, `gcc`, `clang`, `java`, `cmake`, `ninja` — проверено до запуска.
`ldd` runner, всех `.so` и crash-handler не содержит `not found`. Повторная
runtime-проверка обоих графов успешна: три события, фильтрация/дедупликация,
исходные строки, clear и соответствующее имя FlutterError. Живые credentials
не используются; это внешняя установка/runtime-приёмка, не новая live-серия Tracer.

| Bundle | SHA-256 |
| --- | --- |
| Hosted facade 0.2.1 | `99b11f8fc8cf54e955b4cb0d966a830b090cd25874db69d6c89c535fa3644c9b` |
| Staged facade 0.2.2 | `c23b072363318f8c6af409085d476e2a290d68320dbd0a0a54221e1c938daa70` |

Локальные артефакты: `build/ubuntu-consumer-hosted-retry/` и
`build/ubuntu-consumer-candidate/`. В каждом есть `report.json`, dependency
lockfile, export manifest, dry-run/build/ldd logs, symbols, `consumer-bundle.tar.gz`
и `vm/reports/` с результатом и средой гостевой ОС. Каждый SHA относится только
к своему артефакту; следующие сборки могут иметь другие build IDs.

Проверенное значение plugin token из локальной конфигурации сравнивалось с
содержимым обоих bundle и экспортируемыми исходниками: **360 файлов, 0 совпадений**.
Значение не выводилось. `secret-scan.json` сохранён в каталоге candidate;
`.env` и monorepo overrides в bundle отсутствуют. Сборка получала только dummy
loopback DSN; symbol tools не требуют upload token.

Итоговый повтор с анализом и тестами самих изолированных пакетов сохранён в
`build/ubuntu-consumer-release-check/`: **22 desktop-теста** (2 macOS-only skip),
**82 facade-теста**, analyze обоих пакетов и потребителя без замечаний, оба
dry-run и release runtime успешны. Его bundle SHA-256:
`61b89223fdddd9837799bf30a7e1fd6fdb0363b6c754713f8bd7d29b04bcd116`.
Этот bundle также прошёл повторный запуск на чистой VM с `FlutterError` и
теми же проверками; дополнительный token scan — **238 файлов, 0 совпадений**.
22 host Python-теста прошли, YAML workflow и локальные ссылки проверены.

Первый build был прерван сбоем DNS WSL при clone submodules Sentry; это не
успешная проверка и он сохранён отдельно в `build/ubuntu-consumer-hosted/`.
После временной настройки DNS оба графа собраны успешно. Исходный DNS возвращён
побайтно; VM штатно выключена, диски и отчёты сохранены. Компилятор Clang 14
выдаёт предупреждения о неизвестной warning group в upstream Sentry Native;
они не являются предупреждениями Pub и не препятствуют сборке.

## Воспроизведение и границы

Команды и обязательные изменения CMake приведены в
[руководстве внешнего потребителя](desktop-migration.md#ubuntu-linux-consumer).
Ключевые требования: bundle install prefix до подключения плагинов, исключение
неиспользуемой JNI-библиотеки, установка `sentry-crash` с правами исполнения,
DWARF до генерации карт и доставка всего bundle.

В [`linux.yml`](../.github/workflows/linux.yml) добавлен отдельный consumer job
с обоими режимами и сохранением артефактов. Его команды проверены локально;
новый hosted job в этом изменении ещё не запускался. Ранее успешный CI с 21
сценарием и live-серия №13 остаются отдельными результатами.

Обновлены RU/EN README, status, матрица, аудит, symbolication, privacy и порядок
публикации. Для Ubuntu не заявляются crash-free, sessions, performance или replay;
unhandled Dart/fatal не означает завершение процесса. Native SIGSEGV подтверждён
отдельной пробой №13. Dart-фильтры не ограничивают native minidump. Ограничения
серверных виджетов/подписи стека, Wayland/ARM64/других дистрибутивов сохраняются.

Следующий выпуск: facade **0.2.2**, затем desktop **0.1.0-dev.1**. Финальный
release commit и публикация — отдельные действия; после публикации нужен
hosted desktop consumer. Текущая приёмка не выдаётся за уже опубликованный пакет.
