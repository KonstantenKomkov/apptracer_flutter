# П. 37. Risk-based coverage для desktop и lifecycle

**Статус:** открыта. **Приоритет:** P2. **Сложность:** M.

Связанные документы: [единые проверки №28](task-28-unified-checks-coverage.md),
[команды](../contributing.md#commands), [общий план](development_v1.md).

## Контекст

Для четырёх критичных файлов общих пакетов в `tool/coverage_baseline.json`
записаны числа покрытых и измеренных строк. Desktop report формируется отдельно, но не сравнивается с baseline;
`sentry_desktop_tracer.dart` содержит сложные cancellation/close/clear ветки.
Простое повышение общего процента forwarding-методами не снижает основной риск.

## Цель

Предотвращать регрессии покрытия критичного desktop lifecycle и закрыть тестами
наиболее опасные непроверенные ветки без цели 100%.

## Сделать

1. Добавить host-aware desktop baseline для `sentry_desktop_tracer.dart` и при
   необходимости других общих lifecycle файлов; исключить foreign-OS sources
   тем же явным способом, что и текущий report.
2. Взять исходные значения из LCOV каждой ОС. В обычном запуске
   `tool/coverage_report.py` и с `--desktop-only` сравнивать файл с baseline
   текущего host. Сохранить отдельную проверку четырёх файлов общих пакетов.
3. Добавить поведенческие тесты cancellation, initialization/close/clear failure,
   restartRequired и revoke races по фактически непокрытым веткам. Сначала
   сверить LCOV с существующими тестами этих сценариев, затем для каждого
   добавленного теста указать ранее непроверенный исход.
4. Публиковать desktop critical summary в профильных CI artifacts/step summary и
   делать regression видимым в общем локальном `make check`. Проверить
   фильтры путей: PR, меняющий только baseline или coverage reporter, должен
   проверяться с LCOV всех трёх ОС, в том числе при неизменном Dart-коде.
5. Обновить baseline только осознанно вместе с анализом изменённых строк; описать
   процесс в `docs/contributing.md`.

## Критерии приёмки

- Снижение покрытия выбранного desktop critical файла ниже baseline валит проверку
  на каждой поддерживаемой host OS.
- Новые тесты проверяют observable lifecycle behavior, а не только вызов строк.
- Общий coverage report по-прежнему различает VM, Chrome и native/live evidence.
- Нет искусственного глобального порога или тестов ради forwarding-строк.

## Проверки

- Unit-тесты coverage tooling: baseline pass, regression fail, host exclusions,
  missing input и intentional baseline update.
- Desktop tests и полный `make check`; профильные platform workflows по diff.
- `git diff --check`, чистое дерево.

## Не входит

- Погоня за 100% line coverage.
- Объединение несопоставимых host-specific знаменателей в одно число.
- Замена native runtime acceptance unit coverage.
