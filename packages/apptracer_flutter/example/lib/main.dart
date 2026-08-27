import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:apptracer_flutter_sentry/apptracer_flutter_sentry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'src/crash_inside_dart.dart';

/// Tokens are read from the build environment, never hard-coded.
///
/// ```
/// flutter run --dart-define=TRACER_APP_TOKEN=...
/// ```
///
/// A token committed to a repository is a token that has leaked, so the
/// example refuses to carry a default.
const String _appToken = String.fromEnvironment('TRACER_APP_TOKEN');

/// Sentry DSN, issued by Tracer for a project created through VK Cloud. Only
/// desktop and Aurora OS have any use for it; see docs/platform-matrix.md.
const String _dsn = String.fromEnvironment('TRACER_DSN');

void main() {
  // Android and iOS register their implementations automatically, and web
  // registers its HTTP transport for itself. Desktop and Aurora OS have no
  // native SDK a Flutter application can reach — none at all for desktop, a
  // C/C++ library and system minidumps for Aurora — so a pure-Dart transport
  // is registered by hand there.
  //
  // Two are available, and they differ in what backs them rather than in what
  // they do. The Sentry route is the one Tracer documents for platforms
  // without an SDK of its own, and it needs a DSN from a VK Cloud project. The
  // HTTP route speaks Tracer's own ingest, needs only the appToken every other
  // platform already uses, and was recovered by observation rather than read
  // from documentation. The documented one wins when a DSN is present.
  if (_needsDartTransport) {
    if (_dsn.isNotEmpty) {
      TracerPlatform.instance = SentryProtocolTracer();
    } else if (_appToken.isNotEmpty) {
      TracerPlatform.instance = TracerHttpTracer(
        facts: PlatformClientFacts(),
        sdkVersion: '0.1.0',
      );
    }
  }

  Tracer.initialize(
    options: TracerOptions(
      appToken: _appToken.isEmpty ? null : _appToken,
      dsn: _dsn.isEmpty ? null : _dsn,
      environment: kReleaseMode ? 'prod' : 'dev',
      release: '1.0.0',
      debug: !kReleaseMode,
      maxBreadcrumbs: 50,
      // Nothing personal is collected by default; this hook is where an
      // application would strip anything it does not want to leave the device.
      beforeSend: (TracerEvent event) {
        if (event.message.contains('@')) {
          return event.copyWith(message: '<redacted>');
        }
        return event;
      },
    ),
    appRunner: () {
      unawaited(_warmUpNetworkPermission());
      runApp(const ExampleApp());
    },
  );
}

/// Просит систему разрешить сеть один раз — на старте, а не в момент сбоя.
///
/// Оболочки Android, EMUI и не только, показывают собственный вопрос про
/// доступ в сеть при первом сетевом запросе приложения, и пока на него не
/// ответили, запрос ждёт. У приложения с Tracer первым сетевым запросом обычно
/// оказывается отправка отчёта — а значит вопрос всплывает ровно в момент
/// ошибки, поверх сломанного экрана, и отчёт уходит не раньше, чем
/// пользователь его закроет. Худшего момента для системного диалога не
/// придумать.
///
/// Один безобидный запрос к тому же хосту, куда потом пойдут отчёты, переносит
/// вопрос на запуск. Ответ сервера не нужен и не проверяется: важно само
/// обращение к сети.
///
/// Это дело приложения, а не пакета: библиотека не вправе ходить в сеть по
/// собственному почину, поэтому в `apptracer_flutter` такого нет.
///
/// В примере запрос уходит безусловно — сбор здесь включён всегда. Приложению,
/// которое включает сбор по согласию, прогрев надо привязать к тому же
/// согласию: сервер вендора не должен слышать о пользователе, который ничего
/// не разрешал.
Future<void> _warmUpNetworkPermission() async {
  if (kIsWeb) {
    return;
  }
  final http.Client client = http.Client();
  try {
    await client
        .head(Uri.https(TracerHttpTracer.defaultHost, '/'))
        .timeout(const Duration(seconds: 5));
  } catch (error) {
    if (kDebugMode) {
      debugPrint('прогрев сети не удался, это не ошибка: $error');
    }
  } finally {
    client.close();
  }
}

/// Channel to the two failure modes Dart cannot reach on its own: a native
/// crash and an ANR. Implemented in the example's `MainActivity`.
const MethodChannel _nativeFailures =
    MethodChannel('ru.apptracer.flutter.example/native');

/// Whether the native-failure section is worth showing.
///
/// Both platforms can crash the process natively. An ANR, however, is an
/// Android concept: the nearest iOS equivalent is the SDK's hang counter, and
/// an application does not raise that on demand.
bool get _hasNativeFailures =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Whether the ANR button makes sense here.
bool get _hasAnr => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _needsDartTransport {
  if (kIsWeb) {
    return false;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return false;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      return true;
  }
}

/// Root of the example application.
class ExampleApp extends StatelessWidget {
  /// Creates the example application.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Пример apptracer_flutter',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2F6FED),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// Demonstrates every error path the package covers.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _renderBrokenWidget = false;
  String _status = '';

