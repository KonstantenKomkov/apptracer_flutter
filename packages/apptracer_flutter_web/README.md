# apptracer_flutter_web

Реализация [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) под web — неофициальной интеграции Flutter
с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Зависеть от этого пакета напрямую не нужно: его подтягивает
`apptracer_flutter`.

## Почему здесь нет обёртки над JS SDK Tracer

JavaScript SDK Tracer поставляется npm-пакетом `@apptracer/sdk`, а web-сборка
Flutter не умеет включать в себя npm-пакеты. Поэтому реализация говорит с тем же
приёмом, что и этот SDK, — `POST /api/crash/uploadBatch` с `appToken` проекта, —
из чистого Dart, через
[`apptracer_flutter_http`](https://github.com/KonstantenKomkov/apptracer_flutter/tree/main/packages/apptracer_flutter_http).

Раньше отсюда уходили конверты Sentry: считалось, что Tracer принимает события
по протоколу Sentry на всех платформах. Проверка 26.08.2026 этого не
подтвердила — DSN не выдаётся ни одному проекту, а в SDK вендора никакого Sentry
нет. Формат снят с живого запроса и описан в
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).

Из этого следует:

* `TracerOptions.appToken` обязателен, и это `appToken` **JS-проекта**. `dsn` на
  этом пути не используется вовсе.
* Перехватываются только ошибки Dart. Падение в постороннем `<script>` не
  видно.
* Кадры — это кадры `dart2js`, а сорсмапы Tracer сопоставляет **по пути файла,
  а не по Debug ID**. См. [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).
* Нативных крашей на web не бывает, и метрику crash-free пакет не считает:
  `trackSession` вендорского SDK он не шлёт.
* Приём требует `deviceId`, поэтому реализация заводит его сама: UUID в
  `localStorage` под ключом `apptracer_flutter.deviceId`, переживающий
  перезагрузку страницы. В приватном окне или при запрете хранилища он живёт
  столько же, сколько вкладка. Это единственный идентификатор, который пакет
  создаёт от себя.
