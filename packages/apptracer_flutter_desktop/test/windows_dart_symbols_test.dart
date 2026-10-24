import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apptracer_flutter_desktop/src/event_mapping.dart';
import 'package:apptracer_flutter_desktop/src/windows_dart_symbols.dart';
import 'package:apptracer_flutter_desktop/src/windows_elf_identity.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '000102030405060708090a0b0c0d0e0f';
  late Directory directory;
  late File elf;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('windows-elf-');
    elf = File('${directory.path}/app.so');
    final bytes = Uint8List(152);
    bytes.setAll(0, [0x7f, 69, 76, 70, 2, 1]);
    final data = ByteData.sublistView(bytes);
    data.setUint16(18, 62, Endian.little);
    data.setUint64(32, 64, Endian.little);
    data.setUint16(54, 56, Endian.little);
    data.setUint16(56, 1, Endian.little);
    data.setUint32(64, 4, Endian.little);
    data.setUint64(72, 120, Endian.little);
    data.setUint64(96, 32, Endian.little);
    data.setUint32(120, 4, Endian.little);
    data.setUint32(124, 16, Endian.little);
    data.setUint32(128, 3, Endian.little);
    bytes.setAll(132, [71, 78, 85, 0]);
    bytes.setAll(136, List.generate(16, (i) => i));
    await elf.writeAsBytes(bytes);
    await File('${directory.path}/$id.json.gz').writeAsBytes(gzip.encode(
      utf8.encode(jsonEncode({
        'schema': 1,
        'arch': 'x64',
        'build_id': id,
        'files': ['package:example/main.dart'],
        'functions': [
          [0x234, 4, 'crashSite']
        ],
        'lines': [
          [0x234, 4, 0, 73]
        ],
      })),
    ));
  });
  tearDown(() => directory.delete(recursive: true));

  test('reads Windows AOT ELF identity and rejects malformed bounds', () async {
    expect(await windowsElfIdentity(elf.path), id);
    final bytes = await elf.readAsBytes();
    ByteData.sublistView(bytes).setUint64(72, 10000, Endian.little);
    await elf.writeAsBytes(bytes);
    expect(await windowsElfIdentity(elf.path), isNull);
    await elf.writeAsBytes(bytes.sublist(0, 20));
    expect(await windowsElfIdentity(elf.path), isNull);
  });

  test('resolves exact-build Windows addresses and rejects another image',
      () async {
    for (final matches in [true, false]) {
      if (!matches) {
        final bytes = await elf.readAsBytes();
        bytes[136] = 255;
        await elf.writeAsBytes(bytes);
      }
      final source = TracerEvent(
          exceptionType: 'StateError',
          message: 'probe',
          stackTrace: DartStackTrace.parse(StackTrace.fromString(
              "os: windows arch: x64 comp: no sim: no\nbuild_id: '$id'\n"
              'isolate_dso_base: 1000\n'
              '#00 abs 00001234 virt 00000234 _kDartSnapshotText+0x34\n')));
      final event = toSentryEvent(source);
      await WindowsDartSymbols(directory: directory.path, appImage: elf.path)
          .resolve(event, source);
      final frame = event.exceptions!.single.stackTrace!.frames.single;
      expect(frame.lineNo, matches ? 73 : null);
      expect(frame.fileName, matches ? 'package:example/main.dart' : null);
      expect(frame.instructionAddr, '0x00001234');
    }
  });
}
