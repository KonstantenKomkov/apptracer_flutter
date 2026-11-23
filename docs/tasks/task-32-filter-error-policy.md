# П. 32. Управляемое поведение privacy-фильтров при ошибках

**Статус:** выполнена. **Приоритет:** P1. **Сложность:** M.

Связанный общий план: [development_v1.md](development_v1.md).

## Результат

[PR №32](https://github.com/KonstantenKomkov/apptracer_flutter/pull/32) добавил
`TracerFilterErrorPolicy.sendOriginal/drop`, сохранил const API и прежний default.
`drop` блокирует исходные события, raw stacks и breadcrumb native mirror. Отдельно
проверены три automatic capture path, reentrant initialization и сбой debugPrint.

Codex-ревью нашло и исправило сняпшот options при reentrant callback и обработку
ошибок debug printer. После исправлений прошли 100 facade-тестов, 57 interface-тестов,
полный `make check`, documentation tests и ссылки; все 33 CI checks зелёные.
Первый Android job получил внешний Maven Central HTTP 429; повторный запуск прошёл.
Native crashes вне области policy; device/live acceptance не запускался.

## Контекст

Исключение `beforeSend` сейчас отправляет исходное событие, а исключение
`beforeBreadcrumb` сохраняет исходный breadcrumb. Это предотвращает потерю
диагностики, но фильтр персональных данных может аварийно пропустить именно те
данные, которые обязан удалить.

## Цель

Дать приложению явный выбор между доставкой исходных данных и безопасным
отбрасыванием при отказе фильтра, не меняя незаметно существующее поведение.

## Сделать

1. Добавить публичный typed policy для ошибок фильтров с вариантами
   `sendOriginal` и `drop`; значение по умолчанию — текущее `sendOriginal`.
   Экспортировать тип из facade и сохранить выбор в `TracerOptions.copyWith`,
   включая Web-инициализацию.
2. Применять policy к `beforeSend` и `beforeBreadcrumb`, включая события,
   автоматически перехваченные всеми тремя путями.
3. Не вызывать повторно сломанный callback и не отправлять событие/breadcrumb
   после `drop`. Ошибки диагностики не должны влиять на приложение.
4. Для ошибки фильтра и отбрасывания использовать фиксированные debug-сообщения:
   текущие логи включают текст исключения callback или заголовок события.
5. Обновить Dartdoc, [RU](../filtering.md) и [EN](../filtering.en.md) руководства,
   [privacy](../privacy.md) и changelogs затронутых пакетов. Ясно
   указать, что policy не фильтрует native crashes и не заменяет проверку данных.
6. Запланировать отдельное обсуждение значения по умолчанию для API 2.0, не меняя
   его в этом релизе.

## Критерии приёмки

- `sendOriginal` сохраняет прежнее поведение; `drop` гарантированно не пропускает
  исходное событие/breadcrumb при любом исключении callback.
- Успешные callback, возврат `null`, переписывание и обычная доставка не меняются.
- При исключении `beforeSend` с политикой `drop` ручная ошибка и каждая из трёх
  автоматических ошибок не вызывают ни `platform.recordError`, ни запись raw stack
  через `platform.recordLog`. При исключении `beforeBreadcrumb` с той же политикой
  breadcrumb не попадает ни в Dart-буфер, ни в native log mirror. Уже записанные
  ранее breadcrumbs сохраняются. Debug-лог не содержит тестовых данных из callback.
- Документация содержит безопасный пример и ограничения policy.

## Проверки

- Facade unit-тесты и полный `make check`.
- Проверка сериализации/MethodChannel при необходимости по фактическому diff.
- `git diff --check`, чистое дерево после проверок.

## Не входит

- Асинхронные `beforeSend`/`beforeBreadcrumb`.
- Фильтрация уже записанных native crash reports.
- Смена поведения по умолчанию в текущем major API.
