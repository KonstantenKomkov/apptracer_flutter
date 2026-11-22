# П. 34. Общая наблюдаемость доставки и lifecycle

**Статус:** открыта. **Приоритет:** P1. **Сложность:** L.

Связанный общий план: [development_v1.md](development_v1.md).

## Контекст

HTTP transport уже выдаёт `TracerDeliveryDiagnostic`, но общий facade не имеет
единого канала диагностики. Platform errors поглощаются `_guard`, `recordError`
возвращает `Future<void>`, а legacy `stopCollection` теряет typed result.

## Цель

Позволить приложению наблюдать отказы доставки и lifecycle без чтения debug-логов,
не блокируя `recordError` сетевым подтверждением и не передавая персональные данные
в диагностический callback.

## Сделать

1. Спроектировать общий typed diagnostic model/listener в platform interface:
   backend, operation, stable reason, attempt и состояние без payload/tokens.
2. Подключить listener через `TracerOptions` либо facade с безопасной обработкой
   исключений и повторной инициализации. Сохранить source compatibility текущего API.
3. Передавать HTTP `queued/retry/dropped/failed/sent` через общий контракт. `sent`
   по-прежнему означает только HTTP-ответ, не подтверждение консолью Tracer.
4. Добавить диагностику platform call/lifecycle failures для native и desktop без
   выдумывания delivery confirmations, которых SDK не предоставляет.
5. Сохранить существующий HTTP listener как совместимый API или явно адаптировать
   его без двойных событий.
6. Не менять тип `stopCollection` в текущем major; задокументировать typed
   `stopAndClearCollection` и подготовить унификацию lifecycle API к 2.0.
7. Обновить RU/EN guides, Dartdoc и changelogs примерами production diagnostics.

## Критерии приёмки

- Приложение получает typed failures для HTTP и platform calls без debug mode.
- Callback не получает сообщение ошибки, stack, event payload, DSN или app token.
- Исключение listener не влияет на доставку и приложение; события не дублируются.
- `recordError` не ждёт сеть; stop/revoke немедленно закрывают приём новых событий.
- Старый API остаётся совместимым, ограничения native SDK явно описаны.

## Проверки

- Unit-тесты facade/interface/HTTP/desktop и Chrome-тесты по затронутому контракту.
- Полный `make check`, publish dry-run и проверка отсутствия PII в diagnostics.

## Не входит

- Ожидание HTTP-ответа каждым `recordError`.
- Гарантия появления события в Tracer по `sent`.
- Breaking change типов lifecycle до API 2.0.
