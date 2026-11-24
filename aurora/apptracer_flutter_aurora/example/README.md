# Проверить Tracer на Авроре

Подготовьте Tracer Native 0.1.15 и соберите пример с Flutter Аврора 3.41.4.
Команды выполняются из корня checkout. Для рабочего SDK с обычным расположением
Build Tools можно опустить параметр `--sdk-dir`.

```sh
python3 tool/prepare_aurora_sdk.py --destination aurora/apptracer_flutter_aurora/aurora/sdk
cd aurora/apptracer_flutter_aurora/example
flutter-aurora pub get
flutter-aurora analyze
flutter-aurora build aurora --release --target-platform aurora-arm64 --sdk-dir /путь/к/AuroraSDK
adt device deploy --silent build/aurora/*/aurora-arm64/release/RPMS/*example-2*.rpm
adt device exec 'runtime-manager-tool Control start ru.apptracer.apptracer_flutter_aurora_example'
```

1. Откройте пример и разрешите доступ в Интернет. Начальный экран показывает версию SDK и состояние `disabled`.
2. Введите app token и необязательный Sentry DSN своего проекта, задайте область согласия и нажмите «Включить сбор». Пример держит параметры в памяти.
3. Нажмите «Отправить ошибку Dart». Сверьте квитанцию на экране и последнее событие ERROR в кабинете. Для отчёта нужен DSN.
4. Для проверки нативного отчёта нажмите «Проверить нативное падение» и подтвердите SIGABRT. После перезапуска введите прежние app token и область, включите восстановление отчётов и нажмите «Включить сбор». Найдите в кабинете NATIVE с ключом `sample=aurora`.
5. «Остановить и очистить» отзывает согласие и очищает очередь. После завершения можно начать сбор для другого аккаунта.

## Повторить приёмку release

[Фазы автоматической проверки](../../../tool/aurora/acceptance/README.md) собираются
в отдельном каталоге. Для символьного архива сохраните подписанный RPM,
оригиналы ELF до strip и дерево с манифестом в каталоге SHA-256 этого RPM.
[Сборка и сверка символов](../../../docs/aurora-symbols.md).

GitHub Actions запускает проверки SDK, ABI и нативного кода на Ubuntu. В CI
репозитория пока нет зарегистрированного runner с Flutter Аврора, Build Tools,
эмулятором и настроенной подписью RPM. Протокол выше выполняется на такой
машине. Для обычных PR ingest- и plugin-токены не нужны.
