# Как Tracer принимает события из браузера

Восстановлено 26.08.2026 из `@apptracer/sdk` 2.6.9, распакованного с npm, и из
публичной документации вендора. Нужно потому, что web-реализация пакета
построена на предположении о приёме по протоколу Sentry, а оно не подтвердилось:
DSN в настройках JS-проекта не выдаётся, и в SDK вендора никакого Sentry нет.
Это относится именно к web: для платформ, под которые у Tracer нет своего SDK,
Sentry-приём существует и документирован, а DSN выдаётся, если завести проект
через VK Cloud.
См. [design-decisions.md](design-decisions.md) и [status.md](status.md).

## Что установлено

**Адрес и авторизация.** Тот же хост и тот же токен, что на Android:

```
POST https://sdk-api.apptracer.ru/api/crash/uploadBatch
  ?crashToken=<appToken>
  &compressType=GZIP|NONE
```

`apiHost` в конфигурации SDK подменяет только хост. Другие эндпоинты того же
API: `/api/crash/trackSession`, `/api/perf/upload`.

**Тело.** `gzip(JSON.stringify(<массив событий>))`, отправляется как blob.
Когда сжатие недоступно, тело уходит как есть, а `compressType=NONE` —
то есть поддержать надо оба варианта.

**Событие.** Собирается со следующими полями (имена из кода SDK):

| Поле | Смысл |
|---|---|
| `error`, `errorStack` | сама ошибка и её стектрейс |
| `causeSimpleValue` | причина, если задана |
| `versionName`, `versionCode` | версия приложения; `versionCode` выводится из `versionName`, если тот вида `prefix-major.minor.patch-postfix` |
| `severity` | одно из `fatal`, `error`, `warning`, `notice`, `debug` — совпадает с нашим `TracerSeverity` |
| `keys` | кастомные ключи |
| `issueKey` | ключ группировки, как на Android и iOS |
| `crashIdSource` | источник идентификатора проблемы |
| `userId` | идентификатор пользователя |
| `component` | компонент |
| `type` | `NON_FATAL` для ручной регистрации |
| `errorEventType` | `manual` для ручной, иначе — вид перехваченного события |
| `logsFile` | лог события, base64 |
| свойства user-agent | браузер, версия, семейство ОС |

**Пакетирование.** События копятся до `CRASH_BATCH_SIZE` или до
`UPLOAD_BATCH_TIMEOUT_MS`, затем уходят одним запросом. Отдельно
обрабатывается уход со страницы (`beforeUnload` в параметрах запроса).

## Снятый живьём запрос

26.08.2026 SDK вендора запущен в браузере с `apiHost`, направленным на локальный
сервер, который печатает пришедшее. Ниже — дословно то, что он отправил.

**Отчёт об ошибках.**

```
POST https://sdk-api.apptracer.ru/api/crash/uploadBatch
     ?crashToken=<appToken>&compressType=GZIP&sdkVersion=2.6.9
Content-Type: application/octet-stream
```

```json
[
  {
    "type": "NON_FATAL",
    "format": "JS_STACKTRACE",
    "severity": "NON_FATAL",
    "uploadBean": {
      "environment": "dev",
      "deviceId": "5dc6e005-…",
      "sessionUuid": "a3e9640e-…",
      "versionName": "1.0.0",
      "versionCode": 1,
      "properties": {
        "timestamp": 1787774411024,
        "date": "2026-08-26T23:00:11+03:00",
        "host": "127.0.0.1:8798",
        "errorEventType": "manual",
        "screenWidth": 800,
        "screenHeight": 600,
        "screenOrientationAngle": 0,
        "documentVisibilityState": "visible",
        "tracerSdkVersion": "2.6.9"
      }
    },
    "stackTrace": "Error: сообщение\n    at initAll (http://…/index.html:41:25)"
  }
]
```

Необработанная ошибка отличается только тремя полями: `type` и `severity`
становятся `CRASH`, а `errorEventType` — `error` вместо `manual`.

**Сессия.** Отдельным запросом, обычным JSON, без сжатия:

```
POST /api/crash/trackSession?crashToken=<appToken>&sdkVersion=2.6.9
Content-Type: application/json

{"versionName":"1.0.0","versionCode":"1","deviceId":"…",
 "sessions":[{"sessionUuid":"…","versionName":"1.0.0","versionCode":"1",
              "status":"RUNNING","environment":"dev"}]}
```

**Адрес.** `initUrl` собирает его как `"https://" + apiHost + apiUrl`, то есть
`apiHost` — голый хост без схемы, а протокол всегда https. Значение по
умолчанию — `sdk-api.apptracer.ru`.

