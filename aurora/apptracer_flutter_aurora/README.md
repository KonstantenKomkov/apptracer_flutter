# Tracer для Flutter на ОС Аврора

Экспериментальный платформенный пакет для Flutter Аврора 3.41.4 и Aurora Build Tools
5.2.1.200. Пакет регистрирует канал `apptracer_flutter/aurora` только в embedder
Авроры. Включение сбора в фасаде 2.0.0 зависит от проверки отзыва согласия.

## Собрать и установить пример

Из корня репозитория подготовьте лицензированную поставку Tracer Native 0.1.15.
Build Tools видит вложенный в пакет каталог SDK. Библиотека для целевой архитектуры
попадает в RPM приложения. [Условия использования](../../docs/legal.md).

```sh
python3 tool/prepare_aurora_sdk.py --destination aurora/apptracer_flutter_aurora/aurora/sdk
cd aurora/apptracer_flutter_aurora/example
flutter-aurora pub get
flutter-aurora analyze
flutter-aurora build aurora --release --target-platform aurora-arm64
adt device deploy --silent build/aurora/*/aurora-arm64/release/RPMS/*example-2*.rpm
```

Здесь `flutter-aurora` обозначает команду `bin/flutter` из комплекта ОМП.
Для Build Tools, установленных отдельно, добавьте к команде сборки
`--sdk-dir /путь/к/SDK`. Откройте пример на устройстве или запустите его так:

```sh
adt device exec runtime-manager-tool Control start ru.apptracer.apptracer_flutter_aurora_example
```

`AuroraTracer.probe()` загружает библиотеку из RPM и проверяет экспортируемые
функции. Результат содержит `sdkVersion` и `crashDumperConfigured`.
Значение `null` означает, что песочница закрыла доступ к настройке ядра.
При ошибке загрузки или отсутствующем экспорте метод возвращает
`PlatformException`. Пример работает без токена и разрешения Internet.

[Проверки на эмуляторе и в кабинете Tracer](../../docs/aurora-preparation.md#emulator-audit).
