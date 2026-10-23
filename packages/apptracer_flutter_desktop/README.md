# apptracer_flutter_desktop

[English](README.en.md)

Экспериментальный адаптер `TracerPlatform` на **официальном sentry_flutter 9.30.1**.
Dart-код предназначен для Windows/macOS. Жизненный цикл macOS проверен локально
на arm64; Windows x64 release, Dart/native loopback и повторная отправка native
дампа после HTTP 503 проверены в CI. Windows stop/clear и live-приёмка Tracer
не завершены. Пакет не опубликован.

Подключить этот пакет по path/git вместе с `apptracer_flutter`. На Windows/macOS адаптер
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
- На Windows старт с `preservePreviousReports: false` возвращает `unsupported`
  (`windows_previous_report_cleanup_unavailable`) до запуска SDK: удаление
  прежних отчётов пока не реализовано. Экспериментальный пример явно сохраняет
  отчёты для проверки доставки. Native purge возвращает `unsupported`;
  stop/отзыв сети ещё не приняты. macOS-результаты нельзя
  переносить на Windows. Ни одна платформа пока не объявлена полностью поддержанной.

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

Пример с Windows/macOS runners: [example](example/README.md).
Подготовка и открытые проверки Windows: [протокол](../../docs/windows-preparation.md).

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
