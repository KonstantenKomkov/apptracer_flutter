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

Breadcrumbs and custom keys travel only with an event. Event keys override
persistent keys only for that event; later events use the persistent values
again. Android restores native scope after every report, so values from a
previous event cannot leak into the next one.

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

Return `null` to drop an event or breadcrumb. A throwing hook is logged and
ignored, and the original event is sent. `beforeSend` runs before data reaches
the platform; removed persistent and event-only fields must not be restored by
native scope.

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
