# Подключение Авроры к кандидату 2.0.0

Для Flutter Аврора используется исходный пакет `apptracer_flutter_aurora 2.0.0`
с `publish_to: none`. В его метаданных указан платформенный ключ `aurora`,
который обрабатывает fork ОМП. Зафиксируйте ревизию checkout для сборки
приложения. Такая поставка позволяет положить лицензированный SDK в каталог
адаптера и собирать воспроизводимые RPM. Обычные мобильные и Web-приложения
продолжают зависеть от фасада. Desktop SDK и Aurora SDK проверялись в отдельных
графах зависимостей.

## До публикации общих пакетов

Положите checkout рядом с приложением. Подготовьте нативную поставку из корня
checkout следующей командой.

```sh
python3 tool/prepare_aurora_sdk.py --destination aurora/apptracer_flutter_aurora/aurora/sdk
```

Пример `pubspec.yaml` внешнего приложения для каталога checkout `../tracer`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  apptracer_flutter:
    path: ../tracer/packages/apptracer_flutter
  apptracer_flutter_aurora:
    path: ../tracer/aurora/apptracer_flutter_aurora

dependency_overrides:
  apptracer_flutter_platform_interface:
    path: ../tracer/packages/apptracer_flutter_platform_interface

aurora:
  permissions:
    - Internet
```

Добавьте ранний вызов из [runner примера](../aurora/apptracer_flutter_aurora/example/aurora/main.cpp).
Сохраните настройки сборки из [протокола символизации](aurora-symbols.md).
Запустите `flutter-aurora pub get`, затем соберите и установите подписанный RPM
по [инструкции примера](../aurora/apptracer_flutter_aurora/example/README.md).

## Порядок выпуска

1. Первым публикуется `apptracer_flutter_platform_interface 0.3.1`. В нём добавлены
   `auroraAccountScope` и отмена подготовленного старта. Уже опубликованная
   версия 0.3.0 этих API не содержит.
2. После этого публикуется фасад `apptracer_flutter 2.0.0` с зависимостью
   `^0.3.1`. Для финальной проверки разрешите обе зависимости с pub.dev,
   удалив локальный override и заменив путь к фасаду на `^2.0.0`.
3. Для Авроры сохраните path на проверенный checkout адаптера и подготовленный
   Tracer Native 0.1.15. Plugin token задаётся только при отправке символов на
   сборочной машине. Android, iOS, Web и HTTP используют совместимые уже
   опубликованные версии.

[Результаты целевой приёмки](aurora-live-acceptance.md) ·
[Управление согласием и настройка DSN](../aurora/apptracer_flutter_aurora/README.md).

## Проверка кандидата 24 ноября 2026

Внешнее приложение использовало отдельные копии исходных пакетов. В lockfile
фасад и адаптер имели версию 2.0.0, платформенный интерфейс — 0.3.1. Android
0.5.0, iOS 0.3.0, Web 0.3.0 и HTTP 0.3.0 разрешились из hosted registry.
Анализ и сборка прошли на Flutter Аврора. На эмулятор установлен подписанный
RPM с SHA-256 `ff6a7898f3eca7b0d98ba5577a99e89bdbd205d1062aff3f5b47d274154da692`.
В нём прошёл `facade-lifecycle` с отзывом запроса и переключением аккаунта.
В извлечённых файлах RPM проверено отсутствие трёх рабочих значений —
app token, plugin token и DSN тестового проекта.

Из чистых экспортов исходников вне Git checkout выполнен
`dart pub publish --dry-run` для платформенного интерфейса и фасада. Обе
проверки прошли с нулём предупреждений. Фасад получил одну подсказку о
локальном override неопубликованного интерфейса. После выхода 0.3.1 следует
повторить dry-run фасада с hosted-зависимостью. Для адаптера с
`publish_to: none` проверена сборка из исходного пакета, включая штатную
регистрацию платформы. Нативный SDK подготовлен отдельным шагом.
