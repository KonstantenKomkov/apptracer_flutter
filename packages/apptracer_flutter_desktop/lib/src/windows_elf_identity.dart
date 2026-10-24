import 'dart:io';
import 'dart:typed_data';

/// Reads only ELF64 little-endian x64 program headers and bounded GNU notes.
/// Flutter uses this format for data/app.so even on Windows.
Future<String?> windowsElfIdentity(String path) async {
  RandomAccessFile? file;
  try {
    final opened = await File(path).open();
    file = opened;
    final length = await opened.length();
    Future<Uint8List> read(int offset, int count) async {
      if (offset < 0 || count < 0 || offset > length - count) {
        throw const FormatException('ELF bounds');
      }
      await opened.setPosition(offset);
      final bytes = await opened.read(count);
      if (bytes.length != count) throw const FormatException('ELF truncated');
      return bytes;
    }

    final bytes = await read(0, 64);
    final header = ByteData.sublistView(bytes);
    if (bytes[0] != 0x7f ||
        bytes[1] != 69 ||
        bytes[2] != 76 ||
        bytes[3] != 70 ||
        bytes[4] != 2 ||
        bytes[5] != 1 ||
        header.getUint16(18, Endian.little) != 62) {
      return null;
    }
    final offset = header.getUint64(32, Endian.little);
    final size = header.getUint16(54, Endian.little);
    final count = header.getUint16(56, Endian.little);
    if (size < 56 || count > 1024) return null;
    for (var i = 0; i < count; ++i) {
      final program = ByteData.sublistView(await read(offset + i * size, 56));
      if (program.getUint32(0, Endian.little) != 4) continue;
      final noteOffset = program.getUint64(8, Endian.little);
      final noteSize = program.getUint64(32, Endian.little);
      if (noteSize > 65536) return null;
      final notes = await read(noteOffset, noteSize);
      final data = ByteData.sublistView(notes);
      var cursor = 0;
      while (cursor + 12 <= notes.length) {
        final nameSize = data.getUint32(cursor, Endian.little);
        final descSize = data.getUint32(cursor + 4, Endian.little);
        final type = data.getUint32(cursor + 8, Endian.little);
        cursor += 12;
        final descriptor = cursor + ((nameSize + 3) & ~3);
        final end = descriptor + ((descSize + 3) & ~3);
        if (end > notes.length) return null;
        if (type == 3 &&
            nameSize == 4 &&
            descSize >= 16 &&
            descSize <= 32 &&
            notes[cursor] == 71 &&
            notes[cursor + 1] == 78 &&
            notes[cursor + 2] == 85 &&
            notes[cursor + 3] == 0) {
          return notes
              .sublist(descriptor, descriptor + descSize)
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join();
        }
        cursor = end;
      }
    }
  } catch (_) {
    return null;
  } finally {
    await file?.close();
  }
  return null;
}
