# apptracer_flutter_http

Транспорт на чистом Dart к HTTP-приёму [Tracer](https://apptracer.ru) для
[`apptracer_flutter`](https://github.com/komkovkonstantin/apptracer_flutter) —
неофициальной интеграции Flutter.

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Пакет шлёт `POST /api/crash/uploadBatch`, авторизуясь тем же `appToken`, что и
Android-плагин. Формат восстановлен перехватом живого запроса JS-SDK вендора и
описан в
[web-protocol.md](https://github.com/komkovkonstantin/apptracer_flutter/blob/main/docs/web-protocol.md).

> Раньше пакет назывался `apptracer_flutter_sentry` и говорил по протоколу
> Sentry. Для web это оказалось неверно: там у Tracer есть собственный SDK,
> DSN обычному JS-проекту не выдаётся, и события идут в их собственный приём.
> Sentry-путь у Tracer существует, но для платформ без своего SDK и с DSN,
> который выдаётся при заведении проекта через VK Cloud. Переименован
> 26.08.2026, до первой публикации.

На **web** его подключает `apptracer_flutter_web` автоматически. На **десктопе
и Аврора ОС** регистрируйте сами:

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

void main() {
  TracerPlatform.instance = TracerHttpTracer(
    facts: PlatformClientFacts(),
    sdkVersion: '0.1.0',
  );
  Tracer.initialize(
    options: const TracerOptions(appToken: 'appToken из настроек проекта'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

`appToken` берётся в разделе **Настройки** проекта Tracer.

## Область применения

Только ошибки Dart. Нативные краши, ANR и зависания требуют нативного SDK: на
Android и iOS правильный выбор — нативные реализации, а на Аврора ОС вендор
предлагает C/C++-библиотеку и системные минидампы, до которых из Dart не
дотянуться. То есть на десктопе и Авроре пакет закрывает свою половину, но
заменой нативному SDK не становится.

## Статус

Формат принят живым сервером 26.08.2026: событие, собранное по этой схеме,
получило `200 {"success":true}` и появилось в консоли проекта. Что осталось
неизвестным — перечислено в
[web-protocol.md](https://github.com/komkovkonstantin/apptracer_flutter/blob/main/docs/web-protocol.md).
