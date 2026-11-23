# Фильтрация и контекст событий

## Ручная отправка и ключи

```dart
try {
  await repository.load();
} catch (error, stackTrace) {
  await Tracer.recordError(
    error,
    stackTrace,
    severity: TracerSeverity.warning,
    issueKey: 'ORDERS-LOAD',
    customKeys: {'endpoint': '/orders'},
  );
}

Tracer.log('пользователь нажал «оформить»', category: 'ui');
await Tracer.setCustomKey(key: 'checkout_step', value: '3');
await Tracer.removeCustomKey('checkout_step');
```

Ключ события может переопределить постоянный ключ. Начиная с версии 0.4.2, Android-адаптер
восстанавливает нативный контекст после каждого Dart-отчёта.
[Область проверки и ограничения при конкурентных вызовах](android-event-context.md).

`issueKey` переопределяет группировку. Если он не задан, пакет синтезирует ключ
из типа ошибки и внутреннего именованного кадра, без имени файла и строки.

## beforeSend и beforeBreadcrumb

```dart
TracerOptions(
  filterErrorPolicy: TracerFilterErrorPolicy.drop,
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<скрыто>')
      : event,
  beforeBreadcrumb: (crumb) => crumb.category == 'auth' ? null : crumb,
)
```

Верните `null`, чтобы отбросить событие или breadcrumb. По умолчанию при
исключении в хуке `sendOriginal` сохраняет исходное значение. Для безопасного
fail-closed режима используйте `TracerFilterErrorPolicy.drop`, как в примере:
ошибочный фильтр не вызывается повторно, а исходные данные не попадают ни в
platform event/raw stack, ни в Dart/native breadcrumb buffers.

Debug-диагностика таких ошибок содержит только фиксированное сообщение, без
исключения и данных события. Policy применяется к Dart-фильтрам и не фильтрует
native crashes или ранее записанные native SDK данные. Она не заменяет аудит
отправляемых данных. Текущее значение по умолчанию сохранено до отдельного
решения для API 2.0.

С версии фасада 1.4.0 событие сохраняет снимок ключей, breadcrumbs и кадров стека.
Для удаления метаданных Flutter в `beforeSend` верните
`event.copyWith(removeLibrary: true, removeContext: true)`. Каждый флаг можно
применить отдельно.

## Диагностика доставки и lifecycle

`TracerOptions.deliveryListener` сообщает typed transitions HTTP-очереди и ошибки
platform calls/lifecycle без чтения debug-логов:

```dart
TracerOptions(
  deliveryListener: (diagnostic) {
    myLogger.info(
      '${diagnostic.backend}:${diagnostic.operation}:${diagnostic.reason}',
    );
  },
)
```

Обработчик получает имя бэкенда, операцию, причину, состояние и номер попытки.
Встроенные адаптеры используют фиксированные коды, например
`recordError/platform_exception` и `stopCollection/operation_error`. В этих
полях нет содержимого отчёта, текста исключения, стека, DSN или токена.
Исключение обработчика или ошибка возвращённого им `Future` не прерывает сбор.
При повторной инициализации можно задать новый обработчик. Для HTTP обработчик
из `TracerOptions` имеет приоритет над обработчиком из конструктора транспорта.

В `TracerHttpTracer` и автоматически зарегистрированном веб-адаптере
`recordError` ждёт локальной обработки очереди, включая попытку записи в
хранилище. Событие может остаться в памяти или быть отброшено. Состояние
`sent` означает получение HTTP-ответа с кодом ниже 400. Проверить появление
отчёта можно в консоли Tracer. На Android, iOS и в десктопном SDK семантика
`Future` платформенного вызова сохраняется. Эти SDK не подтверждают доставку
через обработчик диагностики.

Метод `stopCollection` сохраняет тип `Future<void>`. Обработчик получает
обнаруженные ошибки остановки. Метод `stopAndClearCollection` запрашивает
удаление ожидающих отчётов и возвращает `TracerCollectionResult`. По результату
можно узнать, поддерживает ли платформа очистку и нужен ли перезапуск.

## Большие стектрейсы

Дословный стек ограничен 8 КБ по умолчанию, разобранные кадры — 128. Начало
трейса сохраняется, потому что там `build_id` и ближайшие к месту броска кадры.
Нулевой лимит сохраняет весь текст стека или все разобранные кадры.
При `maxBreadcrumbs: 0` Dart-буфер остаётся пустым. Фасад по-прежнему
передаёт записи в лог бэкендам, которые это запрашивают. Каждый бэкенд
управляет хранением записей самостоятельно.

Фасад проверяет лимиты при старте и в debug, и в release. Отрицательное
значение `maxBreadcrumbs`, `maxRawStackTraceLogBytes` или `maxStackFrames`
приводит к результату `error` от `Tracer.startCollection` с причиной
`invalid_max_breadcrumbs`, `invalid_max_raw_stack_trace_log_bytes` или
`invalid_max_stack_frames` соответственно. При отложенной инициализации
проверка действует при явном запуске. В обоих режимах `Tracer.initialize`
вызывает `appRunner` ровно один раз.

```dart
TracerOptions(
  maxRawStackTraceLogBytes: 32768, // 0 — без лимита
  maxStackFrames: 256,             // 0 — без лимита
)
```

Подробности данных и очистки — в [privacy.md](privacy.md), символизации — в
[symbolication.md](symbolication.md).
