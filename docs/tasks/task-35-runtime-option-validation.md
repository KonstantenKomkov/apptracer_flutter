# П. 35. Runtime-валидация параметров TracerOptions

**Статус:** выполнена. **Приоритет:** P2. **Сложность:** S.

Связанный общий план: [development_v1.md](development_v1.md).

## Результат

[PR №35](https://github.com/KonstantenKomkov/apptracer_flutter/pull/35) добавил
стабильные `invalid_max_*` для трёх отрицательных лимитов при выключенных
assertions, сохранил `const TracerOptions` и documented zero/unlimited semantics.
Codex-ревью исправило отложенную остановку native start, повторный invalid start
поверх валидной сессии и восстановление cold bootstrap после ошибки.

Поведенческие тесты с `--enable-asserts=false`, полный `make check` и
`git diff --check` прошли; все 33 CI checks зелёные, scheduled canary report
пропущен по условию. Device/live acceptance не запускался.

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
