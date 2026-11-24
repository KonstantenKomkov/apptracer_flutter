# apptracer_flutter_desktop

Дополнительный адаптер для отправки ошибок Dart и нативных падений в Tracer на macOS, Windows и Ubuntu. Фасад `apptracer_flutter` регистрирует обработчики ошибок, а адаптер отправляет отчёты через официальный Sentry Flutter SDK по DSN вашего проекта Tracer.

[English](README.en.md)

## Быстрый старт

1. Установите фасад и адаптер из каталога desktop-приложения. Для адаптера 2.0.0 нужны Flutter 3.44 или новее и Dart 3.12 или новее.

   ```sh
   flutter pub add apptracer_flutter apptracer_flutter_desktop
   ```

2. Подготовьте сборку для своей платформы.

   | Платформа | Что настроить |
   |---|---|
   | macOS arm64 | Включите Swift Package Manager, задайте Runner deployment target macOS 12.0 или выше и разрешите исходящие соединения в release entitlements. [Настройка macOS](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#external-application) |
   | Windows 11 x64 | Перед сборкой задайте в PowerShell `$env:SENTRY_NATIVE_BACKEND = 'native'`. Распространяйте весь каталог Release вместе с DLL и обработчиком падений. [Сборка Windows](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#windows-consumer) |
   | Ubuntu 22.04.5 x86_64 (X11) | Задайте `SENTRY_NATIVE_BACKEND=native` и настройте CMake, чтобы в bundle попал исполняемый `lib/sentry-crash`. [Настройка CMake и упаковка](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#ubuntu-linux-consumer) |

3. Передайте HTTPS DSN проекта Tracer для целевой платформы. Адаптер регистрируется автоматически.

   ```dart
   import 'package:apptracer_flutter/apptracer_flutter.dart';
   import 'package:flutter/material.dart';

   Future<void> main() async {
     await Tracer.initialize(
       options: const TracerOptions(dsn: String.fromEnvironment('TRACER_DSN')),
       appRunner: () => runApp(const MyApp()),
     );
   }
   ```

4. Запустите приложение с DSN. Например, на macOS выполните команду ниже. Для Windows или Ubuntu используйте устройство `windows` или `linux`.

   ```sh
   flutter run -d macos --release --dart-define=TRACER_DSN=YOUR_PROJECT_DSN
   ```

   Вызовите `await Tracer.recordError(StateError('desktop check'), StackTrace.current)` из кнопки и проверьте карточку ошибки в проекте Tracer.

## Согласие и доставка

Для отложенного сбора задайте `TracerNativeInitialization.deferred` в `TracerOptions.nativeInitialization`. После согласия вызовите `Tracer.startCollection()`, при отзыве — `Tracer.stopAndClearCollection()`. После остановки активного нативного SDK для нового старта нужен перезапуск процесса. При обычном перезапуске очередь восстанавливается только с `preservePreviousReports: true`. На macOS ответ сервера HTTP 5xx может привести к потере отчёта. [Жизненный цикл и ограничения доставки](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#sentry-upgrades)

Адаптер сам инициализирует Sentry. Вызывайте API через `Tracer`. Фильтр `beforeSend` обрабатывает события Dart. Ранее записанные ключи, логи и ID пользователя могут попасть в нативный отчёт о падении. [Данные и приватность](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md)

Если мобильные и desktop-сборки используют один `pubspec.yaml`, зависимость `sentry_flutter` добавляет нативный SDK и в Android/iOS. Для независимых наборов зависимостей используйте отдельное desktop-приложение.

## Пример и руководства

- [Пример для трёх платформ](example/README.md)
- [Матрица платформ и проверка символов](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary)
- [Переход со старого транспорта](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#moving-from-the-manual-transport)
- [Отдельный адаптер для Flutter Аврора](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/aurora-release.md)
