import 'dart:collection';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';

/// A bounded FIFO buffer of breadcrumbs.
///
/// When the buffer is full the oldest breadcrumb is dropped, which matches how
/// the native Tracer log buffers behave (Android keeps a 64 KiB ring buffer).
class BreadcrumbBuffer {
  /// Creates a buffer holding at most [maxLength] breadcrumbs.
  BreadcrumbBuffer({required this.maxLength})
      : assert(maxLength >= 0, 'maxLength must not be negative');

  /// Maximum number of retained breadcrumbs. Zero disables buffering.
  final int maxLength;

  final Queue<TracerBreadcrumb> _entries = Queue<TracerBreadcrumb>();

  /// The buffered breadcrumbs, oldest first.
  List<TracerBreadcrumb> get entries =>
      List<TracerBreadcrumb>.unmodifiable(_entries);

  /// Number of buffered breadcrumbs.
  int get length => _entries.length;

  /// Whether the buffer holds nothing.
  bool get isEmpty => _entries.isEmpty;

  /// Appends [breadcrumb], evicting the oldest entry when full.
  void add(TracerBreadcrumb breadcrumb) {
    if (maxLength == 0) {
      return;
    }
    _entries.addLast(breadcrumb);
    while (_entries.length > maxLength) {
      _entries.removeFirst();
    }
  }

  /// Drops every buffered breadcrumb.
  void clear() => _entries.clear();
}
