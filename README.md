# apptracer_flutter

Неофициальная интеграция Flutter с [Tracer](https://apptracer.ru) — сервисом
мониторинга ошибок от OK.TECH / VK.

> **Это не официальный SDK.** Пакет не связан с VK и OK.TECH, не одобрен и не
> поддерживается ими. Это независимая обёртка над публичными SDK вендора; сами
> SDK пакет не распространяет. С проблемами обращайтесь сюда, а не в поддержку
> Tracer.

English version: [README.en.md](README.en.md).

Нативные SDK Tracer не видят ошибок Dart: необработанное Dart-исключение не
роняет процесс и не попадает в JVM, поэтому мимо него проходят и
`UncaughtException`-обработчик, и обработчик сигналов, и ANR-watchdog. Для
Flutter-приложения это большинство ошибок. Репозиторий закрывает этот пробел.

**Начинать отсюда:
[packages/apptracer_flutter/README.md](packages/apptracer_flutter/README.md).**

## Структура репозитория

```
packages/
  apptracer_flutter/                    то, от чего зависит приложение
  apptracer_flutter_platform_interface/ модели, парсер стектрейсов, контракт
  apptracer_flutter_android/            мост на Kotlin к ru.ok.tracer
  apptracer_flutter_ios/                мост на Swift к OKTracer
  apptracer_flutter_web/                реализация для web
  apptracer_flutter_http/             транспорт по протоколу Sentry на чистом Dart
docs/
tool/
  bootstrap.sh              pub get во всех пакетах
  check.sh                  format + analyze + test + publish dry-run
  verify_build_id.sh        валит релиз, к которому не подходят символы Dart
  prepare_dart_symbols.sh   готовит символы Dart AOT для загрузчика Tracer
  upload_web_sourcemaps.sh  загрузка сорсмап, падающая при любой осечке
  elf_build_id.py           чтение GNU build id без зависимостей
```

## Документация

| Документ | На что отвечает |
|---|---|
| [live-verification-plan.md](docs/live-verification-plan.md) | пошаговый чек-лист проверки интеграции на живом проекте Tracer — начинать отсюда перед публикацией |
| [platform-matrix.md](docs/platform-matrix.md) | какой SDK, какой версии, с каким минимумом и что где покрыто — каждый факт со ссылкой на то, как он проверен |
| [web-protocol.md](docs/web-protocol.md) | как Tracer на самом деле принимает события из браузера — и почему нынешняя web-реализация под вопросом |
| [symbolication.md](docs/symbolication.md) | что происходит с обфусцированным стектрейсом Dart и что с этим делать |
| [privacy.md](docs/privacy.md) | что именно уходит с устройства — из этого пакета и из SDK вендора |
| [legal.md](docs/legal.md) | лицензии, наименование и единственный вопрос, который надо закрыть до публикации |
| [status.md](docs/status.md) | что доказано, а что нет |
| [questions-for-vendor.md](docs/questions-for-vendor.md) | что спросить у поддержки Tracer и что изменит каждый ответ |
| [publishing.md](docs/publishing.md) | порядок релиза и чек-лист перед публикацией |
| [contributing.md](docs/contributing.md) | как работать в этом монорепозитории |

## Разработка

Пакеты зависят друг от друга по версии, а локально связаны через
`pubspec_overrides.yaml`, который `dart pub publish` игнорирует.

```sh
make            # список всех целей
make bootstrap  # pub get во всех пакетах
make check      # analyze + test + publish dry-run
```

В `Makefile` лежат и команды запуска примера на каждой платформе
(`make example-android`, `example-ios`, `example-web`) — в них легко ошибиться:
на Android токен приходит из Gradle-плагина, на iOS через `--dart-define`, а
web вместо токена нужен DSN Sentry. `.vscode/launch.json` повторяет тот же
набор для запуска из редактора. Если открыть `packages/apptracer_flutter/example`
отдельным проектом, там свои `Makefile` (`make android`) и `launch.json`.

## Лицензия

MIT, см. [LICENSE](LICENSE). SDK вендора лицензируются отдельно, см.
[docs/legal.md](docs/legal.md).
