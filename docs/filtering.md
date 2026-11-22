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
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<скрыто>')
      : event,
  beforeBreadcrumb: (crumb) => crumb.category == 'auth' ? null : crumb,
)
```

Верните `null`, чтобы отбросить событие или breadcrumb. При исключении в хуке
клиент пишет его в лог и сохраняет исходное событие или breadcrumb.

С версии фасада 1.4.0 событие сохраняет снимок ключей, breadcrumbs и кадров стека.
Для удаления метаданных Flutter в `beforeSend` верните
`event.copyWith(removeLibrary: true, removeContext: true)`. Каждый флаг можно
применить отдельно.

## Большие стектрейсы

Дословный стек ограничен 8 КБ по умолчанию, разобранные кадры — 128. Начало
трейса сохраняется, потому что там `build_id` и ближайшие к месту броска кадры.
Настройте лимиты при необходимости:

```dart
TracerOptions(
  maxRawStackTraceLogBytes: 32768, // 0 — без лимита
  maxStackFrames: 256,             // 0 — без лимита
)
```

Подробности данных и очистки — в [privacy.md](privacy.md), символизации — в
[symbolication.md](symbolication.md).
