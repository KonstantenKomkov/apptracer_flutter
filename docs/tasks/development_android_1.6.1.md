# Обновление Android до Tracer SDK 1.6.1

План от 10 ноября 2026. Цель — обновить Android-интеграцию apptracer_flutter,
использовать Maven Central и проверить изменения runtime и Gradle-плагина.
Android №13–21 завершены в принятых границах; №22 открыт. Kotlin file/line
в консоли Tracer остаётся отдельным внешним ограничением выпуска. Номера исходного плана сохранены;
общий №13 уже занят Ubuntu, поэтому архив Android использует отдельные якоря.
Связь с [общим бэклогом](development_v1.md).
Завершённые пункты переносить в [общий архив](development_completed_v1.md),
сохраняя номера, результаты проверок и ссылки.

## Основание и текущая интеграция

Основание — предоставленный пользователем анонс SDK 1.6.1 и дополнение о
публикации в Maven Central. Повторы и повреждённые фрагменты анонса исключены.
Релиз заявляет `Tracer.enable`, изменение ограничений воркеров `runNow`,
`HeapDumpsConfiguration.Builder.provideEnabled`, изменение генерации `buildUuid`,
исправления configuration cache и обработки mappings в
`AnalyticsEnabledApplicationVariant`.

- Android-пакет компилируется и тестируется с SDK 1.5.2; пример использует BOM
  и Gradle-плагин 1.5.2. SDK подключает приложение через `compileOnly` в плагине.
- Репозиторий VK прописан в Android-пакете и в обоих контурах разрешения
  зависимостей примера: `pluginManagement` и обычные repositories.
- `Sdk140ConsentRuntime` принимает только 1.4.0 и 1.5.2. Остановка управляемого
  SDK отзывает исполнители, удаляет данные, отключает native writer и watchdog;
  повторный старт после такой остановки требует перезапуска процесса.
- В общем Dart API уже есть `startCollection`, `stopCollection` и состояния
  `enabled`, `disabled`, `restartRequired`, `unsupported`, `error`.
  Методы HeapDumps/DiskUsage в нём отсутствуют; эти модули пример не подключает.
- В `app/tracer.gradle` сейчас указано `uploadMapping = true` и обязательны оба
  токена. Название `uploadMappings` из анонса нужно сверить с DSL версии 1.6.1.

Контекст: [аудит 1.5.2](../android-sdk-1.5.2.md),
[контракт управления сбором](../native-collection-consent.md),
[символизация](../symbolication.md).

## Бэклог

P0 — условие безопасного обновления; P1 — проверка возможностей и подготовка
выпуска. Сложность: S — небольшая, M — средняя, L — крупная.

