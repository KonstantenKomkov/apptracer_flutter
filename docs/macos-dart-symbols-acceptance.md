# macOS: локальная символизация Dart AOT

23 октября 2026 проверена самостоятельная часть №5: точная обфусцированная
release-сборка, три Dart-события через официальный SDK и локальное восстановление
исходных функций/строк. Это loopback-проверка; в Tracer события не отправлялись.
Серверная native macOS символизация остаётся принятым ограничением из
[предыдущего протокола](macos-symbols-acceptance.md).

## Результат

Flutter 3.47.4 / Dart 3.13.3, sentry_flutter 9.30.1, macOS 27 arm64.
Исходники примера взяты из `97ffcc2`; сборка выполнена в отдельной копии, прежние
бинарники и символы live-приёмки не заменялись. Собраны arm64 и x86_64; выполнен
только arm64. Для обеих архитектур UUID `.symbols` совпадает с `App.framework`.

UUID arm64: `36EE816C-8BD8-E9F1-C216-7A45CABF3676`.
SHA-256 универсального `App.framework/App`:
`49329c1ef19b845f6946b9a8b9240b413ddb6a5da0b4391ebd5b3a000075cd33`.
SHA-256 `app.darwin-arm64.symbols`:
`14ac22599014297e19682371d9b86273f242b63a8203a0a5c26561f79c1c35d3`.

| Ошибка | Первый virtual PC | Результат `atos` |
| --- | --- | --- |
| handled | `0x2d7c7b` | `handled (#2)`, `main.dart:45` |
| FlutterError | `0x13af3f` | `flutterError`, `main.dart:55` |
| async | `0x13ab0f` | `asyncError.<anonymous closure>`, `main.dart:64` |

Получены ровно три события с userId, breadcrumb и меткой запуска; UUID в исходном
стеке, debug image SDK, символах и приложении совпадают. Сохранён исходный текст
из `contexts.apptracer.dart_stack_trace`, включая заголовок, absolute/virtual PCs.
Все кадры переданы `atos`; наличие имени и строки проверяется для первого кадра
каждого сценария. Полная символизация всех системных кадров не обещается.

**Ограничение Flutter CLI:** `flutter symbolize` этой версии завершился кодом 1
для всех трёх исходных стеков: `Cannot locate isolate instructions section in snapshot`.
Стек использует `_kDartSnapshotText`; декодер `native_stack_traces 0.6.1` пытается
найти прежнюю секцию isolate instructions. Работающий локальный путь — `atos`
по virtual PC с точным Mach-O `.symbols`. Исходный стек и SDK не модифицируются.
Это результат указанного toolchain, а не утверждение о всех версиях Flutter.

## Воспроизведение

В отдельном checkout (чтобы сохранить артефакты предыдущей сборки):

```sh
cd packages/apptracer_flutter_desktop/example
flutter build macos --release --obfuscate --split-debug-info=build/dart-symbols
cd ../../..
python3 tool/check_macos_dart_symbols.py \
  --app packages/apptracer_flutter_desktop/example/build/macos/Build/Products/Release/apptracer_desktop_example.app \
  --symbols packages/apptracer_flutter_desktop/example/build/dart-symbols \
  --output build/macos-dart-symbols
```

Выходной каталог должен быть новым. Проверка сохраняет ZIP приложения, `.symbols`
обеих архитектур, SHA-256/UUID, реальные envelopes, исходные и восстановленные
стеки, результат стандартного `flutter symbolize` и JSON отчёт. Локальные
артефакты первого прогона: `build/macos-dart-symbols/evidence/`. Это игнорируемые
release-артефакты; исходные пути и символы в Git не добавляются.

Для отдельного сохранённого стека:

```sh
python3 tool/symbolize_macos_dart.py \
  --stack build/macos-dart-symbols/0-raw.txt \
  --symbols build/macos-dart-symbols/symbols/app.darwin-arm64.symbols \
  --app-image path/to/exact.app/Contents/Frameworks/App.framework/App
```

До вызова `atos` проверяются архитектура, три UUID и согласованность
`absolute PC - isolate_dso_base == virtual PC`. Нет символов, потерян заголовок,
чужая сборка/архитектура или повреждённый адрес — ошибка, без попытки расшифровать
чужими символами. Три новых теста покрывают эти отказы; всего 10 Python-тестов
приёмников/парсеров прошли. Отдельное ревью проверило сохранение исходного стека,
отсутствие credentials, соответствие артефактов и границы результата.

Workflow [macos-symbols.yml](../.github/workflows/macos-symbols.yml) повторяет
сборку и проверку на macOS 15 arm64, сохраняет артефакт на 14 дней.
[Hosted-прогон 40007734317](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40007734317)
на `e76bf55` успешно выполнил все шаги, включая реальную расшифровку трёх событий
и загрузку артефакта `macos-dart-symbols`. Это отдельная CI-сборка со своими UUID;
хеши локального прогона выше на неё не переносятся.

Команды сборки соответствуют [документации Flutter](https://docs.flutter.dev/deployment/obfuscate).
Для Windows способ нельзя предполагать тем же: документация текущего Flutter
описывает PDB на Windows x64 и отсутствие поддержки PDB у `flutter symbolize`.
Фактический формат выбранного Windows toolchain и его расшифровку нужно
проверить отдельно в №5. Live AOT-приёмка в Tracer остаётся в №11.
