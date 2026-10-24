import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Queue-specific process and reparse-point checks in the Windows helper.
class WindowsUploaders {
  static final _library = DynamicLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/apptracer_windows.dll');

  static void _call(String name, String path) {
    if (!Platform.isWindows) throw UnsupportedError('windows_host_required');
    final value = path.toNativeUtf16();
    try {
      final result = _library.lookupFunction<Uint32 Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>(name)(value);
      if (result != 0) throw StateError('$name failed: $result');
    } finally {
      calloc.free(value);
    }
  }

  /// Stops only daemons holding locks in the caller's exclusively owned queue.
  static Future<void> stop(String database) async {
    validate(database);
    _call('apptracer_stop_daemons', database);
  }

  /// Refuses symlinks, junctions and unreadable storage ancestors.
  static void validate(String path) =>
      _call('apptracer_validate_storage', path);
}
