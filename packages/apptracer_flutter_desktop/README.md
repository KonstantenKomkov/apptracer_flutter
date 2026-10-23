# apptracer_flutter_desktop

Экспериментальный адаптер `TracerPlatform` на **официальном sentry_flutter 9.30.1**.
Dart-код предназначен для Windows/macOS; платформенная приёмка и управление
нативной очередью ещё не завершены. Пакет не опубликован.

Подключить этот пакет по path/git вместе с `apptracer_flutter`, затем до bootstrap:

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

## Ограничения жизненного цикла

- Создание адаптера, disabled и deferred bootstrap не запускают SDK.
- `startCollection` запускает официальный SDK; ошибки инициализации дают `error`
  и не препятствуют запуску приложения.
- Stop сразу закрывает Dart-приём, затем вызывает SDK close. Ошибка native close
  остаётся `error`; успешный close возвращает `restartRequired`.
- Повторный старт после попытки native init запрещён в текущем процессе, включая
  создание нового адаптера. Это временное ограничение до приёмки №8.
- `stopAndClearCollection` возвращает `unsupported`: удаление native cache/dumps
  пока не реализовано. Очередь прошлых запусков может отправиться при следующем
  native init. `preservePreviousReports: false` пока не обеспечивает её удаления.
  Поэтому пакет **не готов для сценариев с обязательным отзывом согласия** и
  ни одна платформа пока не объявлена полностью поддержанной.

## Зависимости и переход

Пакет опциональный: основной `apptracer_flutter` не получил зависимости Sentry.
Но если добавить этот пакет в общее mobile/desktop приложение, транзитивный
`sentry_flutter` также добавит нативные зависимости iOS/Android. Условный Dart import
их не убирает. Используйте отдельный desktop example/consumer; iOS-граф проверяется
отдельно. На iOS/Android/Web этот адаптер откажется стартовать.

Git-потребителям `apptracer_flutter_sentry` нужно явно заменить зависимость и
`SentryProtocolTracer()` на `SentryDesktopTracer()`. Старый manual envelope transport
остаётся неизменным; одновременно запускать его и новый SDK нельзя.

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