**Сжатие необязательно.** `compressType=NONE` — штатный путь SDK, когда gzip
недоступен. Для Dart под web это существенно: `dart:io` там нет.

**Пакетирование.** До 100 событий или 15 секунд, первая отправка через секунду
после старта; на `beforeunload` пакет уходит немедленно.

## Что было неизвестным — и что выяснилось 27.08.2026

Три вопроса из этого раздела закрыты: два прочитаны в бандле самого SDK
(`lib/main/index.mjs` из `@apptracer/sdk` 2.6.9 — он не минифицирован до
неузнаваемости, классы `LogsData` и `StackTraceUploader` читаются), один снят
живой пробой.

**Ответ сервера ничего не подтверждает, кроме токена.** Три запроса в живой
JS-проект:

| Тело | Ответ |
|---|---|
| не JSON вовсе | `200 {"success":true}` |
| JSON не той формы | `200 {"success":true}` |
| верное тело, неверный токен | `400 {"errorCode":"INVALID_PARAMETERS","code":1,"message":"Required app info is missing. Check used token."}` |

То есть `{"success":true}` означает «токен валиден и запрос дошёл», а не
«событие принято». Отличить проглоченный пакет от разобранного клиент не может,
и никакая проверка ответа этого не заменит — только событие в консоли.

**`trackSession` для приёма событий не нужен.** Это отдельный модуль
`SessionUploader` со статусами `RUNNING`, `CRASH`, `BLANK`, живущий сам по себе;
на `/api/crash/uploadBatch` он не влияет. Нужен он для метрики crash-free, и
пакет его не шлёт.

**Breadcrumbs — поле `logsFile`, base64 от текста лога.** Формат строки, из
`LogsData.add`:

```
#<индекс> <epoch millis> | <текст>\n
```

Весь лог — конкатенация строк, кап 64 000 байт, при переполнении выбрасываются
самые старые строки, но никогда последняя. Это ровно тот формат, на который
ругается лог-таблица консоли: `Match line error, expected format: #0 timestamp
| text`. Реализовано в `TracerLogBuffer`, формат закреплён тестами; проверено
живьём — консоль показывает breadcrumb и трейс двумя отдельными записями.

**Кастомные ключи надо слать дважды.** Вендорский SDK кладёт их в
`uploadBean.tags` списком строк `ключ=значение`. Проба показала, что вкладка
«Данные» их оттуда не читает: событие с ключами только в `tags` пришло без них,
событие с ключами ещё и в `properties` — с ними. Пакет шлёт оба вида: то, что
рендерится, и то, что шлёт вендор.

**`issueKey` — свойство `properties.issueKey`**, и консоль его показывает.
`userId` там же, строкой.

## Что уже сделано

Реализовано в `apptracer_flutter_web` 26.08.2026: `TracerHttpTracer` шлёт
`POST /api/crash/uploadBatch` с `compressType=NONE` — сжатие не обязательно, а
`dart:io` под web нет. Формат тела покрыт юнит-тестами по снятому запросу.

**Формат принят живым сервером.** Пробное событие, собранное по этой схеме и
отправленное в реальный JS-проект, получило `200 {"success":true}` и появилось
в консоли.

**Кадры надо отдавать в форме JavaScript.** Две пробы, отличавшиеся только
видом стектрейса, легли по-разному:

| Вид кадров | Что показала консоль |
|---|---|
| `    at name (http://host/main.dart.js:98765:12)` | разобранный стек: `at` убран, кадры разложены построчно |
| `#0      name (package:example/main.dart:190:21)` | текст как есть, `Stacktrace not available` в списке |

Для нас это не требует ничего: под `dart2js` стектрейс и так приходит в первой
форме, а транспорт передаёт его дословно. Но при попытке «улучшить» формат это
свойство легко сломать.

27.08.2026 добавлены breadcrumbs (`logsFile`), кастомные ключи и `userId` —
до этого `recordLog`, `setCustomKey`, `removeCustomKey` и `setUserId` в
`TracerHttpTracer` были пустыми методами, то есть на web этих данных не было
вовсе. Чего по-прежнему нет: `trackSession`, то есть метрики crash-free.

## Почему это важно

Под JavaScript у Tracer есть собственный SDK, и вендор рекомендует именно его.
Sentry-путь остаётся для платформ, где своего SDK нет, — но там нужен DSN из
VK Cloud, а у обычного JS-проекта его нет. Поэтому web ходит в тот же приём, что
и SDK вендора.
