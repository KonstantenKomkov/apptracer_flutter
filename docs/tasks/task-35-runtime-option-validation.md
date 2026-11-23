# П. 35. Runtime-валидация параметров TracerOptions

**Статус:** открыта. **Приоритет:** P2. **Сложность:** S.

Связанный общий план: [development_v1.md](development_v1.md).

## Контекст

`TracerOptions` и `BreadcrumbBuffer` проверяют неотрицательные лимиты только через
`assert`, который отключён в release. Отрицательный `maxBreadcrumbs` может дойти
до цикла удаления из пустой очереди. Отрицательные frame/raw-byte limits
неочевидно смешиваются с documented zero/unlimited semantics.

## Цель

Отклонять недопустимые лимиты при выключенных assertions и сохранить
публичный конструктор `const TracerOptions`.

## Сделать

1. Проверить три лимита до вызова `platform.startCollection`, создания буфера
   и установки обработчиков. Покрыть автоматический запуск через `Tracer.initialize`
   и явный `Tracer.startCollection` после deferred bootstrap.
2. Сохранить const constructor и сигнатуры обоих методов запуска.
3. Сделать `BreadcrumbBuffer` безопасным при любом значении: отрицательное не
   должно приводить к удалению из пустой очереди.
4. Явно определить и задокументировать поведение `maxRawStackTraceLogBytes` и
   `maxStackFrames` для нуля и недопустимых отрицательных значений.
5. Добавить тесты с отключёнными assertions и сохранить debug assertions как
   раннюю подсказку разработчику, если они остаются полезными.

## Критерии приёмки

- Release не падает внутри reporter при отрицательных публичных лимитах.
- При старте из выключенного состояния каждый из трёх отрицательных лимитов
  оставляет Dart-сбор выключенным, без вызова старта backend. Явный старт
  возвращает `TracerCollectionState.error` со стабильной причиной.
  `Tracer.initialize` вызывает `appRunner` ровно один раз.
- Нулевой `maxBreadcrumbs` отключает только Dart-буфер. Нулевые
  `maxStackFrames` и `maxRawStackTraceLogBytes` снимают соответствующие лимиты.
- Существующий код с валидным `const TracerOptions` компилируется.

## Проверки

- Unit-тесты границы и buffer, включая запуск с disabled assertions.
- Полный `make check` и `git diff --check`.

## Не входит

- Изменение смысла нулевых лимитов.
- Немотивированное удаление `const TracerOptions`.
