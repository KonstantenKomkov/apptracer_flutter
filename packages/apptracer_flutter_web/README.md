# apptracer_flutter_web

Реализация [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) под web — неофициальной интеграции Flutter
с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Зависеть от этого пакета напрямую не нужно: его подтягивает
`apptracer_flutter`.

## Почему здесь нет обёртки над JS SDK Tracer

JavaScript SDK Tracer поставляется npm-пакетом `@apptracer/sdk`, а web-сборка
Flutter не умеет включать в себя npm-пакеты. При этом Tracer принимает события
по протоколу Sentry на всех платформах, и этому пути не нужно ничего, кроме
HTTP-клиента, — поэтому реализация отправляет конверты Sentry из чистого Dart
через [`apptracer_flutter_http`](https://github.com/KonstantenKomkov/apptracer_flutter/tree/main/packages/apptracer_flutter_http).

Из этого следует:

* Перехватываются только ошибки Dart. Падение в постороннем `<script>` не
  видно.
* Кадры — это кадры `dart2js`, а сорсмапы Tracer сопоставляет **по пути файла,
  а не по Debug ID**. См. [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).
* `TracerOptions.dsn` обязателен; `appToken` на этом пути не используется.
