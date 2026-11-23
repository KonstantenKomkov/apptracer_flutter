@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a negative buffer limit is safe with assertions disabled', () async {
    final directory = Directory.systemTemp.createTempSync('tracer-no-asserts');
    addTearDown(() => directory.deleteSync(recursive: true));
    final stub = Directory('${directory.path}/stub')..createSync();
    File('${stub.path}/lib/apptracer_flutter_platform_interface.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class TracerBreadcrumb {
  TracerBreadcrumb({required this.message});
  final String message;
}
''');
    final script = File('${directory.path}/main.dart');
    script.writeAsStringSync('''
import 'package:apptracer_flutter/src/breadcrumb_buffer.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';

void main() {
  assert(false, 'expected disabled VM assertions');
  final buffer = BreadcrumbBuffer(maxLength: -1);
  buffer.add(TracerBreadcrumb(message: 'safe'));
  if (!buffer.isEmpty) throw StateError('negative buffer retained an entry');
}
''');
    // Only the element type is stubbed. Queue storage and eviction come from
    // this checkout. This probe does not run the Flutter startup path.
    final config = File('${directory.path}/package_config.json');
    config.writeAsStringSync(jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'apptracer_flutter',
          'rootUri': Uri.directory(Directory.current.path).toString(),
          'packageUri': 'lib/',
        },
        {
          'name': 'apptracer_flutter_platform_interface',
          'rootUri': Uri.directory(stub.path).toString(),
          'packageUri': 'lib/',
        },
      ],
    }));

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final binary = Platform.isWindows ? 'dart.exe' : 'dart';
    final dart = flutterRoot == null
        ? binary
        : '$flutterRoot/bin/cache/dart-sdk/bin/$binary';
    final result = await Process.run(dart, [
      '--enable-asserts=false',
      '--packages=${config.path}',
      script.path,
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
