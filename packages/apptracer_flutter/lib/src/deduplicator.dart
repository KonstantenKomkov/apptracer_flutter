/// Suppresses the same error being reported twice.
///
/// A single Dart error can reach the integration through more than one route.
/// An exception thrown inside a widget build is delivered to
/// `FlutterError.onError`, and, depending on where it was raised, the same
/// object can also surface in the guarded zone or in
/// `PlatformDispatcher.instance.onError`. Reporting it twice inflates event
/// counts and distorts grouping.
///
/// Matching is by *identity* of the error object plus the identity of its stack
/// trace, inside a short time window. Two genuinely separate throws produce
/// separate objects, so a real repeat of the same failure is still reported;
/// only the same instance arriving twice is dropped.
///
/// The identity hash codes are stored, never the objects, so nothing is kept
/// alive by the deduplicator.
class EventDeduplicator {
  /// Creates a deduplicator.
  EventDeduplicator({
    this.window = const Duration(seconds: 3),
    this.capacity = 32,
    DateTime Function()? clock,
  })  : assert(capacity > 0, 'capacity must be positive'),
        _clock = clock ?? DateTime.now;

  /// How long an error stays remembered.
  final Duration window;

  /// How many recent errors are remembered.
  final int capacity;

  final DateTime Function() _clock;
  final List<_Seen> _seen = <_Seen>[];

  /// Returns `true` when this exact error was already seen inside [window].
  ///
  /// Calling this records the error, so a caller should invoke it once per
  /// delivery attempt and skip reporting when it returns `true`.
  bool isDuplicate(Object? error, Object? stackTrace) {
    final now = _clock();
    _seen.removeWhere((_Seen entry) => now.difference(entry.at) > window);

    final errorId = identityHashCode(error);
    final stackId = identityHashCode(stackTrace);
    for (final entry in _seen) {
      if (entry.errorId == errorId && entry.stackId == stackId) {
        return true;
      }
    }

    _seen.add(_Seen(errorId: errorId, stackId: stackId, at: now));
    while (_seen.length > capacity) {
      _seen.removeAt(0);
    }
    return false;
  }

  /// Forgets everything seen so far.
  void clear() => _seen.clear();
}

class _Seen {
  _Seen({required this.errorId, required this.stackId, required this.at});

  final int errorId;
  final int stackId;
  final DateTime at;
}
