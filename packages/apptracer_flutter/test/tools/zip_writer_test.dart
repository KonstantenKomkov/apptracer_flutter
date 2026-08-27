import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apptracer_flutter/src/tools/zip_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZipWriter', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zip_writer_test'));
    tearDown(() => root.deleteSync(recursive: true));

    File write(String relative, String contents) {
      final File file = File('${root.path}/$relative');
      file.parent.createSync(recursive: true);
      return file..writeAsStringSync(contents);
    }

    test('an empty archive says so rather than producing a broken file', () {
      expect(ZipWriter().isEmpty, isTrue);
    });

    test('paths are relative to the directory and use forward slashes', () {
      write('main.dart.js', 'a');
      write('assets/fonts/x.map', 'b');

      final ZipWriter zip = ZipWriter()..addDirectory(root);

      expect(
          _names(zip.build()), <String>['assets/fonts/x.map', 'main.dart.js']);
    });

    test('keep decides what goes in', () {
      write('main.dart.js', 'a');
      write('main.dart.js.map', 'b');
      write('index.html', 'c');

      final ZipWriter zip = ZipWriter()
        ..addDirectory(
          root,
          keep: (String path) => path.endsWith('.js') || path.endsWith('.map'),
        );

      expect(_names(zip.build()), <String>['main.dart.js', 'main.dart.js.map']);
    });

    test('contents survive the round trip, compressed and not', () {
      // Repetitive text deflates; a short string does not, and the writer
      // stores that one instead of making it bigger.
      const String compressible = 'console.log("hello");';
      write('big.js', compressible * 400);
      write('small.map', '{}');

      final Uint8List archive = (ZipWriter()..addDirectory(root)).build();

      expect(_read(archive, 'big.js'), compressible * 400);
      expect(_read(archive, 'small.map'), '{}');
    });

    test('a symlink is skipped rather than followed', () {
      // A .dSYM bundle is full of them, and following them doubles the upload.
      write('real.map', 'x');
      Link('${root.path}/link.map').createSync('${root.path}/real.map');

      final ZipWriter zip = ZipWriter()..addDirectory(root);

      expect(_names(zip.build()), <String>['real.map']);
    });

    test('a non-ASCII name comes back intact', () {
      write('отчёт.map', '{"ключ":1}');

      final Uint8List archive = (ZipWriter()..addDirectory(root)).build();

      expect(_read(archive, 'отчёт.map'), '{"ключ":1}');
    });
  });
}

/// Reads the central directory of [archive]: the part a server parses.
List<String> _names(Uint8List archive) {
  final List<String> names = <String>[];
  for (final _Record record in _records(archive)) {
    names.add(record.name);
  }
  names.sort();
  return names;
}

String _read(Uint8List archive, String name) {
  final _Record record =
      _records(archive).firstWhere((_Record r) => r.name == name);
  final ByteData view = ByteData.sublistView(archive);
  final int local = record.offset;
  final int nameLength = view.getUint16(local + 26, Endian.little);
  final int extraLength = view.getUint16(local + 28, Endian.little);
  final int start = local + 30 + nameLength + extraLength;
  final Uint8List payload =
      archive.sublist(start, start + record.compressedSize);
  final List<int> bytes =
      record.compressed ? ZLibCodec(raw: true).decode(payload) : payload;
  return utf8.decode(bytes);
}

Iterable<_Record> _records(Uint8List archive) sync* {
  final ByteData view = ByteData.sublistView(archive);
  int end = archive.length - 22;
  while (view.getUint32(end, Endian.little) != 0x06054b50) {
    end--;
  }
  final int count = view.getUint16(end + 10, Endian.little);
  int cursor = view.getUint32(end + 16, Endian.little);
  for (int i = 0; i < count; i++) {
    final int nameLength = view.getUint16(cursor + 28, Endian.little);
    yield _Record(
      name: utf8.decode(archive.sublist(cursor + 46, cursor + 46 + nameLength)),
      compressed: view.getUint16(cursor + 10, Endian.little) == 8,
      compressedSize: view.getUint32(cursor + 20, Endian.little),
      offset: view.getUint32(cursor + 42, Endian.little),
    );
    cursor += 46 + nameLength;
  }
}

class _Record {
  _Record({
    required this.name,
    required this.compressed,
    required this.compressedSize,
    required this.offset,
  });

  final String name;
  final bool compressed;
  final int compressedSize;
  final int offset;
}
