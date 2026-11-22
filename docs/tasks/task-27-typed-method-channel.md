# П. 27. Типизированный MethodChannel через Pigeon

**Статус:** выполнена. **Приоритет:** P1. **Сложность:** L.

[Типизированный контракт и совместимость](../architecture.md#связь-dart-с-нативным-кодом),
[генерация](../contributing.md#changing-the-native-contract).

Связанный общий план: [development_v1.md](development_v1.md).
Желательно сначала завершить [№24](task-24-android-event-context.md), чтобы
исправление семантики не смешивалось с миграцией транспорта.

## Контекст

Android и iOS используют общий `MethodChannelTracer`, но контракт поддерживается
вручную: имена методов, строковые ключи, вложенные `Map`, `List` и nullable-поля
синхронно меняются в Dart, Kotlin и Swift. Нативные реализации используют
`call.argument`/`arguments as?` и собственные fallback-значения.

Это повышает риск расхождения версий facade/interface/native adapters. Юнит-тест
одной стороны канала не доказывает совместимость с другой.

Основные места:

- `docs/architecture.md`, раздел «Связь Dart с нативным кодом»;
- `packages/apptracer_flutter_platform_interface/lib/src/method_channel_tracer.dart`;
- `packages/apptracer_flutter_android/android/src/main/kotlin/ru/apptracer/flutter/AppTracerFlutterPlugin.kt`;
- `packages/apptracer_flutter_ios/ios/apptracer_flutter_ios/Sources/apptracer_flutter_ios/AppTracerFlutterPlugin.swift`.

## Цель

Получить единый генерируемый контракт Android/iOS без изменения публичного
`Tracer` API и без ослабления существующих гарантий lifecycle и обработки ошибок.

## Сделать

1. Выписать текущий канал: методы, модели событий/кадров, options, collection и
   diagnostic results, допустимые null и поведение unknown enum/unknown method.
2. Добавить Pigeon как dev-инструмент в подходящий пакет и схему, покрывающую весь
   Android/iOS-контракт. Не добавлять её как runtime-зависимость потребителей.
3. Настроить воспроизводимую генерацию Dart/Kotlin/Swift и проверку в CI, что
   сгенерированные файлы соответствуют схеме. Соблюсти существующие правила
   форматирования и публикации пакетов.
4. Перевести общий Dart adapter и оба native handler на сгенерированные API.
   Сохранить channel naming/версионирование либо описать совместимый переход для
   независимо версионируемых пакетов.
5. Сохранить поведение ошибок: отсутствующий SDK/plugin не падает, lifecycle
   возвращает структурированные state/reason, `appRunner` выполняется ровно один
   раз, stop/clear немедленно запрещает новые Dart-события.
6. Перенести и расширить contract-тесты: все поля `TracerEvent`, Unicode, пустые
   кадры, AOT-адреса, nullable userId, initial/custom keys, diagnostics и все
   collection states.
7. Проверить несовпадение версий в пределах заявленных dependency constraints.
   Неизвестные новые поля/значения не должны приводить к непреднамеренному крашу;
   неподдерживаемая операция должна возвращать понятный результат.
8. Обновить architecture/contributing: схема является источником контракта, ручное
   редактирование generated files запрещено, процесс добавления метода описан.

## Критерии приёмки

- Весь Android/iOS MethodChannel переведён на единую схему; ручные динамические
  map-контракты для этих операций устранены.
- Публичный API `Tracer` и модели платформенного интерфейса не ломаются без
  отдельного major-миграционного решения.
- Существующие Dart/Kotlin/Swift и lifecycle-тесты проходят; добавлены
  двусторонние contract-проверки сериализации.
- Отсутствие SDK, unknown operation и ошибки платформы сохраняют прежнее безопасное
  поведение.
- CI падает при устаревших generated files и при несовместимом изменении схемы.
- Publish archives содержат только необходимые generated/runtime файлы, а схема и
  генератор расположены согласованно с политикой публикации.

## Проверки

- `./tool/check.sh` и Android JVM unit-тесты.
- iOS native storage/plugin tests на macOS.
- Release build Android и iOS example с реальными SDK, затем базовый error/lifecycle
  сценарий на устройстве или принятом эмуляторе.
- Отдельная consumer-проверка совместимых версий пакетов без monorepo overrides.

## Проверка 22.11.2026

- Android, эмулятор API 35 arm64, release/R8, сценарий `event-context`.
  Валидатор `tool/check_android_event_context.py` разобрал два native-отчёта:
  первый содержал результат фильтрации и ключи события, во втором восстановился
  постоянный контекст. После остановки состояние сбора — `disabled`.
- iOS, симулятор iPhone 17 Pro и OKTracer 1.5.2. Установили ключ через
  `TracerNativeApi.setCustomKey`, затем отправили две Dart-ошибки с разными
  `issueKey`. В обоих multipart-отчётах локального приёмника проверены
  нативный ключ, пользователь и breadcrumb из сжатых логов. Одноразовый ключ
  присутствовал только в первом. После `stopAndClearCollection` SDK сообщил
  `restartRequired`. Ошибка, записанная после остановки, не вызвала нового
  запроса за следующие 10 секунд.
- Физический iPhone 16 Pro, iOS 27.2.1, release на Flutter 3.47.4.
  Сценарий `account-b` завершился на устройстве. Локальный приёмник получил
  два отчёта с разными `issueKey`. В каждом проверены нативный ключ,
  идентификатор пользователя и breadcrumb, разовый ключ был только в первом.
  После остановки получено `restartRequired`, сбор выключен. За 10 секунд
  после контрольной ошибки новых запросов не появилось.
- Условие воспроизведения на iOS 27: исходный example из `11402e8`, собранный
  Xcode 27, завершался в UIKit до запуска Dart. В проверочной сборке добавили
  `UIApplicationSceneManifest` с `FlutterSceneDelegate`, а регистрацию плагинов
  и канала примера перенесли в `didInitializeImplicitFlutterEngine`.
  Пакеты адаптера использовались из `11402e8`. Для штатного примера остаётся
  отдельная задача совместимости с Xcode 27 и поддерживаемыми версиями Flutter.
  [Руководство Flutter по UIScene](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).

## Не входит

- Перевод desktop FFI и внутренних Sentry API на Pigeon.
- Изменение HTTP/Sentry wire protocol.
- Одновременный редизайн публичного `Tracer` API.
