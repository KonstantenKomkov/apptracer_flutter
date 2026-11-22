# Filtering and event context

## Manual reporting and keys

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

Tracer.log('user tapped checkout', category: 'ui');
await Tracer.setCustomKey(key: 'checkout_step', value: '3');
await Tracer.removeCustomKey('checkout_step');
```

Event keys can override persistent keys. Starting with version 0.4.2, the Android adapter
restores native scope after each Dart report. See the [verified scope and concurrency limits](android-event-context.md).

`issueKey` overrides grouping. Without it, the package derives a key from the
error type and innermost named frame, excluding file and line number.

## beforeSend and beforeBreadcrumb

```dart
TracerOptions(
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<redacted>')
      : event,
  beforeBreadcrumb: (crumb) => crumb.category == 'auth' ? null : crumb,
)
```

Return `null` to drop an event or breadcrumb. If a hook throws, the client
logs the exception and keeps the original event or breadcrumb.

Starting with facade 1.4.0, events snapshot their custom keys, breadcrumbs and
stack frames. To clear Flutter metadata in `beforeSend`, return
`event.copyWith(removeLibrary: true, removeContext: true)`. Each flag can be
used independently.

## Large stack traces

The verbatim trace is capped at 8 KiB by default and parsed frames at 128. The
beginning is retained because it carries the `build_id` and frames nearest the
throw. Adjust the limits if needed:

```dart
TracerOptions(
  maxRawStackTraceLogBytes: 32768, // 0 = no limit
  maxStackFrames: 256,             // 0 = no limit
)
```

See [privacy.md](privacy.md) for data and cleanup and
[symbolication.md](symbolication.md) for exact-build symbols.
