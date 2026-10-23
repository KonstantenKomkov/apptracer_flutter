# macOS: остановка, очистка и восстановление очереди

Дата: **2026-10-23**. Локальная часть [№8](tasks/development_v1.md#task-8).
Проверено на macOS 27.0.1 arm64, Flutter 3.47.4 / Dart 3.13.3, Xcode 27,
CocoaPods 1.17.0; sentry_flutter/sentry **9.30.1**, Cocoa **8.58.4**.

**Результат:** release-приложение прошло 55 шагов lifecycle и четыре прежних
сценария доставки. Windows/Аврора не проверены; №8 целиком не закрывается.
Локальная проверка использовала синтетические данные и loopback DSN, без чтения
реальных DSN/plugin token. Позже повторная live-проверка в Test подтвердила все
8 новых событий, группировку, native поля и свежий Dart Context — см. ниже.

## Реализация и контракт

Нативная регистрация остаётся инертной. На macOS собственная integration запускает
публичный `SentrySDK.start` с управляемым `cacheDirectoryPath` и `urlSession`.
Официальные SDK продолжают строить envelopes, синхронизировать scope, хранить
очередь и перехватывать native crash. Ручного HTTP/envelope backend не добавлено.
У Windows прежняя integration не изменена.

Session-local `URLProtocol` передаёт SDK-запросы в управляемую ephemeral URLSession.
При stop закрывается допуск новых запросов, отменяются начатые, затем закрывается
Cocoa SDK с `shutdownTimeInterval=0`. Успешный ответ ждёт invalidation сетевой
сессии. Внешняя SDK-сессия остаётся пригодной для создания задач: поздняя задача
получает cancellation без сети. Прямая invalidation этой внешней сессии проверена
и отвергнута: Foundation завершает процесс при создании новой задачи после неё.
Уже переданные серверу байты отозвать нельзя; успешный stop не удаляет серверные данные.

Перед stop сохраняется маркер отзыва. Новый процесс удаляет такую очередь до
native init даже при `preservePreviousReports: true`. При обычном завершении или
crash без stop `true` сохраняет очередь; `false` (default API) удаляет её до init.
Явный stop до первого native init также сохраняет отзыв; deferred bootstrap сам
по себе очереди не трогает и не отправляет.

`stopAndClearCollection` удаляет собственную очередь с crash-файлами, сохранёнными
scope/identity и diagnostic `async.log` Cocoa. На месте каталога очереди оставляет
пустой файл: отложенные writer-задачи не могут восстановить каталог. Проверяются
ошибки файловой системы и symlink-компоненты пути; неуспешная очистка даёт `error`.
Следующий разрешённый процесс удаляет этот файл и создаёт свежую очередь.

| Ситуация | Результат |
| --- | --- |
| Disabled/deferred bootstrap | SDK не запущен, запросов нет |
| Stop/clear до первого native init | `disabled`, отзыв сохранён; последующий явный start возможен |
| Start после успешной инициализации | `enabled`, повторный init не выполняется |
| Stop после попытки native init | `restartRequired` после отмены сети и close |
| Clear после попытки native init | `restartRequired` после удаления данных |
| Повторный start в том же процессе | `restartRequired`; новый адаптер не обходит запрет |
| Ошибка close/clear или timeout | `error`, остающийся видимым при повторных вызовах |
| Другой native SDK / Flutter engine owner | Отказ без закрытия чужого SDK |

Пути в Library определяются Foundation, в sandbox они внутри контейнера:
`Application Support/apptracer_desktop/<bundle-id>/v1/{queue,revoked}`.
При clear от `queue` остаётся нулевой файл, от `revoked` — служебный маркер без
данных пользователя. Cocoa 8.58.4 создаёт `async.log` отдельно в scoped Caches;
удаляется именно этот файл, а не весь каталог Caches.

Старые default cache-каталоги адаптера до этой реализации и отдельного Sentry SDK
не импортируются и автоматически не удаляются. Для обновления приложения с
историческими данными нужна отдельная миграционная очистка владельцем приложения.
Системные crash-логи macOS не удаляются и этим адаптером не импортируются.
Проверен один процесс приложения за раз; одновременная работа нескольких процессов
с общим каталогом не является результатом этой приёмки. Сборка использует CocoaPods;
Swift Package Manager и runtime macOS 12/x86_64 не проверены.

## Воспроизведение

Из `packages/apptracer_flutter_desktop`:

```sh
flutter analyze
flutter test --reporter expanded
swiftc macos/Classes/DesktopStorage.swift macos/Classes/RevocableSession.swift \
  test/native/main.swift -o /tmp/apptracer-native-lifecycle-tests
/tmp/apptracer-native-lifecycle-tests
```

Из `packages/apptracer_flutter_desktop/example`:

```sh
flutter pub get
env -u GEM_HOME -u GEM_PATH flutter build macos --release
flutter analyze
flutter test
```

Из корня репозитория:

```sh
python3 tool/check_macos_lifecycle.py \
  --app packages/apptracer_flutter_desktop/example/build/macos/Build/Products/Release/apptracer_desktop_example.app \
  --output build/macos-acceptance/lifecycle.json
```

Драйвер запускает только отдельные процессы примера и управляет ими через stdin.
Receiver возвращает HTTP 503 для сохранения SDK-очереди либо удерживает ответ,
пока тест вызывает stop. Это управляемая имитация недоступности ingest, не изменение
сетевых настроек компьютера. Приёмочные скрипты запускать последовательно: cache
у этого bundle общий. Проверка намеренно завершает собственные процессы через abort.

## Результаты

Артефакт: `build/macos-acceptance/lifecycle.json` (ignored), run
`199beca0-4d15-40cd-8af3-82c56301456f`: **55 шагов, 8 HTTP-попыток, failures=[]**.
SHA-256 release executable:
`e8ba313b06d0c4a65e8fcf70273f611a127c86162d78f61e3e002edcf58eb441`.
SHA-256 Dart AOT `App.framework/App`:
`845ce0702df7f76ce57711b197dd5f3dfa1aa1436e16a087c4209b8d87cc6479`;
native bridge `apptracer_flutter_desktop.framework/apptracer_flutter_desktop`:
`c40d6d80192153f668b40656652b8cb774fad880c1a2655aae22b1afdb9e2510`.

- Очистка до init, повторные start/stop/clear, отказ повторного старта после stop.
- Offline account A → stop/clear → native crash → новый процесс с preserve=true:
  старых событий нет; свежий отчёт account B не содержит user/key/breadcrumb A.
- Offline → обычное завершение → deferred restart: запросов до start нет;
  preserve=true восстанавливает разрешённый отчёт.
- Тот же restart с default preserve=false удаляет старый отчёт.
- Явный stop до первого init отзывает очередь прежнего процесса; следующий
  preserve=true её не восстанавливает.
- In-flight запрос + второй отчёт в очереди → stop: отмена подтверждена, после
  ответа stop новых HTTP-запросов нет. Crash после stop без clear тоже не попадает
  в следующую сессию; отозванная очередь не восстанавливается.
- Native crash при разрешённом сборе: восстановлен ровно один fatal отчёт после
  следующего явного start; deferred bootstrap его не отправляет.
- После clear проверены нулевой файл очереди, служебный marker и отсутствие async.log.

Повторены старые runtime-сценарии с переносом `.app` в путь с пробелами/кириллицей:
`smoke` — ровно 3 события; `disabled`/`deferred` — 0; `native-crash` — 1 fatal после
restart. Артефакты: `build/macos-acceptance/lifecycle-{scenario}.json`, failures=[].

Анализ адаптера и примера без замечаний; **8 Dart SDK-тестов**, **1 UI-тест** прошли.
Foundation-тесты проверили сохранение/отзыв, повторную очистку, блокировку позднего
writer, отказ на symlink без удаления посторонних файлов, очистку diagnostic log
и позднюю задачу на отозванной сетевой сессии. Ошибки close/clear и отмена старта
дополнительно покрыты Dart-тестами с native channel, а не имитированным SDK.

Отдельное ревью проверило diff, ownership, сериализацию вызовов, ошибки очистки,
позднюю отправку/запись и границы удаляемых файлов. Исправлены гонка invalidated
URLSession, отзыв очереди при prestart stop и неполная очистка отдельного async.log.
Close и purge объединены в одну операцию очереди; тест исключает вклинивание
последующего start между ними до первой native-инициализации.
Депрекационные предупреждения pinned Cocoa API не блокируют release-сборку.

Это локальная проверка lifecycle, а не повторная приёмка Tracer. Серверная native
macOS символизация остаётся [неподдерживаемой в проверенной интеграции](macos-symbols-acceptance.md).
Предоставленная пользователем [документация C/C++](https://apptracer.ru/doc/native-desktop/symbolization/)
описывает уже применённый symupload и minidump-поток; нового способа символизации
наших Cocoa-отчётов она не дала. Дополнительные live-поля/группировка остаются №11;
Windows/Аврора — внешние проверки №3/6–8.

## Повторная live-проверка после изменения lifecycle

23 октября 2026, **19:46:35–19:48:00 МСК**, commit `a373234`.
Использована та же сборка с SHA-256 выше и текущий DSN проекта `Test` из
игнорируемого `.env.tracer`. Секреты не выведены; plugin token не читался и
не передавался приложению. Условия запуска: release, без отладчика, отдельные
процессы; штатные `smoke` и stdin `lifecycle` сценарии примера.

| Серия | Метка probe_run | Выполненные действия |
| --- | --- | --- |
| Dart | `macos-check-aa68494c5c-dart` | Два запуска smoke, по handled/FlutterError/async; userId `desktop-test-user`, breadcrumb `desktop probe started` |
| Native | `macos-check-aa68494c5c-native` | Два SIGABRT с ожидаемым exit -6, каждый с перезапуском и preserve=true; userId/account_marker `desktop-native-test-user`, breadcrumb с тем же текстом |

Перед серией выполнен clear до init (`disabled`), после неё — clear
(`restartRequired`, `macos_cleared_restart_required`). Во всех четырёх 20-секундных
окнах приложение оставалось работоспособным, число оставшихся SDK envelopes — 0.
HTTPS-ответы напрямую не наблюдались; пустая очередь не заменяет подтверждение
карточек в Tracer. Локальный артефакт без секретов:
`build/macos-acceptance/live-lifecycle-recheck.json`; ошибок драйвера нет.

Пользователь прислал список отчётов в **19:47:59 МСК**: четыре группы, release
1.0.0; SIGABRT — FATAL, handled/FlutterError/async — ERROR. Счётчики групп:
native **2** (2 устройства), handled **3**, FlutterError **3**, async **2**
(у Dart-групп по 1 устройству). В заголовках handled/FlutterError видны строки
новой сборки: `_handled:45` / `_runScenario:86`, `_flutterError:55` / `_runScenario:87`.
Таким образом, новые Dart-события видны в консоли и типы представлены ожидаемыми
группами. Общие счётчики могут включать предыдущие запуски: точное сопоставление
восьми новых событий и отсутствие дублей этим снимком не подтверждены.

Пользователь затем подтвердил native-карточку: User ID
`desktop-native-test-user`, `device.arch=arm64`, `os.name=macOS`,
`os.version=27.0.1`, `handled=false`, `mechanism=signal`, release `1.0.0`.
В логах — запись `apptracer` уровня info с текстом
`2026-10-23T16:47:38.842417Z [info] | desktop-native-test-user`.
Она точно соответствует identify перед вторым crash, поэтому сохранение и
доставка native userId/breadcrumb после перезапуска подтверждены для новой сборки.

В этой же карточке пользователь подтвердил custom keys:
`probe_run=macos-check-aa68494c5c-native` и
`account_marker=desktop-native-test-user`. Native Context содержит
`app_start_time=2026-10-23T16:47:17Z`, `app_build=1`, `app_version=1.0.0` и
`app_id=46441EDD-B9D5-3726-A010-E8F61FD93948`; последний сверён через
`dwarfdump --uuid` с arm64 executable проверенной сборки. Доставка native полей
подтверждена именно для повторной серии и новой сборки.

После проверки native полей оставалось сопоставить пары событий по времени,
а не по общему счётчику группы. Эта сверка выполнена ниже через саму консоль.

**FlutterError сверён отдельно:** пользователь прислал обе новые карточки от
**19:46:37** и **19:46:56 МСК**. В обеих — `desktop-test-user`,
`desktop FlutterError probe`, `_runScenario:87` и `_flutterError:55` в `main.dart`.
Тип проекта отображается как **C/C++**. В сводке версия показана как
`1.0.0 (100000000000000)`; это наблюдаемое отображение интерфейса, тогда как SDK
отправляет release `1.0.0`, dist `1`, а native Context подтверждает app_build `1`.
Два новых FlutterError и их читаемые Dart-стеки подтверждены пользователем;
затем все четыре пары независимо сверены через интерфейс Tracer.
Надпись `Stacktrace not available` в списке сохраняется; сама по себе она не
устанавливает наличие или отсутствие стека внутри карточки. Символизация не
перезапускалась и остаётся ранее принятым ограничением.

### Самостоятельная сверка в консоли

По просьбе пользователя агент открыл Test в отдельном окне уже авторизованного
Chrome и прочитал интерфейс через macOS Accessibility. Выполнение JavaScript
из Apple Events оставалось отключённым; cookies/токены браузера не извлекались.
После проверки закрыто только созданное для неё окно.

В каждой из **четырёх групп — ровно три события**: два новых и одно из предыдущего
запуска. Общий счётчик **12**, из них **8 относятся к повторной серии**.
Внутри каждой группы у двух новых событий один group ID, разные event IDs,
ожидаемый userId и следующие времена (МСК, 23 октября 2026):

| Тип | Первое новое событие | Второе новое событие | Предыдущее, не из этой серии |
| --- | --- | --- | --- |
| Handled StateError | 19:46:37 | 19:46:56 | 16:38:57 |
| FlutterError | 19:46:37 | 19:46:56 | 16:38:57 |
| Async StateError | 19:46:37 | 19:46:57 | 16:38:58 |
| Native SIGABRT | 19:47:18 | 19:47:40 | 16:39:19 |

Идентификаторы новых событий из адресов карточек:

| Тип | Event IDs |
| --- | --- |
| Handled | `11f1-cf01-500be5f0-9f35-936c7a8711ec`, `11f1-cf01-5bca0840-b98b-8bb028470b32` |
| FlutterError | `11f1-cf01-502e3b05-9f35-936c7a8711ec`, `11f1-cf01-5be901f3-b98b-8bb028470b32` |
| Async | `11f1-cf01-505460a4-9f35-936c7a8711ec`, `11f1-cf01-5c0cb693-b98b-8bb028470b32` |
| Native | `11f1-cf01-68df5620-9437-99fabfd325b1`, `11f1-cf01-76304d70-b31a-b937c5e462d2` |

У свежего FlutterError от 19:46:56 дополнительно прочитаны:
`probe_run=macos-check-aa68494c5c-dart`; лог `probe | desktop probe started |
level=info | data={source=release-app}`; `contexts.apptracer` с исходным
Dart-стеком (`_flutterError:55`, `_runScenario:87`), `fatal=false`,
`library=desktop acceptance`. Сокращение длинного значения в UI не принято
за проверку полноты всех байтов raw stack.

Итог этой live-серии: **доставка, парная группировка и проверенные поля прошли**;
дублей или потери события среди восьми проб не обнаружено. Снимок от 19:47:59
ещё не отражал окончательные счётчики native/async. Native символизация остаётся
известным ограничением. Это не подтверждение crash-free метрик, всех комбинаций
фильтров/лимитов или runtime Intel/старых macOS; общая №11 остаётся открытой.

Локальные свидетельства: `build/macos-acceptance/console-event-pairs.json`
(12 карточек с group/event IDs), `console-{type}-{latest,previous,old}-ax.txt`,
`console-flutter-{keys,logs,data}-ax.txt`. Эти артефакты ignored; секретов нет.