  void _report(String message) {
    setState(() => _status = message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Пример apptracer_flutter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Состояние', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(Tracer.isEnabled ? 'Сбор включён' : 'Сбор выключен'),
                  Text('бэкенд: ${TracerPlatform.instance.backendName}'),
                  Text('breadcrumbs в буфере: ${Tracer.breadcrumbs.length}'),
                  if (_status.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(_status, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Необработанные ошибки',
            description:
                'Доходят до Tracer через FlutterError.onError или защищённую '
                'зону. Ни одна из них не завершает процесс — именно поэтому '
                'нативные SDK их не видят.',
            children: <Widget>[
              FilledButton(
                onPressed: () => throw StateError('synchronous Dart failure'),
                child: const Text('Бросить синхронно'),
              ),
              FilledButton(
                onPressed: () {
                  Timer.run(
                    () => throw const FormatException('asynchronous failure'),
                  );
                  _report('запланирована асинхронная ошибка');
                },
                child: const Text('Бросить асинхронно'),
              ),
              FilledButton(
                onPressed: () async {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  throw TimeoutException('unawaited future failure');
                },
                child: const Text('Бросить из future без await'),
              ),
              FilledButton(
                onPressed: () =>
                    setState(() => _renderBrokenWidget = !_renderBrokenWidget),
                child: const Text('Бросить внутри build() виджета'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Обработанные ошибки',
            description:
                'Отправляются явно. issueKey переопределяет группировку '
                'Tracer, когда место броска говорит больше, чем стектрейс.',
            children: <Widget>[
              FilledButton.tonal(
                onPressed: () async {
                  try {
                    throw const FormatException('could not parse the response');
                  } catch (error, stackTrace) {
                    await Tracer.recordError(
                      error,
                      stackTrace,
                      severity: TracerSeverity.warning,
                      issueKey: 'EXAMPLE-PARSE',
                      customKeys: const <String, String>{'endpoint': '/orders'},
                    );
                  }
                  _report('отправлена нефатальная ошибка');
                },
                child: const Text('Отправить пойманную ошибку'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  Tracer.log(
                    'user tapped the breadcrumb button',
                    category: 'ui',
                    data: const <String, String>{'screen': 'home'},
                  );
                  _report('breadcrumb добавлен');
                  setState(() {});
                },
                child: const Text('Добавить breadcrumb'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  await Tracer.setCustomKey(key: 'checkout_step', value: '3');
                  _report('задан кастомный ключ checkout_step=3');
                },
                child: const Text('Задать кастомный ключ'),
              ),
            ],
          ),
          if (_hasNativeFailures) ...<Widget>[
            const SizedBox(height: 16),
            _Section(
              title: 'Нативные сбои',
              description: 'Эти пути — работа нативного SDK Tracer, а не этого '
                  'пакета. Кнопки нужны, чтобы подтвердить, что связка жива. '
                  'Каждая завершает сеанс: после краша процесс умирает, '
                  'после ANR приложение надо закрыть из системного диалога — '
                  'иначе отчёта не будет. ANR есть только на Android и требует '
                  'Android 11 или новее. Третья кнопка отличается от первой '
                  'местом падения: сбой происходит в самом коде Dart, внутри '
                  'libapp.so, — этим проверяется, применил ли Tracer '
                  'загруженные символы Dart (проверка 16).',
              children: <Widget>[
                OutlinedButton(
                  onPressed: () {
                    _report('процесс сейчас упадёт');
                    unawaited(
                      _nativeFailures.invokeMethod<void>('crashNatively'),
                    );
                  },
                  child: const Text('Уронить процесс нативно'),
                ),
                OutlinedButton(
                  onPressed: () {
                    // Отчёт уйдёт при следующем запуске, как и у соседней
                    // кнопки: процесс умирает здесь же, на следующей строке.
                    _report('процесс сейчас упадёт внутри кода Dart');
                    crashInsideDartCode();
                  },
                  child: const Text('Уронить процесс изнутри Dart (FFI)'),
                ),
                if (_hasAnr)
                  OutlinedButton(
                    onPressed: () {
                      // Сообщение выставляется до вызова: главный поток Android
                      // вот-вот встанет, и ответа от него ждать бессмысленно.
                      _report(
                        'главный поток Android заблокирован — постучите по '
                        'экрану и закройте приложение из системного диалога',
                      );
                      unawaited(
                        _nativeFailures.invokeMethod<void>('blockMainThread'),
                      );
                    },
                    child: const Text('Заблокировать главный поток (ANR)'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _Section(
            title: 'Согласие',
            description:
                'stopCollection снимает обработчики ошибок Dart и возвращает '
                'те, что стояли до него. На Android дополнительно вызывается '
                'Tracer.disable(), который нативный SDK не отменит до '
                'перезапуска процесса.',
            children: <Widget>[
              OutlinedButton(
                onPressed: () async {
                  await Tracer.stopCollection();
                  _report('сбор остановлен');
                  setState(() {});
                },
                child: const Text('Остановить сбор'),
              ),
            ],
          ),
          if (_renderBrokenWidget) const _BrokenWidget(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(description, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        ...children.expand(
          (Widget child) => <Widget>[child, const SizedBox(height: 8)],
        ),
      ],
    );
  }
}

class _BrokenWidget extends StatelessWidget {
  const _BrokenWidget();

  @override
  Widget build(BuildContext context) {
    throw StateError('failure raised inside build()');
  }
}
