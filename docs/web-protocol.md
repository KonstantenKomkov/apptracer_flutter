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

## Что осталось неизвестным

* Что отвечает сервер на принятый пакет и как выглядит отказ. Локальная ловушка
  отвечала `{"success":true}`, и SDK этим удовлетворился, но это наш ответ, а не
  вендорский.
* Нужен ли `trackSession` для того, чтобы событие приняли, или он только для
  метрики crash-free.
* Как передаются `issueKey` и кастомные ключи: в снятом запросе их не было,
  потому что проба их не задавала.

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

Чего пока нет: breadcrumbs (вендор носит их отдельным полем `logsFile`, формат
которого не снят) и `trackSession` (метрика crash-free).

## Почему это важно

Под JavaScript у Tracer есть собственный SDK, и вендор рекомендует именно его.
Sentry-путь остаётся для платформ, где своего SDK нет, — но там нужен DSN из
VK Cloud, а у обычного JS-проекта его нет. Поэтому web ходит в тот же приём, что
и SDK вендора.
