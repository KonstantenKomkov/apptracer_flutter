# Aurora example

Prepare the SDK in the [adapter checkout](../README.en.md). In this directory run
the following commands with Flutter Aurora 3.41.4, Build Tools 5.2.1.200 and ADT.

```sh
flutter-aurora pub get
flutter-aurora analyze
flutter-aurora build aurora --release --target-platform aurora-arm64 --sdk-dir /path/to/AuroraSDK
adt device deploy --silent build/aurora/*/aurora-arm64/release/RPMS/*example-2*.rpm
adt device exec 'runtime-manager-tool Control start ru.apptracer.apptracer_flutter_aurora_example'
```

Grant Internet access. The screen initially shows the SDK version and disabled
collection. Enter the project's native app token, optional Sentry DSN and an
account scope. Enable collection and send a Dart error, or confirm the native
crash test. After the native crash, reopen the app, enter the same project and
account, enable recovery and start collection to upload the allowed report.
Stop and clear before changing accounts. The example keeps credentials in memory.
[Automated release checks](../../../tool/aurora/acceptance/README.md).
