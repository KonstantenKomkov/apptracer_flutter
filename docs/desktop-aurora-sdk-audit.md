# Windows, macOS и Аврора: аудит SDK для итерации v1

**Актуализация Windows, 24 октября:** Windows 11 x64, Flutter 3.35.5 / Dart 3.9.2,
VS 2022 17.14/SDK 26100 и официальный Sentry native backend 0.16.6 проверены.
Инструменты/кэши размещены на D. Пользователь явно выбрал существующий C/C++ Test
и локальные Linux credentials для Windows; ingest из relocated release принят,
исходные Dart/native кадры видны в консоли. Stop/clear, revoke/retry и consumer
проверены отдельно. B1/B3/B7 для этой Windows-области закрыты;
Windows-часть B6 заменена клиентскими точными картами. Plugin token для них
не нужен. [Полный протокол](windows-local-acceptance.md).
Следующие исходные формулировки об отсутствии Windows-среды/credentials — история.

Дата: **2026-10-23**. Задача: [№1](tasks/development_v1.md#task-1).
Исходный код проекта: `c2fc225` (`Record verified 0.2.1 publication`).

**Статус: локальная часть исследования выполнена; №1 остаётся открытой.**
Не проверены привязки новых проектов и credentials, Windows toolchain и целевая
среда Авроры. Пользователь уточнил: Windows будет на отдельном компьютере,
Аврора пока недоступна (возможная установка позже). Для Windows подготовлен
[протокол проверки среды](windows-preflight.md); отчёт с компьютера ещё не получен.
Ни одна новая платформа этим документом не объявляется поддержанной.
Последующая работа: [локальный macOS-протокол №2/4](macos-local-acceptance.md)
подтвердил release-сборку и отправку в loopback-приёмник. Далее сохранён срез
**исходного аудита до реализации**; live Tracer и символизация всё ещё не проверены.

**Актуализация Ubuntu, 24 октября:** исходные ограничения Linux ниже заменены
результатами №13: Ubuntu 22.04.5 x64 VM, glibc 2.35, GTK 3, kernel 5.15,
Flutter 3.47.4 / Dart 3.13.3 и Sentry Native 0.16.6 backend `native` приняты.
`TRACER_LINUX_SENTRY_DSN` и `TRACER_LINUX_PLUGIN_TOKEN` проверены для C/C++-проекта;
значения остаются вне репозитория. Dart/native delivery, source frames,
offline/restart/clear и смена аккаунта подтверждены раздельными live/VM/CI
проверками. [Матрица и версии](linux-preparation.md),
[установка внешнего приложения](desktop-migration.md#ubuntu-linux-consumer).
Sessions/crash-free/performance/replay не включены. Это закрывает Ubuntu-объём
№1; открытые Windows/Аврора блокеры не относятся к проверенным Ubuntu credentials.

## Версии и архитектуры

| Компонент | Решение / результат проверки | Что ещё проверить |
| --- | --- | --- |
| Flutter / Dart на машине | `3.47.4` stable / `3.13.3`; framework `9584c6713b`, engine revision `06a2e2a110` | Сборки новых runners в №3–4; это не проверка минимальной версии |
| Основной пакет | Объявлены Dart `^3.5.0`, Flutter `>=3.22.0` | Не повышать ограничения существующих пакетов неявно |
| Официальный desktop SDK, выбранный кандидат | **sentry_flutter 9.30.1**, **sentry 9.30.1**, точные версии; требуют Dart `>=3.5.0 <4.0.0`, Flutter `>=3.24.0` | Проверки адаптера №2 и нативных сборок №3–4 |
| Sentry Cocoa в выбранном пакете | `Sentry/HybridSDK 8.58.4`, CocoaPods; podspec macOS floor `10.14`, iOS `12.0` | Итоговый macOS floor должен также удовлетворять Flutter/Xcode; выбрать на сборке №4 |
| Sentry Native в выбранном пакете | `0.16.6`, CMake FetchContent из `getsentry/sentry-native` | Компиляция и комплект DLL/handler на Windows №3 |
| Sentry 10.x | Не выбран: пакет 10.2.0 сообщает об отказе от CocoaPods начиная с 10.0.0 | Переход существующего iOS-приложения на SPM не входит в подключение desktop |
| macOS host | `27.0.1` (`26A434`), **arm64**; Xcode `27.0` (`27A266a`) | Первый target — arm64; x86_64 требует отдельного запуска, universal-сборка его не доказывает |
| CocoaPods | `1.17.0`; обычный `pod --version` падает на `nkf` из-за смешанных Ruby gem paths | `env -u GEM_HOME -u GEM_PATH pod --version` проходит; применять это окружение в №4, не менять глобальные gems |
| Windows | Исполняемая среда не обнаружена: macOS host, `prlctl list -a` вернул пустой список VM | Windows x64 + Visual Studio с Desktop development with C++, MSVC, Windows SDK, CMake; записать точные версии и `flutter doctor -v` в №3 |
| Windows ARM64 | Не принят в первоначальную матрицу | В исходнике SDK есть отдельный выбор backend; проверка на x64 не подтверждает ARM64 |
| Tracer Native Aurora | **0.1.15**, скачан архив вендора, проверены ZIP, header, CMake и ELF | Условия поставки и runtime/ABI проверить в №6; сторонние бинарники не добавлены в репозиторий |
| Архитектуры поставки Авроры | `aarch64`, `armv7hl`, `x86_64` подтверждены `file` по трём ELF | Приоритет: устройство aarch64 и эмулятор x86_64; ни одна архитектура не проверена запуском; armv7hl не обещается автоматически |
| Aurora SDK / ОС / embedder | Локально `flutter-aurora`, `sfdk`, `aurora-cli` не найдены; версия целевого устройства неизвестна | Нужна совместимая Linux-среда, точные версии SDK/PSDK, ОС, Flutter fork, embedder и `aurora_client_wrapper` перед №6 |

Документация ОМП на дату просмотра показывает Flutter **3.41.4**. Это кандидат
для отдельной среды, а не установленная/проверенная версия. Начиная с 3.35.7 API
embedder вынесен в `aurora_client_wrapper`; нельзя копировать старые прямые вызовы
`aurora_embedder`. Конкретную связку SDK/ОС/engine необходимо закрепить после
получения сборочной среды. Обычный upstream Flutter на этой машине её не заменяет.

Изолированный `flutter pub get` с `sentry_flutter: 9.30.1` на указанном Flutter
прошёл: разрешены `sentry 9.30.1`, `jni 0.14.2`, `package_info_plus 10.2.2`.
Это проверка текущего resolver, не native build и не минимального Flutter 3.24.
Широкое ограничение SDK на `package_info_plus` требует отдельного прогона minimum
SDK в №2/10; lockfile приложения должен закреплять фактически проверенный граф.

## Проекты и конфигурация без секретов

Проект через VK Cloud подключён по исходному плану пользователя. Проверки
привязки к Windows/Авроре пока нет. Позднее в этой сессии пользователь добавил macOS
DSN и подтвердил три Dart-события снимком Tracer; см.
[протокол](macos-local-acceptance.md). Значения `.env.tracer` не выводились.

**Уточнение 23 октября:** MacOS было названием первого проекта; пользователь
сообщил, что, вероятно, при создании выбрал Android. После открытия расширенного
списка платформ ему указан C/C++; создан проект `Test`, оба macOS credentials
заменены. Первые live-результаты не подтверждают приёмку нового C/C++-проекта.
Повторная проверка — в [протоколе символов](macos-symbols-acceptance.md).

| Назначение | Имя переменной | Наличие / требуемая проверка |
| --- | --- | --- |
| Windows ingest | `TRACER_WINDOWS_SENTRY_DSN` | Отсутствует; получить из API нужного проекта, сопоставить проект в консоли |
| macOS ingest | `TRACER_MACOS_SENTRY_DSN` | Заменён для C/C++-проекта Test; пользователь подтвердил native SIGABRT, Dart-приёмка Test ещё ожидается. Подтверждения первого проекта сохранены в протоколе |
| Windows symbols | `TRACER_WINDOWS_PLUGIN_TOKEN` | Отсутствует; подтвердить принадлежность проекту Windows |
| macOS symbols | `TRACER_MACOS_PLUGIN_TOKEN` | Заменён для Test; 12 модулей загружены, но строки не появились. Apple upload отклонён с подтверждением типа DESKTOP; [диагностика](macos-symbols-acceptance.md) |
| Aurora ingest | `TRACER_AURORA_APP_TOKEN` | Отсутствует; нужен проект **C/C++** |
| Aurora symbols | `TRACER_AURORA_PLUGIN_TOKEN` | Отсутствует; отдельный plugin token того же C/C++ проекта |
| Существующие платформы | `TRACER_APP_TOKEN`, `TRACER_PLUGIN_TOKEN`, `TRACER_IOS_APP_TOKEN`, `TRACER_IOS_PLUGIN_TOKEN`, `TRACER_JS_APP_TOKEN`, `TRACER_JS_PLUGIN_TOKEN` | Есть непустые значения; не считать их доступом к новым проектам |
| Метаданные будущего примера | `TRACER_RELEASE`, `TRACER_ENVIRONMENT`, `TRACER_DIST` | Имена для №2/10; передаются в существующие `TracerOptions.release/environment/dist` |

Имена — контракт конфигурации; desktop example уже читает `TRACER_MACOS_SENTRY_DSN`.
Остальные новые имена не означают реализованные команды для всех платформ.
Desktop передаёт выбранный DSN в `TracerOptions.dsn`; app token не является DSN.
Plugin token используют только инструменты символизации, не Dart defines приложения.
DSN Windows/macOS могут совпадать только после явного подтверждения привязки проекта.
Пустая/неверная конфигурация должна оставлять SDK выключенным. Наличие строки DSN
и успешный HTTP-ответ не подтверждают отображение события в нужном проекте.

## Матрица возможностей

«Исходник» означает наличие API в закреплённой поставке, а не приёмку в Tracer.
**Обновление:** macOS runtime проверен локально; пользователь подтвердил три
Dart-события и стеки карточек в Tracer. В FlutterError подтверждены userId, ключ
запуска, Context и breadcrumb. Пользователь подтвердил native SIGABRT в Tracer;
символизация, расширенная приёмка и другие платформы остаются непроверенными.
Подробности — в [протоколе macOS](macos-local-acceptance.md).

| Возможность | Windows/macOS, официальный Sentry SDK | Аврора, Tracer 0.1.15 | Проверка в плане |
| --- | --- | --- | --- |
| Dart handled/Flutter/async error | `captureEvent`/`captureException`, исходный Dart stack; владельцем перехватчиков остаётся Tracer | Нет API передачи Dart type/message/stack; non-fatal dump API не решает эту задачу | №2–4, №7, №11: разные типы, fatal, исходный стек, ровно одно событие |
| Native crash | Sentry Native / Cocoa; формат приёмника проверяется отдельно | Системный `crash-dumper`, импорт предыдущего dump перед init | №3–4, №6, №11: падение без отладчика, повторный разрешённый запуск |
| Логи / breadcrumbs | SDK Breadcrumb; Tracer документирует отображение в логах | `tracer_log`, строковые записи, не структурированные breadcrumbs | №2, №7, №11: порядок, Unicode, лимиты, фильтр и отсутствие дублей |
| Ключи | Scope tags/context/extra, removal API | `tracer_set_key`; публичного remove нет | №2, №7, №11: добавить/заменить/удалить и проверить следующий отчёт |
| Пользователь | Scope user, сброс `null` | `tracer_set_userid` требует non-null строку; семантика пустой строки не доказана | №7–8, №11: смена и удаление userId |
| Offline | Нативная очередь SDK; структура/границы очистки требуют проверки | Persistent session storage + явный upload | №8, №11: offline → stop/clear → online/restart |
| Stop | SDK close доступен; close сам по себе не доказывает purge или отмену сети | `tracer_disable_upload` не является остановкой SDK | №8: незавершённый start/upload, crash после stop |
| Очистка | Не считать очистку Scope удалением native cache/crash files | Нет публичного purge/shutdown; системные dumps лежат вне storage SDK | №8: account switch, перезапуск и файлы запрещённого периода |
| Символы | PDB/DWARF и Dart AOT — отдельные каналы/результаты | ELF build-id, symupload до strip; Dart AOT отдельно | №5, №9, №11: точные модули, чужие символы, читаемые кадры приложения |

Sessions, crash-free, performance, profiling, replay, автоматические logs/metrics
не включать. У выбранного Sentry SDK часть автоматических интеграций включается
по умолчанию; в №2 нужна явная конфигурация и тест фактического набора integrations.
`beforeSend` в Dart не гарантирует фильтрацию native crash при завершении процесса.
Фильтрацию native данных и запрет отправки после отзыва нужно проверять отдельно.

## Проверка поставки Авроры

Источник: [архив 0.1.15](https://nexus-external.vkteam.ru/repository/raw-tracer-native-public/aurora/tracer-native-aurora-0.1.15.zip),
ссылка из [quick start](https://apptracer.ru/doc/native-aurora/quick-start/).
ZIP integrity: успешно. SHA-256 архива:

```text
b65040d76d0aa2d882a91699700a36160ef327c8eeece2616c1db0897ada9669
```

SHA-256 `include/tracer.h`:

```text
bf910544edc6050e6aeb99b36fdfc8801e470977c7a3c047ba13b02addfba8b7
```

Это зафиксированные локально хеши загруженной поставки, не подпись вендора.
Архив называется 0.1.15, но верхняя запись `changelog.md` — `0.1.15-rc7`;
для воспроизводимости использовать URL **и** хеш.

Полный `tracer.h` прочитан, включая комментарии к API:

- `tracer_init` возвращает `void`; нет явного результата успешной инициализации.
  Он создаёт storage/session и блокировки. `tracer_set_platform_info2` обязателен:
  сессии без информации о версии не загружаются.
- `tracer_aurora_collect_minidump_from_cachedir` копирует системный dump и должен
  вызываться **до** init. Оба действия подчинить разрешению сбора. Сам crash handler
  SDK на Авроре ничего не устанавливает.
- `tracer_upload` работает синхронно; `tracer_upload_async` запускает detached
  thread. У последнего нет handle отмены/join в публичном header — не использовать
  его как основу доказуемой остановки. `tracer_upload_crashes` — deprecated alias.
- `tracer_disable_upload` запрещает upload и позволяет upload удалять обработанные
  сессии. Это не обещание остановить logger, закрыть SDK или стереть системные dumps.
  Публичного обратного enable, shutdown или purge в header нет.
- `tracer_set_key` и `tracer_set_userid` принимают non-null UTF-8. Публичных remove,
  clear keys, reset user нет. Не передавать `nullptr` и не объявлять `""` удалением
  без подтверждения. `tracer_log` пишет асинхронно в logger thread.
- `tracer_supports_arbitrary_dump` документирован только для Crashpad;
  `tracer_report_nonfatal_from_here` работает только при положительном результате.
  Он не принимает Dart exception/stack. Нужен ответ вендора или новая поставка для
  полноценного `recordError` на Авроре; искусственный crash и лог не являются заменой.
- В CMake whitelist архитектур — `x86_64 arm64 universal auto`, но библиотеки
  Авроры лежат в `aarch64/armv7hl/x86_64`. Нельзя подключить ARM-поставку простым
  `TRACERNATIVE_ARCH=aarch64`; в №6 нужен собственный imported target и явная ABI map.
- В архиве нет общей лицензии SDK (есть лицензия стороннего symbolstore).
  Не вендорить бинарники; условия получения и распространения установить в №6.

| ELF | Build-id из `file` |
| --- | --- |
| aarch64 | `cccc68dd0127cd85200d275f452695760db925f7` |
| armv7hl | `ba9bb328dc9005a2057ae57d51dfdcc96bfade24` |
| x86_64 | `e042969e26fd3af53e4bfc2cce0b7c4f87d873e5` |

Эти идентификаторы относятся к библиотекам вендора, не к будущему runner или RPM.

Проверен также [демо-проект ОМП Crasher](https://gitlab.com/omprussia/demos/Crasher/-/tree/3039a968f4f3d209325036b8ab7d6b0d68898c90),
commit `3039a968f4f3d209325036b8ab7d6b0d68898c90`, ветка `example`:
`src/utils/tracer_helper.cpp`, `src/main.cpp`, `rpm/ru.auroraos.Crasher.spec`.
Это Qt/QML, не Flutter. В helper init и import dump разделены; порядок будущего
плагина должен следовать требованию header «import до init». Пример печатает
app token и содержит token defines в spec — эти решения не переносить.
Spec отключает пересчёт build-id и вызывает symupload после install; фактическое
совпадение ID установленного RPM проверяется отдельно в №9.

## Схема пакетов и регистрация

Предлагаемая граница для №2–4:

```text
apptracer_flutter → существующие Android / iOS OKTracer / Web
desktop consumer → apptracer_flutter + apptracer_flutter_desktop
apptracer_flutter_desktop → platform_interface + sentry_flutter 9.30.1
Aurora consumer → apptracer_flutter + apptracer_flutter_aurora
apptracer_flutter_aurora → platform_interface + MethodChannel + Tracer Native
```

1. Новый **опциональный** desktop пакет, floor Flutter 3.24, точный SDK pin.
   Не добавлять Sentry в зависимости основного пакета до регрессионных сборок.
   На этапе №2 явная установка `TracerPlatform.instance`; в №3–4 регистрация
   `dartPluginClass` первоначально только windows/macos. После №13 добавлены
   Linux `dartPluginClass` и FFI CMake hook; это регистрация Ubuntu backend,
   а не нативного Tracer SDK Авроры.
2. `sentry_flutter` сам является многоплатформенным плагином: установка optional
   пакета в общее приложение всё равно добавит его iOS/Android native dependencies.
   Условный Dart import их не убирает. Для изоляции использовать отдельный desktop
   example/entry dependency graph; существующий mobile/web example сохраняет граф.
   В №4 дополнительно собрать iOS-потребитель с optional зависимостью и проверить
   OKTracer; до этого совместимость такого общего графа не обещать.
3. Apple plugin registration выбранного SDK создаёт MethodChannel; SDK запускается
   в `initNativeSdk`, не в `register`. Это статическая проверка, а не доказательство
   отсутствия runtime побочных эффектов. На сторонних платформах адаптер не вызывает
   `SentryFlutter.init` и не подменяет существующий backend.
4. `Tracer.initialize` остаётся единственным владельцем appRunner/зоны/перехватчиков
   и пользовательских фильтров. Не передавать appRunner в Sentry. Удалить лишние
   Dart/Flutter error integrations из SDK, сохранив необходимые native transport,
   symbol/debug-image integrations. Проверить конкретный список в №2.
5. Существующий `apptracer_flutter_sentry` — legacy manual envelope transport,
   `publish_to: none`. Не менять его незаметно для git-потребителей: описать переход
   на новый пакет в №2/12; никогда не активировать оба транспорта одновременно.
6. Аврора — отдельный пакет с metadata/template совместимого Flutter fork и
   регистрацией MethodChannel. Upstream `TargetPlatform.linux` не отличает Аврору;
   включение Aurora backend по одному признаку Linux запрещено. Не добавлять неизвестный upstream платформенный
   ключ в основной pubspec до проверки tooling/упаковки в №6/12.

Ограничения lifecycle — часть архитектуры, а не последняя косметическая проверка.
До №8 не выдавать `disabled` за доказанный native stop/clear; отсутствие purge API
должно приводить к честному `unsupported`/`restartRequired` по фактическому результату.

## Внешние блокеры и конкретные проверки

| ID | Блокер | Как закрыть / задачи |
| --- | --- | --- |
| B1 | Windows DSN/проект не подтверждён; macOS DSN, три Dart-события, стеки, userId, ключ запуска, Context и breadcrumb подтверждены | Без публикации значений предоставить локальную конфигурацию; сверить проекты в консоли, №1; Dart/native события и поля №3–5/11 |
| B2 | Нет проверенного C/C++ проекта Авроры, app/plugin tokens | Установить привязку в консоли №1; ingest №6–7/11, symbols №9 |
| B3 | Windows планируется на отдельном компьютере; версии и доступ пока не подтверждены | Выполнить [preflight](windows-preflight.md), записать версии VS/MSVC/SDK/CMake; затем проверить запуск и пути №3 |
| B4 | Пользователь подтвердил отсутствие среды Авроры; установка возможна позже | После появления Linux runner и устройства/эмулятора закрепить версии №1, собрать/установить RPM №6 |
| B5 | API Aurora 0.1.15 не покрывает Dart error, удаление данных, остановку | Получить подтверждённые API/новую поставку или согласованное ограничение; №7–8 остаются блокерами поддержки, без HTTP fallback |
| B6 | Native macOS символизация принята как неподдерживаемая возможность проверенной интеграции; доставка SIGABRT работает. Windows ingest не подтверждён | По решению пользователя ответ Tracer не ожидается, повторных macOS symbol-проб без новых данных не выполнять. Продолжить остальные проверки №3–5/11 с указанным ограничением |
| B7 | Windows native upload/purge не проверены; macOS arm64 локальная часть прошла, возобновление требует нового процесса | [macOS протокол №8](macos-lifecycle-acceptance.md): 55 шагов, offline/in-flight/restart/account switch и файлы; Windows проверить отдельно |

№1 не переносится в архив до проверки недостающих конфигураций и фиксации целевых
сред. По уточнению пользователя 2026-10-23 отсутствие Windows/Авроры и DSN не
блокирует независимую реализацию и локальные сборки на macOS: №2/4 выполняются,
а внешние проверки остаются открытыми. Последующие задачи не закрываются
unit-тестами вместо обязательной live-приёмки.

## Воспроизведение и источники

Проверки и отдельное ревью diff 2026-10-23:

- Проверены версии SDK по архивам, pub-хеши, целостность Aurora ZIP и ELF-архитектуры;
  изолированный `flutter pub get` прошёл.
- При ревью учтено, что optional пакет с `sentry_flutter` всё равно приносит native
  зависимости в общий consumer; добавлены изоляция примера и отдельная iOS-проверка.
- Проверены локальные ссылки, сохранение всех номеров №1–12, отсутствие значений
  локальных токенов в staged diff; `git diff --cached --check` прошёл.
- Изменены только документы. Тесты runtime не запускались; результаты старых
  платформ не используются как доказательство работоспособности новых.

Локальные команды исследования (не отправляют тестовые события):

```sh
flutter --version
sw_vers
uname -sm
xcodebuild -version
env -u GEM_HOME -u GEM_PATH pod --version
command -v flutter-aurora sfdk aurora-cli
prlctl list -a
# В отдельном временном package с зависимостью sentry_flutter: 9.30.1:
flutter pub get
# После загрузки архивов по ссылкам ниже:
shasum -a 256 sentry_flutter-9.30.1.tar.gz sentry-9.30.1.tar.gz
shasum -a 256 tracer-native-aurora-0.1.15.zip
unzip -p tracer-native-aurora-0.1.15.zip include/tracer.h
unzip -p tracer-native-aurora-0.1.15.zip CMakeLists.txt
file aurora/lib/*/libtracernative.so
```

SHA-256 официальных pub-архивов сверены с `archive_sha256` Pub API:

```text
sentry_flutter 9.30.1 bdd8897b38ce31185c42ed910628059c4eccbc0b0641213e8d1c63e2fda3f5a3
sentry         9.30.1 40a247686af64e497df29ab0de1303a20ca55a2e3c7c7e39b989fac47dcadf84
```

- [Sentry Flutter 9.30.1, метаданные/хеш](https://pub.dev/api/packages/sentry_flutter/versions/9.30.1),
  [архив](https://pub.dev/api/archives/sentry_flutter-9.30.1.tar.gz): проверены
  `pubspec.yaml`, Apple podspecs/plugin registration, Windows CMake,
  `sentry-native/CMakeCache.txt`, `sentry_flutter.dart`, options.
- [Sentry Dart 9.30.1](https://pub.dev/api/packages/sentry/versions/9.30.1),
  [архив](https://pub.dev/api/archives/sentry-9.30.1.tar.gz): options и integrations API.
- [Sentry Flutter, переход 10.x на SPM](https://pub.dev/packages/sentry_flutter).
- [Tracer: Sentry DSN, breadcrumbs/context](https://apptracer.ru/doc/other-platforms/quick-start/).
- [Tracer: Аврора](https://apptracer.ru/doc/native-aurora/quick-start/),
  [символизация desktop](https://apptracer.ru/doc/native-desktop/symbolization/),
  [символизация Авроры](https://apptracer.ru/doc/native-aurora/symbolization/).
- [ОМП: начало разработки](https://developer.auroraos.ru/doc/extended/flutter/flutter_development),
  [компоненты среды](https://developer.auroraos.ru/doc/extended/flutter/about_flutter/platform),
  [миграция embedder API](https://developer.auroraos.ru/doc/extended/flutter/migration_guide/3.32.7_to_3.35.7),
  [шаблон Platform Channels](https://developer.auroraos.ru/doc/extended/flutter/plugins_development/platform_channels).
