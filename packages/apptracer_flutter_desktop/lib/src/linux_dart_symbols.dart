import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Optional exact-build source maps, read only after collection is authorized.
/// Missing, corrupt or mismatched maps leave the original SDK event intact.
class LinuxDartSymbols {
  /// [directory] is injectable for isolated tests. Construction performs no IO.
  LinuxDartSymbols({String? directory}) : _directory = directory;

  final String? _directory;
  String? _loadedId;
  Future<_SourceMap?>? _pending;

  /// Enriches only address frames retained by the user's Tracer filter.
  Future<SentryEvent> resolve(SentryEvent event, TracerEvent source) async {
    try {
      final stack = source.stackTrace;
      final id = stack.buildId;
      final base = _hex(stack.isolateDsoBase);
      if (stack.os != 'linux' ||
          stack.architecture != 'x64' ||
          id == null ||
          !RegExp(r'^[0-9a-f]{32,64}$').hasMatch(id) ||
          base == null) {
        return event;
      }
      // Compare with the actual loaded ELF, not just a user-supplied stack ID.
      final images = event.debugMeta?.images ?? <DebugImage>[];
      if (!images.any((image) =>
          image.type == 'elf' &&
          image.codeId == id &&
          image.codeFile?.endsWith('/libapp.so') == true &&
          _hex(image.imageAddr) == base)) {
        return event;
      }
      if (_loadedId != id) {
        _loadedId = id;
        _pending = _load(id);
      }
      final map = await _pending;
      if (map == null) return event;
      final addresses = <int, int>{};
      for (final frame in stack.frames) {
        final absolute = _hex(frame.absoluteAddress);
        final relative = _hex(frame.virtualAddress);
        if (absolute != null &&
            relative != null &&
            absolute - base == relative) {
          addresses[absolute] = relative;
        }
      }
      for (final exception in event.exceptions ?? <SentryException>[]) {
        for (final frame
            in exception.stackTrace?.frames ?? <SentryStackFrame>[]) {
          if (frame.fileName != null || frame.lineNo != null) continue;
          final address = addresses[_hex(frame.instructionAddr)];
          if (address == null) continue;
          final function = map.find(map.functions, address);
          final line = map.find(map.lines, address);
          if (function != null) {
            frame.function = function[2] as String;
            frame.platform = 'dart';
          }
          if (line != null) {
            final file = map.files[line[2] as int];
            frame
              ..fileName = file
              ..absPath = file
              ..lineNo = line[3] as int
              ..platform = 'dart';
          }
        }
      }
    } catch (_) {
      // Symbolication must not lose an error or affect the application's flow.
    }
    return event;
  }

  Future<_SourceMap?> _load(String id) async {
    try {
      final directory = _directory ??
          '${File(Platform.resolvedExecutable).parent.path}/lib/apptracer-dart-symbols';
      final file = File('$directory/$id.json.gz');
      if (await file.length() > 16 * 1024 * 1024) return null;
      final bytes = BytesBuilder(copy: false);
      await for (final block in gzip.decoder.bind(file.openRead())) {
        if (bytes.length + block.length > 64 * 1024 * 1024) return null;
        bytes.add(block);
      }
      return _SourceMap(jsonDecode(utf8.decode(bytes.takeBytes())), id);
    } catch (_) {
      return null;
    }
  }

  static int? _hex(String? value) => value == null
      ? null
      : int.tryParse(value.startsWith('0x') ? value.substring(2) : value,
          radix: 16);
}

class _SourceMap {
  _SourceMap(dynamic value, String id) {
    if (value is! Map ||
        value['schema'] != 1 ||
        value['build_id'] != id ||
        value['arch'] != 'x64') {
      throw const FormatException('Incompatible Dart source map');
    }
    files = List<String>.from(value['files'] as List);
    functions = _rows(value['functions'], 3);
    lines = _rows(value['lines'], 4);
    for (final function in functions) {
      if (function[2] is! String) {
        throw const FormatException('Invalid function');
      }
    }
    for (final line in lines) {
      if (line[2] is! int ||
          (line[2] as int) < 0 ||
          (line[2] as int) >= files.length ||
          line[3] is! int ||
          (line[3] as int) <= 0) {
        throw const FormatException('Invalid source line');
      }
    }
  }

  late final List<String> files;
  late final List<List<dynamic>> functions;
  late final List<List<dynamic>> lines;

  static List<List<dynamic>> _rows(dynamic value, int columns) {
    final rows = (value as List).map((row) => row as List<dynamic>).toList();
    var previous = -1;
    for (final row in rows) {
      if (row.length != columns ||
          row[0] is! int ||
          row[1] is! int ||
          (row[0] as int) < 0 ||
          (row[0] as int) < previous ||
          (row[1] as int) <= 0) {
        throw const FormatException('Invalid address range');
      }
      previous = row[0] as int;
    }
    return rows;
  }

  List<dynamic>? find(List<List<dynamic>> rows, int address) {
    var lower = 0;
    var upper = rows.length;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      if ((rows[middle][0] as int) <= address) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    if (lower == 0) return null;
    final row = rows[lower - 1];
    return address - (row[0] as int) < (row[1] as int) ? row : null;
  }
}
