# Windows: соответствие PDB и локальная символизация

> Исторический протокол. Текущий native backend, lifecycle и клиентские карты
> проверены отдельно 24 октября 2026: [Windows local acceptance](windows-local-acceptance.md).


Продолжение №5, 23 октября 2026. Live-приёмка символов в Tracer и Dart AOT
остаётся отдельной открытой работой. Проверка ниже касается native runner x64.

`tool/check_windows_symbols.py` читает GUID/age из PE CodeView и Info stream PDB 7,
сверяет их с модулем runner в minidump, преобразует символы через
`dump_syms` и проверяет Breakpad MODULE. Затем `minidump-stackwalk 0.27.0`
восстанавливает стек из локального дерева символов. В crashing thread требуется
самый первый кадр `ApptracerNativeCrashProbe` с файлом `flutter_window.cpp`,
положительным номером строки и `trust=context`. Проба делает реальное
недопустимое обращение к памяти в отдельной noinline-функции runner.
Сканирование стека не засчитывается как подтверждение места падения.
Системные символы не скачиваются.

Источники инструментов CI: официальный
[Mozilla dump_syms 2.3.9](https://github.com/mozilla/dump_syms/releases/tag/v2.3.9)
и официальный
[rust-minidump 0.27.0](https://github.com/rust-minidump/rust-minidump/releases/tag/v0.27.0).
SHA-256 Windows архива dump_syms:
`bdf48486220708808a3e00aec78856ee1cce096189d47a1e2cb1c635f93bacc7`.
SHA-256 архива stackwalk:
`f6f2d7f1665843c4a270cd13fcd1458fed3b19013ea5dd909e12bc3599b959f4`.
Скачивание проверяет хеш до распаковки. Бинарники в Git не включаются.
Загрузка большого Aurora SDK ради vendor-копии утилиты в первом CI
`40008328779` остановилась на лимите времени; CI использует отдельный
архив исходного проекта Mozilla. Vendor uploader для будущей загрузки
в Tracer этим инструментом не заменяется.
Прогон `40009066200` подтвердил совпадение GUID/age и загрузку локальных
Breakpad-символов, но прежний `RaiseException` давал верхний кадр в KERNELBASE,
а собственный исходный кадр находился только сканированием стека. Поэтому
проба перенесена в отдельную функцию runner; требуется новая release-сборка.

Для воспроизведения на Windows после release-сборки:

```powershell
python tool/check_windows_native.py --app packages/apptracer_flutter_desktop/example/build/windows/x64/runner/Release --output build/windows-native/online.json --dump-dir build/windows-native/dumps
python tool/check_windows_symbols.py --app packages/apptracer_flutter_desktop/example/build/windows/x64/runner/Release --pdb packages/apptracer_flutter_desktop/example/build/symbols/native/apptracer_desktop_example.pdb --dump-dir build/windows-native/dumps --dump-syms path/to/dump_syms.exe --stackwalk path/to/minidump-stackwalk.exe --output build/windows-native/symbols
```

PDB должен быть от той же сборки. Если CMake указал другой каталог символов,
передать его фактический путь; workflow находит PDB в артефакте сборки.
Выходной каталог символизации должен быть новым. Сохраняются точные PE/PDB,
Breakpad symbol tree, исходные minidumps тестового приложения и JSON стеков.
`--dump-dir` сохраняет только дампы со сверенными CodeView и уникальным путём
собственного тестового запуска. Сценарий намеренно завершает процесс примера.

14 host Python-тестов прошли: повреждённый/фрагментированный PDB, GUID/age,
чужой модуль и кадр другого потока. Дополнительно на macOS проверена реальная
пара vendor `dump_syms.exe`/`.pdb` и соответствующий Breakpad MODULE.
Отдельное ревью проверило границы MSF-блоков, отсутствие сетевых symbol servers,
хеши инструментов и изоляцию артефактов.

## Подтверждённый Windows runtime

Release x64 из `1657514` собран в
[CI 40009549554](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40009549554),
включая disabled/deferred/smoke. После сборки
[CI 40010387576](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/40010387576)
успешно проверил native crash/restart, offline-restart после HTTP 503,
совпадение PE/PDB/minidump и локальную символизацию обоих дампов.

GUID/age: `bfd53960-ed86-4d36-aa78-d0fa6620a69d` / `1`.
SHA-256 EXE: `66e1b2cf31dc6773af064c782ffdcf6b97885f0bf198559c0d7808092f6b5883`;
PDB: `d2d6fbc1400f1c92a0a102d0599e038d32982470a3e16eb87761af4de4911f5a`.

Оба первых кадра: `(anonymous namespace)::ApptracerNativeCrashProbe()`,
`flutter_window.cpp:16`, `trust=context`. SHA-256 дампов:

```text
cc292345f75c0b5a1cdccde7fc950f98dd261be9210408fbb02768c93860080e
f48f33535fd8944ed75350ff09f9aa6240487a1bc692015bcfd0d3fb5e6bae19
```

Функция/строка подтверждены из crash context; это не результат сканирования
стека. Артефакт `windows-native-evidence` хранится 14 дней и содержит исходные
дампы, точные EXE/PDB, SHA-256/GUID/age, Breakpad symbol tree и JSON stackwalk.
Локальная копия артефакта: `build/windows-native-symbols-passed.zip`.
Системные и Flutter-кадры без их символов остаются ограничением; Windows Dart AOT,
live Tracer и stop/clear этой проверкой не закрываются.

Рабочий путь будущей загрузки описан в
[документации Tracer](https://apptracer.ru/doc/native-desktop/symbolization/):
vendor `symupload.py` с plugin token. Эта проверка ничего не загружает в Tracer.
