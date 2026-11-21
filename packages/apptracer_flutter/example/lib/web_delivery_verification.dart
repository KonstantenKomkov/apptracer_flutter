import 'dart:async';
import 'dart:js_interop';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';

@JS('window.location.assign')
external void _assign(String url);

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
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(
          child: ValueListenableBuilder<String>(
        valueListenable: status,
        builder: (_, value, __) => Text('web-delivery:$value'),
      )),
    ),
  ));
  final options = TracerOptions(
    appToken: 'web-delivery-synthetic-token',
    apiUrl: 'http://${Uri.base.host}:$port',
    debug: true,
    initialCustomKeys: const <String, String>{'verification': 'web-delivery'},
  );
  try {
    await Tracer.initialize(options: options, appRunner: () {});
    if (scenario == 'stop' && !reloaded) {
      await Tracer.recordError(
          StateError('web-delivery-revoked'), StackTrace.current);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await Tracer.stopAndClearCollection();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _reload();
      return;
    }
    if (scenario == 'reload' && !reloaded) {
      await Tracer.recordError(
          StateError('web-delivery-reload'), StackTrace.current);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _reload();
      return;
    }
    if (scenario == 'recovery') {
      await Tracer.recordError(
          StateError('web-delivery-recovery'), StackTrace.current);
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    status.value = 'complete';
  } on Object catch (error) {
    status.value = 'error:${error.runtimeType}';
  }
}
