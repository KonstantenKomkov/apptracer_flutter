# apptracer_flutter_platform_interface

Общий интерфейс платформы для [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) — неофициальной
интеграции Flutter с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

**Код приложения должен зависеть от `apptracer_flutter`, а не от этого пакета.**
Он существует ради того, чтобы реализации под платформы и пакет, обращённый к
приложению, версионировались независимо.

Здесь лежит:

* `TracerPlatform` — контракт, который расширяет каждая реализация, и
  `UnsupportedTracerPlatform`: инертная заглушка, благодаря которой платформа
  без реализации остаётся безобидной, а не фатальной.
* `MethodChannelTracer` — общий для реализаций под Android и iOS.
* `DartStackTrace.parse` — парсер всех форм стектрейса, которые способно выдать
  Flutter-приложение: кадры JIT, обфусцированные кадры AOT с заголовком
  `build_id`, кадры `dart2js` в нотациях V8 и SpiderMonkey, асинхронные
  маркеры. Исходный текст сохраняется всегда: обфусцированный трейс
  расшифровывается только через `flutter symbolize`, а тому нужны исходные
  байты.
* Модели данных: `TracerOptions`, `TracerEvent`, `TracerBreadcrumb`,
  `TracerSeverity`.

## Как реализовать платформу

Расширяйте `TracerPlatform`, а не имплементируйте — тогда новые члены можно
добавлять без ломающего изменения, — и регистрируйте реализацию в
`registerWith`.

См. [матрицу платформ](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).
