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
2. Подключить listener через публичный facade или его `TracerOptions`, включая
   автоматически зарегистрированный `AppTracerWeb`. Сохранить source compatibility
   текущего API и исключить вызовы listener предыдущей сессии после смены аккаунта.
3. Передавать HTTP `queued/retry/dropped/failed/sent` через общий контракт. `sent`
   по-прежнему означает HTTP-ответ со статусом ниже 400.
4. Добавить диагностику platform call/lifecycle failures для native и desktop без
   выдумывания delivery confirmations, которых SDK не предоставляет. Обработать
   исключения и возвращённые `TracerCollectionResult` со статусом `error`.
   Использовать фиксированные диагностические коды: строка `result.reason`
   может содержать исходный текст исключения.
5. Сохранить существующий HTTP listener как совместимый API или явно адаптировать
   его без двойных событий.
6. Сохранить `Future<void> stopCollection()` и сообщать наблюдаемый сбой остановки
   через listener. Описать отдельно `stopAndClearCollection`, который также
   очищает отчёты и возвращает типизированный результат.
7. Обновить RU/EN guides, Dartdoc и changelogs примерами production diagnostics.

## Критерии приёмки

- Приложение получает typed failures для HTTP и platform calls без debug mode.
- Callback не получает сообщение ошибки, stack, event payload, DSN или app token.
- Исключение listener не влияет на доставку и приложение; события не дублируются.
- На Web/HTTP `recordError` завершается при ещё не завершившемся HTTP-запросе.
  На остальных backend сохранить семантику возвращаемого Future и не вводить
  дополнительное ожидание сети. Stop/revoke немедленно закрывают приём новых Dart-событий.
- Старый API остаётся совместимым, ограничения native SDK явно описаны.

## Проверки

- Unit-тесты facade/interface/HTTP/desktop и Chrome-тесты по затронутому контракту.
- Полный `make check`, publish dry-run и проверка отсутствия PII в diagnostics.

## Не входит

- Ожидание HTTP-ответа каждым `recordError`.
- Гарантия появления события в Tracer по `sent`.
- Breaking change типов lifecycle до API 2.0.
