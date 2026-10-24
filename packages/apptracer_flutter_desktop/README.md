# apptracer_flutter_desktop

[English](README.en.md)

Экспериментальный адаптер `TracerPlatform` на **официальном sentry_flutter 9.30.1**.
Dart-код предназначен для Windows/macOS/Ubuntu Linux. Для Windows 11 x64
проверены native backend, stop/clear, offline/retry, исходные Dart/native кадры,
доставка в Tracer и два внешних потребителя. Пакет ещё не опубликован;
[проверенная область и ограничения](../../docs/windows-local-acceptance.md).

Ubuntu 22.04 x86_64 использует официальную native-очередь для сериализованных SDK
Dart-событий и native-отчётов. Linux требует `SENTRY_NATIVE_BACKEND=native`
и исполняемый `lib/sentry-crash` в bundle (см. build helper примера).
Linux CMake добавляет в crash daemon восстановление native-файлов/строк по
совпадающим Breakpad-картам в `lib/symbols`. Build helper создаёт их из DWARF
этой же сборки; Dart AOT-карты туда не включаются. Пустые или несовпадающие карты
не мешают доставке исходного отчёта. Механизм привязан к sentry-native 0.16.6.
Для Dart AOT адаптер автоматически читает отдельную компактную карту из
`lib/apptracer-dart-symbols/<build-id>.json.gz` и заполняет function/file/line
перед сериализацией официальным SDK. Проверяются build ID стека, загруженного ELF
и карты; исходный стек сохраняется. Helper примера создаёт карту по умолчанию.
Она раскрывает имена функций и пути файлов, ослабляя обфускацию; для сборки без неё
используйте `TRACER_BUNDLE_DART_SYMBOLS=0 bash tool/build_linux_desktop.sh`.
Полный DWARF и исходный код в bundle не добавляются.
После согласия добавляются distro/kernel, архитектура и DMI model/vendor;
hostname, serial и machine-id не читаются. В Tracer эти поля видны в
«Данные → Other/Context». Стандартные виджеты ОС/устройства и подпись
`Stacktrace not available` имеют ограничения C/C++-приёмника сервиса;
подпись может оставаться даже при наличии исходных файлов и строк.
Stop отзывает replay и отменяет собственные
отправки; повторный старт требует нового процесса. Реальная доставка,
исходные кадры и группировка проверены отдельно на Ubuntu 22.04.5 x64 VM;
[среды, результаты и команды](../../docs/linux-preparation.md).

