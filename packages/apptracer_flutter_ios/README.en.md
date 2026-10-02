# apptracer_flutter_ios

The iOS implementation of [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter), an unofficial Flutter
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

The package supports both of Flutter's iOS dependency managers, Swift Package
Manager and CocoaPods. Flutter uses whichever the application has enabled.

### Swift Package Manager

Nothing to set up: `Package.swift` declares `OKTracer` as a versioned
dependency on the [vendor's repository](https://github.com/odnoklassniki/tracer-ios),
and Xcode fetches the SDK itself.

`Package.swift` depends on nothing Flutter generates: `import Flutter` resolves
through the framework search paths Flutter passes to the build. The Swift
Package Manager path therefore works on every version that has Swift Package
Manager at all, and the package's constraint stays at `>=3.22.0` for both paths.
`url_launcher_ios` from `flutter/packages` and `vkid_flutter_sdk` are built the
same way.

The one difference from CocoaPods is the `dSYM` upload phase, which has to be
added by hand, because nothing evaluates the podspec that would add it at
`pod install`. In Xcode: the `Runner` target → **Build Phases** → **+** → **New
Run Script Phase**, name it `[apptracer_flutter] Upload dSYMs to Tracer` and
paste the contents of
[`ios/tracer_dsym_upload_phase.sh`](ios/tracer_dsym_upload_phase.sh).

The package's own command does the same — it finds the script and edits the
project — given Ruby with the `xcodeproj` gem, the pair CocoaPods itself runs
on:

```sh
dart run apptracer_flutter:install_ios_dsym_phase
```

Running it again is safe: an existing phase is refreshed in place rather than
duplicated.

### CocoaPods

`OKTracer` lives in the vendor's own CocoaPods spec repository and ships as a
static `xcframework`, so `ios/Podfile` needs both the source and static
linkage:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'

target 'Runner' do
  use_frameworks! :linkage => :static
  # ...
end
```

At `pod install` the podspec adds that same build phase to
`Runner.xcodeproj`, uploading the `dSYM` on every release build; `TRACER_SKIP_IOS_PHASE=1` keeps it
away from the project file. The phase reads its token from
`ios/tracer_plugin_token` or from `TRACER_IOS_PLUGIN_TOKEN`.

Unlike Android, `TracerOptions.appToken` **is** used on iOS.

## Native consent lifecycle

Use `TracerNativeInitialization.deferred` for bootstrap, then explicitly call
`Tracer.startCollection` after the application verifies consent. OKTracer is
pinned to **1.5.2**: the plugin audits and manages this version's report paths.

`stopAndClearCollection` (and `stopCollection`) stops and detaches the SDK, deletes pending
reports and replaces its report directories with empty guard files. This blocks
its surviving native crash writer from persisting new reports. Revocation is
saved before native stop, so an automatic startup in a new process stays off
with `consent_required`. After an active session the result is `restartRequired`;
start again only in a new process after new consent, with explicit deferred start.
That start purges old reports even when `preservePreviousReports` is requested.

A failed cleanup keeps collection off with `native_cleanup_failed`. Requests
already in flight may finish; reports already received by the server are not
deleted. The native crash handler itself remains installed until process exit.
The SDK storage paths are reserved for this plugin; do not run another OKTracer
service independently in the same process. Updating the pinned SDK requires a
new storage audit and the device acceptance tests.

See [implementation and device evidence](../../docs/native-collection-consent.md).

### Symbols with Xcode 27

Runner and Flutter source frames were verified on a physical iPhone using
[`tracer_dwarf4.xcconfig`](ios/tracer_dwarf4.xcconfig). Set `XCODE_XCCONFIG_FILE`
to its absolute path when running `flutter build ipa`. This opt-in override applies
to the whole build, including Pods. It retains function names and source lines
but omits imported Clang module debug types; installing the plugin does not
change host build flags. Upload the resulting dSYMs before sending new crashes.
See the [verification record](../../docs/symbolication.md).
