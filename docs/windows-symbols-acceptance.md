# Windows: соответствие PDB и локальная символизация

Продолжение №5, 23 октября 2026. Live-приёмка символов в Tracer и Dart AOT
остаётся отдельной открытой работой. Проверка ниже касается native runner x64.

`tool/check_windows_symbols.py` читает GUID/age из PE CodeView и Info stream PDB 7,
сверяет их с модулем runner в minidump, преобразует символы через vendor
`dump_syms` и проверяет Breakpad MODULE. Затем `minidump-stackwalk 0.27.0`
восстанавливает стек из локального дерева символов. В crashing thread требуется
кадр `FlutterWindow` с файлом `flutter_window.cpp` и положительным номером строки.
Метод получения кадра (`trust`) сохраняется в JSON; найденный сканированием кадр
не объявляется доказанным CFI-unwind. Системные символы не скачиваются.

Источники инструментов: `dump_syms.exe` из уже проверенной поставки Tracer
0.1.15, закреплённой в `tool/aurora/sdk.lock.json` (используется только утилита,
не Aurora runtime), и официальный
[rust-minidump 0.27.0](https://github.com/rust-minidump/rust-minidump/releases/tag/v0.27.0).
SHA-256 архива stackwalk:
`f6f2d7f1665843c4a270cd13fcd1458fed3b19013ea5dd909e12bc3599b959f4`.
Скачивание проверяет хеш до распаковки. Бинарники в Git не включаются.

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
хеши инструментов и изоляцию артефактов. Целевой runtime результат фиксируется
отдельно после Windows CI; одни host-тесты не закрывают задачу.

Рабочий путь будущей загрузки описан в
[документации Tracer](https://apptracer.ru/doc/native-desktop/symbolization/):
vendor `symupload.py` с plugin token. Эта проверка ничего не загружает в Tracer.
