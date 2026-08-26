# apptracer_flutter_ios

The iOS implementation of [`apptracer_flutter`](https://github.com/komkovkonstantin/apptracer_flutter), an unofficial Flutter
integration with [Tracer](https://apptracer.ru).

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

You do not need to depend on this package directly; `apptracer_flutter` pulls
it in.

## What it does

Forwards Dart errors to the `OKTracer` SDK as `TracerNonFatalModel`. Native
crashes, hangs and MetricKit reports are handled by that SDK on its own.

Because a Dart stack trace carries no native addresses — and Tracer ignores a
supplied symbol array unless a debugger is attached — this implementation
synthesises an `issueKey` from the Dart error type and its top frame so that
errors still group per call site. Pass your own `issueKey` to override it.

Breadcrumbs are delivered through `TracerLogProviderProtocol`, which leaves the
SDK's own logging verbosity untouched.

## Setup

`OKTracer` lives in the vendor's own CocoaPods spec repository, so `ios/Podfile`
must declare it:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'
```

Unlike Android, `TracerOptions.appToken` **is** used on iOS.
