# Tracer for Flutter Aurora

Use the optional 2.0.0 source adapter with facade 2.0.0, platform interface
0.3.1 and Flutter Aurora 3.41.4. Release tests used the Aurora 5.2.1.200
aarch64 emulator. Obtain a checkout containing the adapter and prepare Tracer
Native 0.1.15 in that checkout. [Release setup and dependency order](../../docs/aurora-release.md).

```sh
python3 tool/prepare_aurora_sdk.py --destination aurora/apptracer_flutter_aurora/aurora/sdk
```

Add the adapter as a path dependency. Enable the Internet permission in the
Aurora application and call `ApptracerFlutterAuroraPrepareRunner(argc, argv)`
as the first operation in the runner. Keep this custom main.cpp when regenerating
the Aurora project. The hook disables system dumps until collection starts.
[Runner example](example/aurora/main.cpp).

Initialize the facade once with `TracerNativeInitialization.deferred`. After
consent, call `Tracer.startCollection(options)` with the C/C++ project's app
token, application version and an opaque account scope. To report handled Dart
exceptions, add the same project's Sentry DSN. Without a DSN the native SDK
still reports crashes and the delivery listener reports `dart_dsn_missing` for
a Dart error. For native replay after a restart, explicitly allow
`preservePreviousReports` with the same account scope. Await
`Tracer.stopAndClearCollection()` before switching accounts. The plugin token
is used by the symbol uploader on the build machine.

[Run the example](example/README.en.md) · [Live results](../../docs/aurora-live-acceptance.md)
· [Symbol verification](../../docs/aurora-symbols.md).
