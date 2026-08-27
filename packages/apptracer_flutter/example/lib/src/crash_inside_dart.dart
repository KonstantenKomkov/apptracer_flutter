/// A crash whose faulting instruction lives inside the Dart AOT snapshot.
///
/// Only meaningful where `dart:ffi` exists, which is everywhere but the web.
library;

export 'crash_inside_dart_stub.dart'
    if (dart.library.ffi) 'crash_inside_dart_ffi.dart';
