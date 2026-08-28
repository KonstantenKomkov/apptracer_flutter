# apptracer_flutter_sentry

Транспорт по протоколу Sentry на чистом Dart для
[`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) —
неофициальной интеграции Flutter с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Tracer принимает события по протоколу Sentry на платформах, под которые у него
нет собственного SDK, — это его документированная рекомендация. Sentry DSN
выдаётся в разделе **Настройки → Проект → API**, но только если проект заведён
через **VK Cloud**.

Для Flutter это десктоп, а также Аврора ОС, где у вендора есть C/C++-SDK с
системными минидампами, до которого из Dart не дотянуться.

> **Ни одна из этих платформ не поддерживается релизом 0.1.0**, и ни одна из них
> ни разу не проверялась на живом проекте. Поэтому на pub.dev пакета нет:
> подключайте его зависимостью из git. К тому же DSN выдаётся
> только проекту, заведённому через VK Cloud: у обычного проекта Tracer его нет
> — проверено 26.08.2026.

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_sentry/apptracer_flutter_sentry.dart';

void main() {
  TracerPlatform.instance = SentryProtocolTracer();
  Tracer.initialize(
    options: const TracerOptions(dsn: 'https://<ключ>@<хост>/<проект>'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

## Чего этот пакет не делает

**Web им не пользуется.** Там у Tracer есть собственный JavaScript-SDK, DSN
обычному JS-проекту не выдаётся, и `apptracer_flutter_web` ходит в тот же приём,
что и SDK вендора.

**Нативные сбои не собираются.** Краши, ANR и зависания требуют нативного SDK:
на Android и iOS правильный выбор — нативные реализации, на Авроре — C/C++-SDK
вендора. Здесь только ошибки Dart.

## Две особенности Tracer, а не Sentry

**Версия.** Sentry-SDK передаёт её в поле `release`. Tracer отбрасывает всё до
последнего `@` включительно, поэтому `my_app@1.2.3` хранится как `1.2.3` — и
ровно это значение нужно указывать при загрузке сорсмап.

**Сорсмапы сопоставляются по пути файла**, а не по Debug ID, как в Sentry. При
расхождении путей десимволизация просто не применится, молча.

## Статус

Сборка конвертов и событий покрыта юнит-тестами и следует документированному
формату приёма Sentry, но на живом проекте Tracer этот транспорт **не
проверялся**: для этого нужен проект, заведённый через VK Cloud. См.
[status.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/status.md).