| № | Задача | Приоритет | Сложность | Зависимости |
| --- | --- | --- | --- | --- |
| 22 | [Документация и подготовка выпуска](#task-22) | P1 | M | №21 принят с ограничением |

Завершён [аудит Android №13](development_completed_v1.md#task-android-13).
[Зависимости и Maven Central №14](development_completed_v1.md#task-android-14)
также проверены и завершены.
[Повторное включение №15](development_completed_v1.md#task-android-15)
проверено на release/R8 API 35.
[Опциональные runNow №16](development_completed_v1.md#task-android-16)
проверены с явными ограничениями VM-пауз и offline-доставки.
[Ленивый HeapDumps provider №17](development_completed_v1.md#task-android-17)
проверен JVM-тестами и release/R8 на API 35.
[Mappings/buildUuid №18](development_completed_v1.md#task-android-18)
проверены матрицей чистых сборок.
[AnalyticsEnabledApplicationVariant №20](development_completed_v1.md#task-android-20)
воспроизведён с двумя flavor на AGP 8.9.1.
[Configuration cache №19](development_completed_v1.md#task-android-19)
проверен в предусмотренном native fallback; полный Flutter build блокер открыт ниже.
[Результаты и ограничения](../android-sdk-1.6.1.md).

Следующая задача: **22**. [№21 принят с известным ограничением](development_completed_v1.md#task-android-21);
исправление Kotlin-символизации отслеживается отдельно ниже и не блокирует выпуск.
Сборочная ветка №18/20/19 может выполняться независимо от runtime-ветки
№15–17 после №14. Windows, macOS и Аврора не блокируют этот план.

## Общие правила

1. Сохранить федеративную архитектуру и подключение SDK приложением. Не включать
   дополнительные диагностические модули по умолчанию ради обновления версии.
2. Сначала использовать существующий Dart lifecycle API. Расширение публичного
   API HeapDumps/DiskUsage требует отдельного решения после проверки нативного API.
3. Build-time disable, отсутствие SDK, deferred-старт и runtime disable — разные
   состояния. `Tracer.enable` не инициализирует SDK, отключённый при сборке.
4. Возобновление через `enable` само по себе не доказывает возможность повторного
   старта после полной очистки. Сохранять `restartRequired`, где это необходимо.
5. Для каждой задачи провести ревью и записать применимые проверки. Разделять
   компиляцию, JVM-тесты, runtime, доставку и символизацию в Tracer.
6. CI-проверки сборки выполнять без живой загрузки mappings/символов. Live-приёмка
   использует отдельную конфигурацию; секреты не включать в отчёты и артефакты.

<a id="task-21"></a>

## П. 21. Принятая сквозная приёмка

[Результат и принятые ограничения перенесены в архив](development_completed_v1.md#task-android-21).
Решение от 13 ноября 2026 разрешает подготовку и выпуск с известным дефектом
Kotlin file/line. Результат проверки консоли не изменён на успешный.

<a id="blocker-kotlin-symbolication"></a>

## Открытое ограничение: Kotlin file/line в консоли Tracer

**Внешний дефект, не блокирует выпуск по решению от 13 ноября 2026.**
Точная minified-сборка доставляет Kotlin crash с восстановленными классом и
методом, но консоль показывает `KotlinCrashProbe.java:14` вместо
`KotlinCrashProbe.kt:6`. Локальный Retrace 8.9.32 с тем же загруженным mapping
восстанавливает правильные файл и строку. Подмена mapping/UUID исключена.

Временный путь диагностики: сохранять полный `mapping.txt` точной сборки и
обрабатывать исходный обфусцированный стек локальным Retrace.
[Протокол](../android-sdk-1.6.1-acceptance.md#открытый-дефект-kotlin-символизации)
и [минимальный reproducer](../../tool/fixtures/android-sdk161/kotlin-symbolication/README.md).

**Условие закрытия дефекта:** после исправления Tracer повторно проверить
существующий отчёт или новую точную minified-сборку: консоль должна показывать
исходные `.kt:6` вместе с восстановленными классом и методом. До этого не
заявлять полную Kotlin-символизацию и сохранять ограничение в RU/EN README
и changelog выпуска. Дефект не считается исправленным принятием №21.

<a id="task-22"></a>

## П. 22. Документация и подготовка выпуска

**Сделать.** Обновить RU/EN README основного и Android-пакетов, пример,
`docs/status.md`, `docs/platform-matrix.md`, lifecycle и symbolication по
результатам приёмки. Описать Maven Central, версии BOM/плагина, runtime enable,
неизменность build-time disable, runNow, provideEnabled и флаги загрузки.
Исторический аудит 1.5.2 сохранить как протокол прежней версии.

Подготовить версии/changelog изменённых пакетов, команды миграции, порядок
выпуска и publication dry-run. Проверить внешний Flutter consumer без локальных
overrides: зависимости берутся из заявленных репозиториев, а инструкции не
требуют VK для 1.6.1. Проверить состав пакетов и отсутствие секретов.

**Приёмка.** Подготовлен комплект выпуска с проверенной установкой и точной
матрицей возможностей/ограничений. Публикация пакетов — отдельное действие;
её результат не подменяется dry-run. Все заявленные возможности подтверждены
№21, оставшиеся ограничения явно отражены в документации.

<a id="blocker-flutter-configuration-cache"></a>

## Открытый блокер: configuration cache полного Flutter assemble

На Flutter 3.47.4 / AGP 8.9.1 / Gradle 8.12 / JDK 21 `assembleRelease` с SDK
и без SDK не сохраняет configuration cache: действие FlutterPlugin захватывает
legacy ApkVariantOutputImpl и несериализуемый граф Project/configurations.
[Протокол №19](../android-sdk-1.6.1-gradle.md#configuration-cache-android-19),
[машиночитаемые результаты](../android-sdk-1.6.1-cache.json).
Native fixture и задачи генерации конфигурации Flutter проходят strict reuse
и инвалидацию; это не полная Flutter-сборка. CI явно сохраняет ограничение.

**Условие закрытия:** совместимое исправление Flutter Gradle plugin/toolchain и
успешный `check_android_configuration_cache.py --require-full-flutter` с обоими
контролями и инвалидацией. Не включать cache полного Flutter assemble на
основании native fallback. Публикация пакетов и другие платформы этого не исправляют.
