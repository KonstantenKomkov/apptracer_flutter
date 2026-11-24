# apptracer_flutter — репозиторий

> **Это README монорепозитория: сборка, документация, внутреннее устройство.**
> Если вы хотите просто подключить пакет к своему приложению, вам не сюда, а в
> [packages/apptracer_flutter/README.md](packages/apptracer_flutter/README.md)
> — это же и есть страница пакета на pub.dev, и там есть быстрый старт.

Неофициальная интеграция Flutter с [Tracer](https://apptracer.ru) — сервисом
мониторинга ошибок от OK.TECH / VK.

> **Это не официальный SDK.** Пакет не связан с VK и OK.TECH, не одобрен и не
> поддерживается ими. Это независимая обёртка над публичными SDK вендора; сами
> SDK пакет не распространяет. С проблемами обращайтесь сюда, а не в поддержку
> Tracer.

English version: [README.en.md](README.en.md).

На macOS, Windows и Ubuntu подключите дополнительный desktop-пакет.
[Установка](docs/desktop-migration.md) и [проверенные среды](docs/platform-matrix.md#summary).

Нативные SDK Tracer не видят ошибок Dart: необработанное Dart-исключение не
роняет процесс и не попадает в JVM, поэтому мимо него проходят и
`UncaughtException`-обработчик, и обработчик сигналов, и ANR-watchdog. Для
Flutter-приложения это большинство ошибок. Репозиторий закрывает этот пробел.

Для ОС Аврора в версии 2.0.0 подключите отдельный адаптер для Flutter Аврора. Нативным отчётам нужен app token, ошибкам Dart также нужен DSN того же проекта. [Подключение и проверенные версии](docs/aurora-release.md).

## Структура репозитория

```
packages/
  apptracer_flutter/                    то, от чего зависит приложение
  apptracer_flutter_platform_interface/ модели, парсер стектрейсов, контракт
  apptracer_flutter_android/            мост на Kotlin к ru.ok.tracer
  apptracer_flutter_ios/                мост на Swift к OKTracer
  apptracer_flutter_web/                реализация для web
  apptracer_flutter_desktop/            optional официальный Sentry SDK для desktop;
                                        проверенные среды указаны в матрице платформ
  apptracer_flutter_http/               собственный приём Tracer на чистом Dart
aurora/
  apptracer_flutter_aurora/              исходный адаптер для Flutter Аврора
docs/
tool/
  bootstrap.sh              pub get во всех пакетах
  check.sh                  format + analyze + test + publish dry-run
  verify_build_id.sh        валит релиз, к которому не подходят символы Dart
  prepare_dart_symbols.sh   готовит символы Dart AOT для загрузчика Tracer
                            (загрузка проходит, но Tracer их не применяет —
                            см. symbolication.md, находка 2)
  upload_web_sourcemaps.sh  загрузка сорсмап, падающая при любой осечке
  elf_build_id.py           чтение GNU build id без зависимостей
```

## Документация

| Документ | На что отвечает |
|---|---|
| [docs/README.md](docs/README.md) | карта актуальных руководств и граница с историческими протоколами |
| [android-guide.md](docs/android-guide.md) | настройка Android, токены, native crashes и согласие |
| [apptracer_flutter_ios/README.md](packages/apptracer_flutter_ios/README.md) | настройка iOS, SPM/CocoaPods и dSYM |
| [web-protocol.md](docs/web-protocol.md) | web transport, offline-очередь, retry и их ограничения |
| [filtering.md](docs/filtering.md) | ручная отправка, breadcrumbs, beforeSend и custom context |
| [release-history.md](docs/release-history.md) | release-specific Runtime API и старые migration notes |
| [architecture.md](docs/architecture.md) | как разделены пакеты, как Dart взаимодействует с нативным кодом и почему desktop подключается отдельно |
| [live-verification-plan.md](docs/live-verification-plan.md) | пошаговый чек-лист проверки интеграции на живом проекте Tracer — начинать отсюда перед публикацией |
| [platform-matrix.md](docs/platform-matrix.md) | какой SDK, какой версии, с каким минимумом и что где покрыто — каждый факт со ссылкой на то, как он проверен |
| [symbolication.md](docs/symbolication.md) | что `--split-debug-info` делает со стектрейсом Dart и что с этим делать |
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
make analyze    # analyze всех пакетов, включая desktop
make test       # VM/Chrome-тесты и сводный coverage в build/coverage
make check      # format + analyze + test + coverage + publish dry-run
```

В `Makefile` лежат и команды запуска примера на каждой платформе
(`make example-android`, `example-ios`, `example-web`) — в них легко ошибиться:
на Android токен приходит из Gradle-плагина, а на iOS и web — через
`--dart-define`, причём у каждой платформы свой проект и свой токен. `.vscode/launch.json` повторяет тот же
набор для запуска из редактора. Если открыть `packages/apptracer_flutter/example`
отдельным проектом, там свои `Makefile` (`make android`) и `launch.json`.

## Лицензия

MIT, см. [LICENSE](LICENSE). SDK вендора лицензируются отдельно, см.
[docs/legal.md](docs/legal.md).
