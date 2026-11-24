# Символы release-сборки для Авроры

В [примере](../aurora/apptracer_flutter_aurora/example/aurora/CMakeLists.txt)
runner и платформенный плагин собираются с DWARF. В
[спецификации RPM](../aurora/apptracer_flutter_aurora/example/aurora/rpm/ru.apptracer.apptracer_flutter_aurora_example.spec)
сохранён исходный build-id. Для своего приложения перенесите параметры из примера
и сохраните файлы CMake и spec от перегенерации. RPM может удалять отладочную
информацию из поставляемого ELF. В каталоге сборки остаются оригиналы до strip.

Из корня репозитория укажите каталог release с одним подписанным RPM.
Для команды нужны Python 3 с `requests`, `file` и `bsdtar`.

```sh
release=/путь/к/example/build/aurora/bt_5.2.1/aurora-arm64/release
python3 tool/aurora/symbols.py "$release" --sdk build/aurora-sdk/0.1.15 --out build/aurora-symbols
python3 tool/aurora/symbols.py "$release" --sdk build/aurora-sdk/0.1.15 --out build/aurora-symbols --upload
```

Первая команда извлекает модули из подписанного RPM и сверяет их полные build-id
с оригиналами. Штатный `symupload.py` строит дерево символов. Каталог с SHA-256
RPM содержит карты и `manifest.json` с хешами поставляемых ELF. Сохраняйте
манифест, карты и соответствующий RPM как артефакты одной сборки.
`--library /путь/к/библиотеке.so` добавляет другой модуль из каталога lib этого
RPM при наличии DWARF. Для отправки введите plugin token в скрытом приглашении
или задайте его процессу через `TRACER_AURORA_PLUGIN_TOKEN`.
[Инструкция производителя](https://apptracer.ru/doc/native-aurora/symbolization/).

В [тестовом RPM](../tool/aurora/acceptance/README.md) запустите фазу
`facade-symbols`. Она вызывает контролируемое падение в собственном runner.
До следующего запуска скопируйте `~/.cache/ru.apptracer/apptracer_flutter_aurora_example/minidump`
с тестового эмулятора в закрытый каталог. Повторите первую команду с параметром
`--minidump /путь/к/minidump`, затем выполните `facade-replay` и откройте
последнюю карточку SIGTRAP. SHA-256 файлов на устройстве можно независимо
сверить с манифестом командой `sha256sum` для каждого пути из поля `path`.

## Результаты 24 ноября 2026

На эмуляторе 5.2.1.200 aarch64 установлен RPM с SHA-256
`5b078862be0b650b3a55ad485fd0f9972149a9328a0ef3ae025c32d4d05fb3b2`.
В подписанном RPM, оригиналах до strip и минидампе совпали build-id.
SHA-256 установленного runner и плагина совпал с байтами в RPM.

| Модуль | ELF build-id | Проверка |
| --- | --- | --- |
| runner | `69f2f766a89e5b8662c314fa4047aff937f5058b` | В Tracer видна функция `AuroraAcceptanceCrash` и строка `main.cpp:45` |
| плагин | `c412fc7caba6174cc9332c64c0508d1e676fc7a7` | Модуль в дампе и карта с исходными строками. В данном сценарии падал runner |

Символизация системных библиотек и Flutter Engine зависит от DWARF производителя.
Для Dart проверена отдельная подписанная release-сборка Flutter Аврора 3.41.4
с `--split-debug-info=build/dart-symbols`. Фаза `dart-symbols` записала
`throwFacadeError` и `main.dart:186` в `acceptance-aot-stack` в закрытом каталоге
данных примера. В этой версии fork флаг принимается, но вызов `gen_snapshot`
в `_buildSnapshot` передаёт лишь `--strip` и не задаёт сохранение отдельного
DWARF-файла. Подтверждены исходные кадры обычных Dart-исключений в сборке без
обфускации. Восстановление Dart-кадров из нативного минидампа и поддержка
обфусцированных AOT-стеков остаются за пределами проверенной конфигурации.
