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
  filterErrorPolicy: TracerFilterErrorPolicy.drop,
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<redacted>')
      : event,
  beforeBreadcrumb: (crumb) => crumb.category == 'auth' ? null : crumb,
)
```

Return `null` to drop an event or breadcrumb. By default, `sendOriginal` keeps
the original value when a hook throws. For fail-closed filtering, set
`TracerFilterErrorPolicy.drop` as shown above: the failed filter is not called
again, and original data reaches neither platform events/raw stacks nor the
Dart/native breadcrumb buffers.

Debug diagnostics for filter failures use fixed messages without exception text
or event data. This policy covers Dart filters only; it does not filter native
crashes or data already recorded by a native SDK, and it does not replace auditing
your event data. The current default is preserved pending a separate API 2.0 decision.

Starting with facade 1.4.0, events snapshot their custom keys, breadcrumbs and
stack frames. To clear Flutter metadata in `beforeSend`, return
`event.copyWith(removeLibrary: true, removeContext: true)`. Each flag can be
used independently.

## Delivery and lifecycle diagnostics

`TracerOptions.deliveryListener` reports typed HTTP queue transitions and platform
call/lifecycle failures without requiring debug logs:

```dart
TracerOptions(
  deliveryListener: (diagnostic) {
    myLogger.info(
      '${diagnostic.backend}:${diagnostic.operation}:${diagnostic.reason}',
    );
  },
)
```

Diagnostics contain only backend, operation, stable reason, state and attempt — no
payload, exception text, stack trace, DSN or app token. A listener exception is
ignored and cannot affect the application. Reinitialization replaces the listener.

`queued/retry/dropped/failed` describe the local transport. `sent` means only an
HTTP response below 400, not that the event appeared in the Tracer console. HTTP
`recordError` completes after queueing rather than awaiting the network. Legacy
`stopCollection` keeps `Future<void>`; report its failure through the listener.
`stopAndClearCollection` also clears reports and returns a typed result.

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
