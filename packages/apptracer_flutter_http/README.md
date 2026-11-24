# apptracer_flutter_http

Транспорт на чистом Dart к HTTP-приёму [Tracer](https://apptracer.ru) для
[`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) —
неофициальной интеграции Flutter.

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

На Web этот транспорт автоматически подключает `apptracer_flutter_web`. Он отправляет
ошибки Dart на `POST /api/crash/uploadBatch` с `appToken` JS-проекта.
[Формат запроса](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md)
восстановлен по запросу JavaScript SDK вендора.

Для поддерживаемых настольных конфигураций подключите необязательный стабильный
адаптер `apptracer_flutter_desktop`. Он использует официальный Sentry SDK с DSN
целевого проекта Tracer. Аврора ОС не поддерживается. См.
[матрицу платформ](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary).

Пример ручного подключения HTTP-транспорта для собственной интеграции:

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

void main() {
  TracerPlatform.instance = TracerHttpTracer(
    facts: PlatformClientFacts(),
    sdkVersion: '0.2.1',
  );
  Tracer.initialize(
    options: const TracerOptions(appToken: 'appToken из настроек проекта'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

## Область применения

HTTP-транспорт передаёт только ошибки Dart. Для нативных сбоев, ANR и зависаний нужен нативный SDK.

26.08.2026, до первой публикации, ручную реализацию протокола Sentry выделили
в отдельный пакет [apptracer_flutter_sentry](https://github.com/KonstantenKomkov/apptracer_flutter/blob/v1.5.0/packages/apptracer_flutter_sentry/README.md), впоследствии удалённый.

## Статус

`startCollection` поддерживает явное включение после отложенного bootstrap.
`stopAndClearCollection` сразу выключает сбор, очищает логи, custom keys и user ID
и очередь. После успешной очистки он возвращает `disabled`, при сбое — `error`.
По умолчанию очередь находится в памяти. Временные ошибки повторяются до пяти
попыток с таймаутом 10 секунд на запрос. Лимиты — 100 событий, 1 МиБ и 24 часа. Новое включение работает в том же процессе и создаёт новый HTTP-клиент;
данные, переданные при выключенном сборе, отбрасываются. Уже начатый запрос может
завершиться. Клиент, переданный через `httpClient`, транспорт не закрывает.

Формат принят живым сервером 26.08.2026: событие, собранное по этой схеме,
получило `200 {"success":true}` и появилось в консоли проекта. Что осталось
неизвестным — перечислено в
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).
