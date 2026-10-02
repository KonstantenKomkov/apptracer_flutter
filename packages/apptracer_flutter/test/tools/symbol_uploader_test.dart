import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter/src/tools/symbol_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('symbol upload', () {
    late HttpServer server;
    late List<_Request> received;
    late int status;
    late String responseBody;
    late Directory root;

    setUp(() async {
      received = <_Request>[];
      status = 200;
      responseBody = '{"success":true}';
      root = Directory.systemTemp.createTempSync('uploader_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        final List<int> body = <int>[];
        await for (final List<int> chunk in request) {
          body.addAll(chunk);
        }
        received.add(_Request(request.uri, latin1.decode(body)));
        request.response
          ..statusCode = status
          ..write(responseBody);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      root.deleteSync(recursive: true);
    });

    String url(String path) => 'http://127.0.0.1:${server.port}$path';

    File write(String relative, String contents) {
      final File file = File('${root.path}/$relative');
      file.parent.createSync(recursive: true);
      return file..writeAsStringSync(contents);
    }

    test('iOS upload uses vendor app-name and marketing-version fields',
        () async {
      write('Runner.app.dSYM/Contents/Resources/DWARF/Runner', 'symbols');

      final UploadResult result = await uploadDsym(
        token: 'SECRET',
        dsymDir: root,
        appName: 'Runner',
        version: '2.1.0',
        endpoint: url('/api/symbol/upload'),
      );

      expect(result.ok, isTrue);
      expect(result.fileCount, 1);
      expect(received.single.uri.queryParameters['symbolToken'], 'SECRET');
      expect(received.single.body,
          contains('name="versionName"\r\n\r\nRunner\r\n'));
      expect(received.single.body,
          contains('name="versionCode"\r\n\r\n2.1.0\r\n'));
      expect(received.single.body, contains('filename="dsym.zip"'));
    });

    test('a source-map upload carries the token as a field, not a query',
        () async {
      // The two endpoints differ here, and sending it the other way authenticates
      // nothing while looking like it worked.
      write('main.dart.js', 'console.log(1)');
      write('main.dart.js.map', '{"version":3}');

      final UploadResult result = await uploadSourceMaps(
        token: 'SECRET',
        buildDir: root,
        versionName: '1.0.0',
        endpoint: url('/api/sourcemap/upload'),
      );

      expect(result.ok, isTrue);
      expect(received.single.uri.query, isEmpty);
      expect(received.single.body, contains('name="sourcemapToken"'));
      expect(received.single.body, contains('SECRET'));
    });

    test('iOS build folder uploads only dSYM bundle contents', () async {
      write('Runner.app.dSYM/Contents/Resources/DWARF/Runner', 'symbols');
      write('Runner.app.dSYM/Contents/Info.plist', 'metadata');
      write('Runner.app/Runner', 'application');
      write('Runner.app/embedded.mobileprovision', 'signing');
      write('private-config.json', 'credentials');
      final result = await uploadDsym(
        token: 'T',
        dsymDir: root,
        appName: 'Runner',
        version: '1',
        endpoint: url('/symbols'),
      );
      expect(result.ok, isTrue);
      expect(result.fileCount, 2);
      expect(received.single.body,
          contains('Runner.app.dSYM/Contents/Resources/DWARF/Runner'));
      expect(received.single.body, isNot(contains('Runner.app/Runner')));
      expect(received.single.body, isNot(contains('embedded.mobileprovision')));
      expect(received.single.body, isNot(contains('private-config.json')));
    });

    test('iOS folder without DWARF never makes an upload request', () async {
      write('Runner.app/Runner', 'application');
      write('Runner.app.dSYM/Contents/Info.plist', 'metadata');
      final result = await uploadDsym(
        token: 'T',
        dsymDir: root,
        appName: 'Runner',
        version: '1',
        endpoint: url('/symbols'),
      );
      expect(result.ok, isFalse);
      expect(received, isEmpty);
    });

    test('only .js and .map are sent, so the whole build is not uploaded',
        () async {
      write('main.dart.js', 'a');
      write('main.dart.js.map', 'b');
      write('index.html', 'c');
      write('assets/logo.png', 'd');

      final UploadResult result = await uploadSourceMaps(
        token: 'T',
        buildDir: root,
        versionName: '1.0.0',
        endpoint: url('/api/sourcemap/upload'),
      );

      expect(result.fileCount, 2);
      expect(received.single.body, isNot(contains('index.html')));
    });

    test('a refusal is a failure even when the status is 200', () async {
      // The ingest answers 200 to a body it did not understand, so the status
      // code alone proves nothing.
      responseBody = '{"errorCode":"INVALID_PARAMETERS"}';
      write('main.dart.js.map', '{}');

      final UploadResult result = await uploadSourceMaps(
        token: 'T',
        buildDir: root,
        versionName: '1.0.0',
        endpoint: url('/api/sourcemap/upload'),
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('rejected'));
    });

    test('an HTTP error is a failure', () async {
      status = 400;
      responseBody = '{"errorCode":"INVALID_PARAMETERS"}';
      write('main.dart.js.map', '{}');

      final UploadResult result = await uploadSourceMaps(
        token: 'T',
        buildDir: root,
        versionName: '1.0.0',
        endpoint: url('/api/sourcemap/upload'),
      );

      expect(result.ok, isFalse);
    });

    test('a missing directory is reported, not uploaded as nothing', () async {
      final UploadResult result = await uploadSourceMaps(
        token: 'T',
        buildDir: Directory('${root.path}/absent'),
        versionName: '1.0.0',
        endpoint: url('/api/sourcemap/upload'),
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('no such directory'));
      expect(received, isEmpty);
    });

    test('a build without source maps says which flag is missing', () async {
      write('index.html', 'c');

      final UploadResult result = await uploadSourceMaps(
        token: 'T',
        buildDir: root,
        versionName: '1.0.0',
        endpoint: url('/api/sourcemap/upload'),
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('--source-maps'));
      expect(received, isEmpty);
    });

    test('a failure message never quotes the token', () async {
      // The message is printed by CI, and CI logs are read by everyone.
      final UploadResult result = await uploadSourceMaps(
        token: 'SUPERSECRET',
        buildDir: root,
        versionName: '1.0.0',
        endpoint: 'http://127.0.0.1:1/api/sourcemap/upload',
      );

      expect(result.ok, isFalse);
      expect(result.message, isNot(contains('SUPERSECRET')));
    });
  });
}

class _Request {
  _Request(this.uri, this.body);

  final Uri uri;
  final String body;
}
