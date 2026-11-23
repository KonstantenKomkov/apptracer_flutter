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

The listener receives the backend, operation, reason, state and attempt number.
The built-in adapters use fixed codes such as `recordError/platform_exception`
and `stopCollection/operation_error`. Payloads, exception messages, stacks and
credentials stay out of these fields. A throwing listener or a failed Future
returned by an async listener does not interrupt collection. A new initialization
selects the listener for subsequent events. On HTTP, the options listener takes
precedence over the optional transport constructor listener.

With `TracerHttpTracer` and the registered web adapter, `recordError` waits for
local queue processing, including the attempted storage write. An entry can be
dropped or retained in memory. `sent` records an HTTP response below 400. Only the
Tracer console can confirm that a report appeared there. Android, iOS and the
desktop SDK retain their platform-call Future semantics and provide no delivery
confirmation through this listener.

Legacy `stopCollection` returns `Future<void>` and reports observable stop
failures through the listener. `stopAndClearCollection` requests deletion of
pending reports and returns a `TracerCollectionResult` describing the platform
outcome, including unsupported cleanup and restart requirements.

## Large stack traces

The verbatim trace is capped at 8 KiB by default and parsed frames at 128. The
beginning is retained because it carries the `build_id` and frames nearest the
throw. A zero limit keeps all raw bytes or parsed frames. Setting
`maxBreadcrumbs` to zero disables Dart breadcrumb storage. The facade still
mirrors breadcrumbs to backends that request it. Each backend controls its own
retention.

The facade validates limits at startup in debug and release. A negative
`maxBreadcrumbs`, `maxRawStackTraceLogBytes` or `maxStackFrames` makes
`Tracer.startCollection` return `error` with reason `invalid_max_breadcrumbs`,
`invalid_max_raw_stack_trace_log_bytes` or `invalid_max_stack_frames`,
respectively. With deferred initialization the check applies to the explicit
start. In either mode `Tracer.initialize` still runs `appRunner` once.

```dart
TracerOptions(
  maxRawStackTraceLogBytes: 32768, // 0 = no limit
  maxStackFrames: 256,             // 0 = no limit
)
```

See [privacy.md](privacy.md) for data and cleanup and
[symbolication.md](symbolication.md) for exact-build symbols.
