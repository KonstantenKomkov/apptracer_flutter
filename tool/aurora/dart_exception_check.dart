// Entry point for a generated Aurora Flutter app with sentry 9.30.1.
// The only receiver is a temporary HTTP server inside this process.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sentry/sentry.dart';

@pragma('vm:never-inline')
void throwAuditError() => throw StateError('aurora-dart-loopback');

Future<Map<String, Object?>> receiveEvent(HttpServer server) async {
  final request = await server.first;
  try {
    final body = await request.fold<List<int>>(
      [],
      (all, part) => all..addAll(part),
    );
    final bytes = request.headers.value('content-encoding') == 'gzip'
        ? gzip.decode(body)
        : body;
    final lines = const LineSplitter().convert(utf8.decode(bytes));
    final event = lines
        .map(jsonDecode)
        .whereType<Map>()
        .firstWhere((item) => item['exception'] is Map);
    final exception = (event['exception']['values'] as List).last;
    final frames = exception['stacktrace']['frames'] as List;
    final appFrame = frames.whereType<Map>().firstWhere(
      (frame) => frame['function'].toString().contains('throwAuditError'),
      orElse: () => {},
    );
    if (exception['type'] != 'StateError' ||
        exception['value'] != 'Bad state: aurora-dart-loopback' ||
        appFrame.isEmpty) {
      throw StateError('Missing exception or application stack frame');
    }
    request.response.write(jsonEncode({'id': event['event_id']}));
    return {
      'path': request.uri.path,
      'type': exception['type'],
      'message': exception['value'],
      'frames': frames.length,
      'function': appFrame['function'],
      'file': appFrame['filename'],
      'line': appFrame['lineno'],
    };
  } catch (_) {
    request.response.statusCode = HttpStatus.badRequest;
    rethrow;
  } finally {
    await request.response.close();
  }
}

Future<Map<String, Object?>> checkDelivery() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    await Sentry.init((options) {
      options.dsn = 'http://public@127.0.0.1:${server.port}/1';
      options.sendClientReports = false;
      options.release = 'aurora-test@2.0.0';
    });
    Future<void> sendError() async {
      try {
        throwAuditError();
      } catch (error, stack) {
        await Sentry.captureException(error, stackTrace: stack);
      }
    }

    final results = await Future.wait<Object?>([
      receiveEvent(server),
      sendError().then<Object?>((_) => null),
    ], eagerError: true).timeout(const Duration(seconds: 15));
    return results.first! as Map<String, Object?>;
  } finally {
    await server.close(force: true);
    await Sentry.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String status;
  try {
    status = jsonEncode(await checkDelivery());
  } catch (error) {
    status = 'FAILED: $error';
  }
  stdout.writeln('APPTRACER_AURORA_DART $status');
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(status))),
    ),
  );
}
