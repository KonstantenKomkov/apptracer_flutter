# Changelog

## 2.0.0

- Integrate with facade 2.0.0 on Flutter Aurora 3.41.4. Native crash collection
  requires Tracer Native 0.1.15 and an app token. An explicit Sentry DSN enables
  Dart, Flutter and async errors.
- Support consent withdrawal, scoped native replay and native symbol upload for
  the signed RPM. Verified on the Aurora 5.2.1.200 aarch64 emulator.
