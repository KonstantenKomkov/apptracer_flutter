# apptracer_flutter

Неофициальная интеграция Flutter с [Tracer](https://apptracer.ru) — сервисом
мониторинга ошибок от OK.TECH / VK.

> **Это не официальный SDK.** Пакет не связан с VK и OK.TECH, не одобрен и не
> поддерживается ими. Это независимая обёртка над публичными SDK вендора; сами
> SDK пакет не распространяет. С проблемами обращайтесь
> [сюда](https://github.com/KonstantenKomkov/apptracer_flutter/issues), а не в
> поддержку Tracer.

English version: [README.en.md](README.en.md).

## Быстрый старт

**1. Установите пакет** из каталога вашего Flutter-приложения.

```sh
flutter pub add apptracer_flutter
```

**2. Настройте платформу.** Создайте отдельный проект для каждой платформы в
[консоли Tracer](https://apptracer.ru). Для Android, iOS и Web возьмите
`appToken` для событий и `pluginToken` для загрузки символов в настройках API
проекта. Для desktop нужен Sentry DSN.

### Android

Следуйте [полному Android-руководству](../../docs/android-guide.md): BOM и
Gradle-плагин Tracer, репозитории, `resValues = true`, токены и native crashes.
`TracerOptions.appToken` и `TracerOptions.environment` на Android игнорируются.

### iOS

Выберите Swift Package Manager или CocoaPods по
[iOS-руководству](../apptracer_flutter_ios/README.md#подключение). Там же
настройка `dSYM` и `pluginToken`. `appToken` передаётся из Dart.

### Web

Передайте из Dart `appToken` JS-проекта. Web-адаптер входит в пакет.
[Руководство по Web](../../docs/web-protocol.md#web-setup) описывает
загрузку сорсмап и ограничения доставки.

### Desktop (optional)

Для Windows, macOS и Ubuntu Linux добавьте `apptracer_flutter_desktop ^1.0.1`
и настройте Sentry DSN по [desktop-руководству](../../docs/desktop-migration.md).
Основной пакет сам desktop backend не подключает.

**3. Оберните запуск приложения.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      iosAppToken: String.fromEnvironment('IOS_APP_TOKEN'),
      webAppToken: String.fromEnvironment('WEB_APP_TOKEN'),
      dsn: String.fromEnvironment('TRACER_DSN'),
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

`appRunner` вызывается ровно один раз, включая ошибку инициализации и отключённый
сбор. Приложение только для iOS или только для Web может передать токен своего проекта в `appToken`. На Android токен
берётся только из Gradle.

Например, запустите Web-приложение с токеном JS-проекта. Для iOS передайте
`IOS_APP_TOKEN`, для desktop — `TRACER_DSN`.

```sh
flutter run -d chrome --release --dart-define=WEB_APP_TOKEN=YOUR_JS_APP_TOKEN
```

**4. Отправьте тестовое событие.**

```dart
onPressed: () => throw StateError('проверка apptracer_flutter'),
```

Проверьте событие в консоли Tracer. На Android и iOS читаемый Dart-стек находится во вкладке «Логи». Для ручной обработанной ошибки используйте `Tracer.recordError` из
[руководства по контексту](../../docs/filtering.md).

### Если событий нет

Сначала проверьте лог запуска и `Tracer.isEnabled`. Затем:

- Android: включены Gradle-плагин и `resValues = true`, токен передан в `tracer { }`.
- iOS/web: `appToken` задан, например через `--dart-define`.
- На Android и iOS проверяйте release-сборку. По умолчанию нативные SDK отключают отправку из debug-сборок.
- Настройка согласия завершена явным `startCollection`, если выбран deferred-режим.

Подробности — в [platform-matrix](../../docs/platform-matrix.md) и
[руководстве по согласию](../../docs/native-collection-consent.md).

<a id="что-дальше"></a>

## Использование

- [Фильтрация, breadcrumbs и custom context](../../docs/filtering.md).
- [Согласие, pause/resume и stop/clear](../../docs/native-collection-consent.md).
- [Переданные данные и приватность](../../docs/privacy.md).
- [Символизация и большие стектрейсы](../../docs/symbolication.md).
- [Текущие версии и ограничения платформ](../../docs/platform-matrix.md).

### Согласие пользователя

До согласия используйте deferred initialization. После него —
`Tracer.startCollection()`, после logout — `Tracer.stopAndClearCollection()`.
Точный контракт и ограничения очистки описаны в
[native-collection-consent.md](../../docs/native-collection-consent.md).

### Фильтрация данных

`beforeSend` и `beforeBreadcrumb` позволяют изменить или отбросить данные до
платформенной передачи. Примеры и большие стеки — в [filtering.md](../../docs/filtering.md).

### Очень большие стектрейсы

По умолчанию дословный стек ограничен 8 КБ, кадры — 128. Лимиты и причины
описаны в [filtering.md](../../docs/filtering.md#большие-стектрейсы).

### Уровень автоматически перехваченных ошибок

Автоматические ошибки отправляются как `error`, а не `fatal`: процесс при этом
не завершается. `reportUnhandledErrorsAsFatal: true` меняет это осознанно.

## Зачем это нужно

Нативные SDK Tracer не видят ошибок Dart. Пакет перехватывает их через
`FlutterError.onError`, `PlatformDispatcher.instance.onError` и guarded zone и
передаёт нативному SDK, который продолжает обрабатывать native crashes, ANR и
crash-free метрики.

## Сравнение с Firebase Crashlytics

Оба пакета перехватывают ошибки Dart. Tracer использует SDK VK / OK.TECH и их
ingest, Firebase — SDK и ingest Google. Данные и ограничения приватности —
в [privacy.md](../../docs/privacy.md).

## Что вы получите, кроме ошибок Dart

Нативные краши и ANR/hangs обрабатывает SDK платформы. Полный актуальный список
возможностей и ограничений находится только в
[platform-matrix.md](../../docs/platform-matrix.md).

## Какие данные уходят

На Android и iOS пакет не добавляет персональных данных сам. Web добавляет
`deviceId` и браузерный контекст, native SDK собирает собственные метаданные.
Полный список — в [privacy.md](../../docs/privacy.md).

### Группировка

Свой `issueKey` имеет приоритет. Без него ключ синтезируется из типа ошибки и
внутреннего именованного кадра, без файла и строки.

## Release-сборки со `--split-debug-info`

Пакет сохраняет дословный стек и `build_id`. Символы нужны от той же сборки;
ручная расшифровка через `flutter symbolize` описана в
[symbolication.md](../../docs/symbolication.md).

### Android tombstones (SDK 1.5.2)

Экспериментальные tombstones выключены по умолчанию. Настройка и ограничения —
в [Android-руководстве](../../docs/android-guide.md#debug-and-native-crashes).

### Обновление до Android SDK 1.6.2

Инструкции по обновлению и известные ограничения — в [хронологии](../../docs/release-history.md#android-sdk-162-migration).

## Runtime API в apptracer_flutter 1.2.0

Release-specific pause/resume и diagnostic APIs вынесены в
[хронологию релиза](../../docs/release-history.md#apptracer_flutter-120-runtime-apis).
Текущие lifecycle-контракты — в [native-collection-consent.md](../../docs/native-collection-consent.md).

## Лицензия

MIT. SDK вендора лицензируются отдельно, см.
[legal.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/legal.md).
