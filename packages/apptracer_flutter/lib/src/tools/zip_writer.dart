import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds a ZIP archive from files on disk, without a package dependency.
///
/// `package:archive` would do this in three lines, but it would then be a
/// dependency of every application that uses `apptracer_flutter`, for the sake
/// of a command that runs on a build machine. `dart:io` already carries raw
/// deflate through [ZLibCodec], and the rest of the format is a header, a
/// central directory and a CRC.
class ZipWriter {
  final BytesBuilder _body = BytesBuilder();
  final List<_Entry> _entries = <_Entry>[];

  /// Adds [bytes] under [name], which must use forward slashes.
  ///
  /// Stores the entry uncompressed when deflating it would not save anything,
  /// which is what every zip tool does and what keeps already-compressed
  /// payloads from growing.
  void addBytes(String name, List<int> bytes) {
    final Uint8List raw = Uint8List.fromList(bytes);
    final Uint8List deflated =
        Uint8List.fromList(ZLibCodec(raw: true, level: 6).encode(raw));
    final bool compress = deflated.length < raw.length;
    final Uint8List payload = compress ? deflated : raw;

    final Uint8List nameBytes = Uint8List.fromList(utf8.encode(name));
    final int crc = _crc32(raw);
    final int offset = _body.length;

    _body.add(_localHeader(
      nameBytes: nameBytes,
      crc: crc,
      compressedSize: payload.length,
      uncompressedSize: raw.length,
      compressed: compress,
    ));
    _body.add(payload);

    _entries.add(_Entry(
      nameBytes: nameBytes,
      crc: crc,
      compressedSize: payload.length,
      uncompressedSize: raw.length,
      compressed: compress,
      offset: offset,
    ));
  }

  /// Adds every file under [directory], named relative to it.
  ///
  /// [keep] decides which files go in; symbolic links are skipped rather than
  /// followed, because a `.dSYM` bundle is full of them and following them
  /// doubles the archive.
  void addDirectory(
    Directory directory, {
    bool Function(String relativePath)? keep,
  }) {
    final String root = directory.absolute.path;
    final List<FileSystemEntity> entities = directory.listSync(
        recursive: true, followLinks: false)
      ..sort(
          (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path));

    for (final FileSystemEntity entity in entities) {
      if (entity is! File) {
        continue;
      }
      String relative = entity.absolute.path.substring(root.length);
      relative = relative.replaceAll(r'\', '/');
      if (relative.startsWith('/')) {
        relative = relative.substring(1);
      }
      if (keep != null && !keep(relative)) {
        continue;
      }
      addBytes(relative, entity.readAsBytesSync());
    }
  }

  /// Whether anything has been added.
  bool get isEmpty => _entries.isEmpty;

  /// The number of entries added.
  int get length => _entries.length;

  /// Serializes the archive.
  Uint8List build() {
    final BytesBuilder out = BytesBuilder()..add(_body.toBytes());
    final int centralStart = out.length;
    for (final _Entry entry in _entries) {
      out.add(entry.centralHeader());
    }
    final int centralSize = out.length - centralStart;

    final ByteData end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _entries.length, Endian.little)
      ..setUint16(10, _entries.length, Endian.little)
      ..setUint32(12, centralSize, Endian.little)
      ..setUint32(16, centralStart, Endian.little)
      ..setUint16(20, 0, Endian.little);
    out.add(end.buffer.asUint8List());
    return out.toBytes();
  }

  static Uint8List _localHeader({
    required Uint8List nameBytes,
    required int crc,
    required int compressedSize,
    required int uncompressedSize,
    required bool compressed,
  }) {
    final ByteData header = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 1 << 11, Endian.little) // names are UTF-8
      ..setUint16(8, compressed ? 8 : 0, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0x21, Endian.little) // a fixed date keeps builds stable
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, compressedSize, Endian.little)
      ..setUint32(22, uncompressedSize, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    return Uint8List.fromList(<int>[
      ...header.buffer.asUint8List(),
      ...nameBytes,
    ]);
  }
}

class _Entry {
  _Entry({
    required this.nameBytes,
    required this.crc,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressed,
    required this.offset,
  });

  final Uint8List nameBytes;
  final int crc;
  final int compressedSize;
  final int uncompressedSize;
  final bool compressed;
  final int offset;

  Uint8List centralHeader() {
    final ByteData header = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 1 << 11, Endian.little)
      ..setUint16(10, compressed ? 8 : 0, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, 0x21, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, compressedSize, Endian.little)
      ..setUint32(24, uncompressedSize, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint16(30, 0, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint16(36, 0, Endian.little)
      ..setUint32(38, 0, Endian.little)
      ..setUint32(42, offset, Endian.little);
    return Uint8List.fromList(<int>[
      ...header.buffer.asUint8List(),
      ...nameBytes,
    ]);
  }
}

final List<int> _crcTable = List<int>.generate(256, (int i) {
  int c = i;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  int crc = 0xffffffff;
  for (final int byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}
