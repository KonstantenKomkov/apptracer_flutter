# What data leaves the device

This package is aimed at applications that have to answer for every field they
transmit, so the default is deliberately austere: **this package adds no
personal data of its own.** Everything it sends is either a property of the
error or something the application explicitly handed it.

That is only half the picture, though. On Android and iOS the vendor's native
SDK collects its own metadata, and it does so whether or not this package is
installed. Both halves are listed below.

## What this package sends

| Field | Contents | When | Off by |
|---|---|---|---|
| Exception type | Dart runtime type, e.g. `FormatException` | every event | — |
| Message | `error.toString()` minus the duplicated type prefix | every event | `beforeSend` |
| Stack trace | parsed Dart frames: member, file URI, line, column | every event | `beforeSend` |
| Verbatim stack trace | the same trace as unmodified text, in the log buffer | every event | `attachRawStackTraceAsLog: false` |
| Severity, fatal flag, timestamp | — | every event | — |
| `issueKey` | supplied by the caller, or synthesised on iOS from type + top frame | every event | — |
| Breadcrumbs | free text written by the application | events, plus mirrored to the native log as they happen | `maxBreadcrumbs: 0`, `beforeBreadcrumb` |
| Custom keys | key/value pairs written by the application | every event | do not set them |
| `dart.exception_type`, `dart.obfuscated`, `dart.build_id` | diagnostics for symbolication | every event | — |
| User id | whatever the application passed to `Tracer.setUserId` | only after that call | never call it |

Nothing on that list is populated automatically from the device, the install or
the user. A message or a file path can of course contain personal data if the
application put it there — `beforeSend` exists for exactly that case:

```dart
TracerOptions(
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<redacted>')
      : event,
)
```

`beforeSend` runs before anything is handed to the platform. A hook that throws
is logged and ignored, and the original event is still sent — dropping errors
because a redaction rule has a bug would be the worse failure.

## A note on debug logging

With `TracerOptions.debug` the iOS SDK writes its own log to the console, and
that log contains the upload URL **including the `crashToken` query parameter**.
Observed 2026-08-26. Keep debug builds' console output out of shared logs and
screen recordings, or treat the token as disclosed. This package's own
diagnostics print at most the first six characters of a token.

## What the native Android SDK sends on its own

Collected by `ru.ok.tracer` itself, documented by the vendor, and **not
controllable from Dart**:

`date`, `board` (`Build.BOARD`), `brand`, `cpuABI` (`Build.SUPPORTED_ABIS`),
`device`, `manufacturer`, `model`, `osVersionSdkInt`, `osVersionRelease`,
`cpuCount`, `operatorName` (mobile operator, when available), `installer`
(installing package).

Since SDK 1.4.0 each crash also carries **the free space remaining on the
device's storage**, which the vendor added because a full store turns out to be
a common cause of failures.

Observed live on 2026-08-26, on SDK 1.4.0, in the "Data" tab of a real event:
the report also carries **the free RAM** at the moment of the crash. The vendor
does not list it among the collected fields, so treat the list above as a
lower bound rather than an exhaustive one.

Together these form a reasonably distinctive device fingerprint. The crash-free
metric additionally requires a per-installation identity: the vendor states that
the same user on two devices, or after a reinstall, counts as two units, which
means an install-scoped identifier exists.

To avoid all of it, do not add the Tracer Android SDK; the package degrades to
reporting nothing on Android rather than failing.

## What the native iOS SDK sends on its own

The OKTracer SDK collects system information through
`TracerSystemInfoProviderProtocol`. An application that needs to constrain it
can supply its own implementation — but only from native code, since this
package does not expose that hook.

## The Sentry-protocol transport

The pure-Dart transport (web, desktop, Aurora) sends exactly the table in the
first section and nothing else. In particular it does not attach a device
context, an IP-derived location or an automatically generated user id. It has no
access to a device identifier and does not create one.

Note that any HTTP request reveals the client IP address to the receiving
server. That is a property of the network, not of this package.

## Consent is not optional

The Tracer License Agreement puts this on you, not on the vendor and not on this
package. Two clauses, in the edition dated 29 May 2025:

* **1.2** — you are the data controller for your end users' personal data, and
  you *entrust* its processing to VK as processor for the purposes of the
  agreement.
* **1.3** — you **undertake to obtain the end-user consents required by
  applicable law** for that processing.

So shipping Tracer in an application means having a consent story before the
first event is sent. That is why this package has two separate switches rather
than one, and why stopping actually stops.

Two switches, for two different situations.

**Before the first frame** — the user has already declined:

```dart
Tracer.initialize(
  options: TracerOptions(isCollectionEnabled: consent.isGranted),
  appRunner: () => runApp(const MyApp()),
);
```

No native SDK is started and nothing is transmitted. `appRunner` still runs
exactly once.

**During the session** — the user withdraws consent:

```dart
await Tracer.stopCollection();
```

The Dart error handlers are removed and whatever handlers were installed before
are restored. On Android this also calls `Tracer.disable()`, which the native
SDK cannot undo before the process restarts — deliberately, since a withdrawal
of consent should not be quietly reversible.

## Data residency and retention

Tracer states that data is stored in Russia and that events are kept for the
last 90 days. Both are properties of the service, not of this package; verify
them against your own agreement with the vendor rather than against this file.

## Where the vendor's obligations end

Worth reading before you decide how much to send. Under the agreement the
Library is provided **"как есть" (as is)**, clause 2.1: the Licensor gives no
warranty that it fits any particular purpose and promises no specific results.
Clause 6.2.2 lets the Licensor suspend or terminate a Licensee's access at any
time without explanation or notice, and the closing clause 4.1 lets the
agreement itself change without prior notice.

None of that is unusual for a free service, and none of it is this package's
doing. It does mean that diagnostics you cannot afford to lose should not live
only in Tracer.
