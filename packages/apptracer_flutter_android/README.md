# apptracer_flutter_android

Реализация [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) под Android — неофициальной интеграции
Flutter с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Зависеть от этого пакета напрямую не нужно: его подтягивает
`apptracer_flutter`.

## Что он делает

Передаёт ошибки Dart в `ru.ok.tracer:tracer-crash-report`. Нативные краши, ANR
и метрику crash-free этот SDK считает сам — плагин добавляет только ту
половину, которую SDK не видит.

Ошибка Dart заворачивается в синтетический `Throwable`, чей `stackTrace`
собран из кадров Dart. Если отдавать вместо этого стек JVM, у всех ошибок Dart
в приложении окажутся одинаковые кадры, и Tracer схлопнет их в одну проблему.

## Подключение

SDK Tracer подключён здесь как `compileOnly`, поэтому его добавляет само
приложение — вместе с Gradle-плагином `ru.ok.tracer`, откуда берётся
`appToken`. См. [README](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/packages/apptracer_flutter/README.md#android).

Настройку SDK пакет ставит себе сам, без строчки в манифесте: рейт-лимит на
нефатальные (10 в час вместо жёстких 8 за сессию — а каждая ошибка Dart здесь
нефатальная). Кладёт её `TracerAutoConfigProvider`, который система создаёт
раньше провайдера Tracer. `Application`, реализующий `HasTracerConfiguration`,
эту конфигурацию отменяет — на такой случай в пакете есть
`TracerApplication`, от которого наследуются. Почему так и чем это рискованно —
в `TracerAutoConfig`.

О двух вещах плагин скажет в рантайме, а не промолчит:

* SDK Tracer отсутствует в classpath рантайма;
* Gradle-плагин `ru.ok.tracer` не применён — определяется по отсутствию
  сгенерированного ресурса `tracer_app_token`.

Требует `minSdk 21` — как и `ru.ok.tracer:tracer-commons`.
