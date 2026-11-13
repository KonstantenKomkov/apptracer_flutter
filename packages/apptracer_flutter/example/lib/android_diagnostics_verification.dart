// Opt-in release fixture: public Dart API -> channel -> actual optional SDK.
// It uses a synthetic loopback endpoint and never records raw diagnostic bodies.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ru.apptracer.flutter.example/native');
  final context =
      (await channel.invokeMapMethod<String, String>('verificationContext'))!;
  runApp(const MaterialApp(
      home: Scaffold(
          body:
              Center(child: Text('Optional Dart diagnostics verification')))));
  final output = Directory(context['outputPath']!);
  await output.create(recursive: true);
  final requests = <Map<String, Object?>>[];
  final tokens = <String, String>{};
  final results = <String, String>{};
  HttpServer? sink;
  Object? transportFailure;
  int samples(String feature) => requests
      .where(
          (r) => r['path'] == '/api/sample/upload' && r['feature'] == feature)
      .length;
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> save(String stage, [Object? error]) async {
    await File('${output.path}/dart-diagnostics.json').writeAsString(
        jsonEncode({
          'stage': stage,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'pid': pid,
          'enabled': Tracer.isEnabled,
          'results': results,
          'requests': requests,
          if (error != null) 'error': '$error',
        }),
        flush: true);
  }

  void invoked(String operation, TracerDiagnosticResult result) {
    results[operation] = '${result.state.name}/${result.reason}';
    require(result.state == TracerDiagnosticState.invoked,
        '$operation: ${result.state}/${result.reason}');
  }

  void disabled(String operation, TracerDiagnosticResult result) {
    results[operation] = '${result.state.name}/${result.reason}';
    require(result.state == TracerDiagnosticState.disabled,
        '$operation admitted while off');
  }

  try {
    require(context['scenario'] == 'dart-diagnostics',
        'Explicit diagnostic scenario required');
    sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 37018);
    sink.listen((request) async {
      try {
        final path = request.uri.path;
        final item = <String, Object?>{'path': path};
        final response = <String, Object?>{'success': true};
        if (path == '/api/sample/initUpload') {
          final bytes = await request
              .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
          final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          final feature = json['feature'] as String;
          require(['HEAP_DUMP', 'DISK_USAGE'].contains(feature),
              'Unexpected sample feature');
          final token = 'synthetic-${tokens.length}';
          tokens[token] = feature;
          response['uploadToken'] = token;
          item['feature'] = feature;
          item['bytes'] = bytes.length;
        } else {
          item['bytes'] =
              await request.fold<int>(0, (size, chunk) => size + chunk.length);
          if (path == '/api/sample/upload') {
            item['feature'] =
                tokens[request.uri.queryParameters['uploadToken']];
          }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
        requests.add(item);
      } catch (error) {
        transportFailure = error;
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
    const options =
        TracerOptions(captureFlutterErrors: false, captureZoneErrors: false);
    await Tracer.initialize(
        options: options.copyWith(isCollectionEnabled: false),
        appRunner: () {});
    require(
        !Tracer.isEnabled &&
            (await Tracer.getCollectionState()).state ==
                TracerCollectionState.disabled,
        'SDK started before permission');
    disabled('heapBeforeStart', await Tracer.runHeapDump(tag: 'before'));
    disabled('diskBeforeStart', await Tracer.runDiskUsage());
    disabled('providerBeforeStart', await Tracer.setHeapDumpEnabled(true));
    require((await Tracer.startCollection(options)).isEnabled,
        'Explicit start failed');
    invoked('heapDefaultOff', await Tracer.runHeapDump(tag: 'default-off'));
    await Future<void>.delayed(const Duration(seconds: 3));
    require(
        samples('HEAP_DUMP') == 0, 'Default-false provider captured a dump');
    invoked('providerTrue', await Tracer.setHeapDumpEnabled(true));
    invoked('disk', await Tracer.runDiskUsage());
    invoked('heap', await Tracer.runHeapDump(tag: 'task23-public-dart'));
    await save('waiting-for-uploads');
    for (var attempt = 0;
        attempt < 120 &&
            (samples('HEAP_DUMP') < 1 || samples('DISK_USAGE') < 1);
        attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      require(transportFailure == null, 'Loopback failure: $transportFailure');
    }
    require(samples('HEAP_DUMP') == 1 && samples('DISK_USAGE') == 1,
        'Missing or duplicate sample uploads');
    require(
        requests
            .where((r) => r['path'] == '/api/sample/upload')
            .every((r) => (r['bytes']! as int) > 0),
        'Empty sample');
    invoked('providerFalse', await Tracer.setHeapDumpEnabled(false));
    invoked('heapProviderOff', await Tracer.runHeapDump(tag: 'provider-off'));
    await Future<void>.delayed(const Duration(seconds: 3));
    require(samples('HEAP_DUMP') == 1, 'False provider admitted a dump');
    require(
        (await Tracer.pauseCollection()).state ==
            TracerCollectionState.disabled,
        'Pause failed');
    disabled('heapPaused', await Tracer.runHeapDump(tag: 'paused'));
    disabled('diskPaused', await Tracer.runDiskUsage());
    require((await Tracer.resumeCollection()).isEnabled, 'Resume failed');
    await Tracer.stopCollection();
    disabled('heapStopped', await Tracer.runHeapDump(tag: 'stopped'));
    disabled('diskStopped', await Tracer.runDiskUsage());
    disabled('providerStopped', await Tracer.setHeapDumpEnabled(true));
    await Future<void>.delayed(const Duration(seconds: 3));
    require(samples('HEAP_DUMP') == 1 && samples('DISK_USAGE') == 1,
        'Post-stop sample');
    await save('complete');
  } catch (error) {
    await Tracer.stopCollection();
    await save('error', error);
  } finally {
    await sink?.close(force: true);
  }
}