Для внешнего Ubuntu-приложения выполнить
[настройку CMake и упаковки](../../docs/desktop-migration.md#ubuntu-linux-consumer):
заранее задать bundle install prefix, исключить неиспользуемый JNI runtime,
установить `sentry-crash` как PROGRAMS. Одной зависимости в pubspec недостаточно.
Проверены glibc 2.35, GTK 3 и X11; для остановки uploader нужны kernel ≥5.3 и `/proc`.
Переносить весь bundle с правами исполнения; Flutter/Java на целевой машине не нужны.
Символы создаются инструментами из той же ревизии репозитория; plugin token для
клиентских карт не требуется. Опубликованный facade 0.2.1 ещё не содержит
исправление имени `FlutterError` при обфускации; для него использовать текущий
facade по path/git до выпуска 0.2.2.

Подключить этот пакет по path/git вместе с `apptracer_flutter`. На Windows/macOS/Linux адаптер
регистрируется автоматически; при явном выборе backend до bootstrap:

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';

Future<void> main() async {
  TracerPlatform.instance = SentryDesktopTracer();
  await Tracer.initialize(
    options: const TracerOptions(
      dsn: String.fromEnvironment('TRACER_MACOS_SENTRY_DSN'),
      release: '1.0.0',
      environment: 'test',
      dist: '1',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

DSN берётся из проекта Tracer, созданного через VK Cloud. На Windows использовать
его DSN вместо macOS-переменной. App token не заменяет DSN; plugin token в приложение
не передавать. HTTPS обязателен, HTTP разрешён только для loopback-приёмника при
локальной проверке. Пустая/неверная конфигурация оставляет сбор выключенным.

`Tracer` владеет appRunner, зоной, Dart/Flutter-перехватчиками и пользовательскими
фильтрами. Адаптер не вызывает appRunner. Не вызывать `Sentry.init`/`SentryFlutter.init`
или методы записи Sentry самостоятельно: экземпляр SDK принадлежит этому адаптеру;
существующий чужой SDK не переинициализируется и не закрывается.

Включены только необходимые binding, release, native SDK и debug-image integrations.
Автоматические sessions, performance, profiling, replay, logs/metrics, screenshots,
view hierarchy, breadcrumbs и дополнительные Dart error handlers отключены.
События, созданные вне `Tracer`, отбрасываются на Dart-границе SDK.

`beforeSend` применяется до преобразования события; удалённые ключи и breadcrumbs
не восстанавливаются из глобального Scope. Исходный Dart-стек сохраняется в
`contexts.apptracer.dart_stack_trace`; `issueKey` передаётся как fingerprint.
Fatal — классификация вызывающего кода, не доказательство смерти процесса.
Отображение и группировка этих полей в Tracer требуют отдельной live-проверки.

Native crash минует Dart callback. В него могут попасть ранее записанные логи,
ключи, userId и системные сведения нативного SDK. `beforeSend` не является фильтром
нативного падения; не записывайте туда значения, которые нельзя отправлять.

Серверная символизация native macOS-стеков в Tracer **не поддерживается в
проверенной интеграции** (sentry_flutter 9.30.1 / Cocoa 8.58.4, DESKTOP-проект).
SIGABRT доставляется, но файлы/строки не восстанавливаются после загрузки
совпадающих desktop-символов; Apple dSYM endpoint отклоняет DESKTOP-проект.
Локальное восстановление по dSYM работает. Обычные символические Dart-стеки
передаются отдельно. [Результаты проверки](../../docs/macos-symbols-acceptance.md).

## Ограничения жизненного цикла

- Создание адаптера, disabled и deferred bootstrap не запускают SDK.
- `startCollection` запускает официальный SDK; ошибки инициализации дают `error`
  и не препятствуют запуску приложения.
- На macOS stop сразу закрывает Dart-приём, запрещает новые native-запросы,
  отменяет начатые и закрывает SDK. Подтверждение ждёт остановки сетевой сессии;
  ошибка остаётся `error`, успешный stop возвращает `restartRequired`.
- Повторный старт после попытки native init запрещён в текущем процессе, включая
  создание нового адаптера. Для возобновления нужен новый процесс.
- На macOS `stopAndClearCollection` удаляет очередь, crash-файлы, SDK identity и
  сохранённый scope в собственном каталоге, а также диагностический `async.log`.
  На месте очереди остаётся пустой файл, запрещающий позднюю запись SDK.
  После native init результат — `restartRequired`, до него — `disabled`.
- `preservePreviousReports: false` (по умолчанию) удаляет очередь до native init.
  `true` сохраняет отчёты обычного завершённого/упавшего процесса. Предшествующий
  stop всегда отменяет восстановление, даже при `true` в следующем процессе.
  Явный stop до первого старта SDK также отзывает старую очередь.
- Уже переданные серверу байты нельзя отозвать. Stop не удаляет данные с сервера.
  Очистка охватывает новый каталог `Library/Application Support/apptracer_desktop/<bundle-id>/v1`
  (в sandbox — внутри контейнера). Старые каталоги предыдущего адаптера и отдельного
  Sentry SDK не импортируются и автоматически не удаляются; миграционную очистку
  должен планировать владелец приложения. Системные crash-логи macOS не удаляются.
- Windows использует официальный native backend (`SENTRY_NATIVE_BACKEND=native`)
  и собственный `%LOCALAPPDATA%/apptracer_desktop/<exe-name>/v1`. Default purge,
  stop/clear и отзыв replay реализованы. После native init нужен новый процесс.
  Junction/reparse-point в предках storage отвергаются; второй владелец очереди
  получает безопасный отказ. Старые SDK-кэши не импортируются и не удаляются.
  Переносить весь Release, включая daemon/helper и app-local MSVC DLL.
  Опциональные точные Dart/PDB-карты раскрывают function/file/line; их можно
  не создавать. Plugin token для карт не нужен. [Команды](../../docs/windows-preparation.md).

Нативный мост использует публичные API Cocoa 8.58.4 и CocoaPods, сохраняя официальный
SDK для сериализации, scope, crash handler и очереди. Session-local `URLProtocol`
только ограничивает сетевую отправку. Swift Package Manager для этого моста не заявлен.
Подробные сценарии и пределы: [macOS lifecycle](../../docs/macos-lifecycle-acceptance.md).

## Зависимости и переход

Пакет опциональный: основной `apptracer_flutter` не получил зависимости Sentry.
Но если добавить этот пакет в общее mobile/desktop приложение, транзитивный
`sentry_flutter` также добавит нативные зависимости iOS/Android. Условный Dart import
их не убирает. Используйте отдельный desktop example/consumer; iOS-граф проверяется
отдельно. На iOS/Android/Web этот адаптер откажется стартовать.

Git-потребителям `apptracer_flutter_sentry` нужно явно заменить зависимость и
`SentryProtocolTracer()` на `SentryDesktopTracer()`. Старый manual envelope transport
остаётся неизменным; одновременно запускать его и новый SDK нельзя.

Пример с Windows/macOS/Linux runners: [example](example/README.md).
Сборка и проверенная область Windows: [протокол](../../docs/windows-preparation.md).

Установка во внешнее приложение, CocoaPods, переход со старого транспорта и
проверка упаковки: [migration guide](../../docs/desktop-migration.md).
Проверенный инструментальный baseline: Flutter 3.47.4 / Dart 3.13.3,
sentry_flutter 9.30.1 / Cocoa 8.58.4; runtime macOS arm64. Deployment target
моста — macOS 12.0, но это не означает выполненную приёмку на каждой старой ОС.

## Проверки

```sh
flutter pub get
flutter analyze
flutter test
```

SDK-тесты с mock native MethodChannel сейчас запускаются на macOS. Они используют
официальные init, Scope, фильтрацию и сериализатор envelopes; сетевой приём Tracer,
нативный crash и purge ими не проверяются. Внутренние integration types и options
observer привязаны к точной версии SDK: перед обновлением повторить аудит и тесты.
