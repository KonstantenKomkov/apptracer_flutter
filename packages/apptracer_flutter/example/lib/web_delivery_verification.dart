import 'dart:async';
import 'dart:js_interop';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/widgets.dart';

@JS('window.location.assign')
external void _assign(String url);

@JS('window.fetch')
external JSPromise<JSAny?> _fetch(String url);

void _reload() {
  _assign(Uri.base.replace(queryParameters: <String, String>{
    ...Uri.base.queryParameters,
    'reloaded': 'true',
  }).toString());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scenario = Uri.base.queryParameters['scenario'] ?? 'recovery';
  final reloaded = Uri.base.queryParameters['reloaded'] == 'true';
  final port = Uri.base.queryParameters['port']!;
  final status = ValueNotifier<String>('running');
  runApp(WidgetsApp(
    color: const Color(0xff202020),
    builder: (_, __) => Center(
      child: ValueListenableBuilder<String>(
        valueListenable: status,
        builder: (_, value, __) => Text('web-delivery:$value'),
      ),
    ),
  ));
  final options = TracerOptions(
    appToken: 'web-delivery-synthetic-token',
    apiUrl: 'http://${Uri.base.host}:$port',
    debug: true,
    initialCustomKeys: const <String, String>{'verification': 'web-delivery'},
  );
  try {
    final receiver =
        Uri(scheme: 'http', host: Uri.base.host, port: int.parse(port));
    Future<void> signal(String stage) async {
      await _fetch(
              receiver.replace(path: '/verification/$stage', queryParameters: {
        'scenario': scenario,
        'reloaded': '$reloaded',
      }).toString())
          .toDart;
    }

    if (reloaded) await signal('reloaded');
    await Tracer.initialize(options: options, appRunner: () {});
    if (scenario == 'stop' && !reloaded) {
      await Tracer.recordError(
          StateError('web-delivery-revoked'), StackTrace.current);
      final result = await Tracer.stopAndClearCollection();
      if (result.state != TracerCollectionState.disabled) {
        throw StateError('cleanup failed');
      }
      _reload();
      return;
    }
    if (scenario == 'reload' && !reloaded) {
      await Tracer.recordError(
          StateError('web-delivery-reload'), StackTrace.current);
      _reload();
      return;
    }
    if (scenario == 'recovery') {
      await Tracer.recordError(
          StateError('web-delivery-recovery'), StackTrace.current);
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await signal('complete');
    status.value = 'complete';
  } on Object catch (error) {
    status.value = 'error:${error.runtimeType}';
  }
}
