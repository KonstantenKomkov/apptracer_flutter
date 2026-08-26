import 'dart:convert';

import 'models/dart_stack_frame.dart';

/// Builds a Tracer `issueKey` from a Dart error type and its innermost named
/// frame, for backends whose own grouping cannot tell two Dart errors apart.
///
/// Why this is needed at all differs per platform, but the answer is the same
/// on both native SDKs:
///
///  * **Android.** Measured against a live project on 2026-08-26: Tracer keys a
///    group on the top frame's class and method and nothing else. Three events
///    — `StateError` twice from different lines and a `TimeoutException` from a
///    third — landed in one group because all three read
///    `_HomePageState.build.<anonymous closure>` at the top. In a Flutter
///    application most handlers are anonymous closures inside one `build`, so
///    unrelated errors collapse together.
///  * **iOS.** A Dart stack trace carries no native addresses, and Tracer
///    ignores a supplied symbol array unless a debugger is attached, so a
///    release build has nothing to group on at all.
///
/// Adding the error type to the key separates errors of different kinds while
/// keeping everything thrown from one call site together.
abstract final class SyntheticIssueKey {
  /// Maximum length of an `issueKey`.
  ///
  /// `LIMIT_MAX_ISSUE_KEY_LENGTH = 32` is declared in the Android SDK's
  /// `BuildConfig`. Whether it truncates or rejects could not be established
  /// from the bytecode, and the iOS SDK publishes no equivalent — but a key of
  /// `dart/<Type>/<member>` runs to 37–56 characters in ordinary cases, so if
  /// truncation does happen it happens on nearly every event, and two errors
  /// sharing a 32-character prefix would merge into one group. That is worse
  /// than not grouping at all, and staying inside the limit costs nothing.
  static const int maxLength = 32;

  /// Builds the key for an error of [exceptionType] with [frames].
  ///
  /// **Neither the file nor the line number is included, deliberately.** Tracer
  /// computes its own grouping id from a title and subtitle and explicitly
  /// ignores file names and line numbers, so that editing a file does not
  /// scatter one issue across several groups — confirmed live: the same throw
  /// at line 135 and at line 148 stayed in one group. An `issueKey` is used
  /// verbatim, so putting a line number in it would reintroduce exactly the
  /// instability Tracer went out of its way to avoid.
  static String forError({
    required String exceptionType,
    required List<DartStackFrame> frames,
  }) {
    for (final DartStackFrame frame in frames) {
      final String? member = frame.member;
      if (member != null) {
        return _bounded('dart/$exceptionType/$member', member);
      }
      // An obfuscated AOT build has no names at all, only addresses, and those
      // move with every build. Grouping is per-build here, because nothing
      // stable is left to key on. See docs/symbolication.md.
      final String? virtual = frame.virtualAddress;
      if (virtual != null) {
        return _bounded(
          'dart/$exceptionType/virt+$virtual',
          'virt+$virtual',
        );
      }
    }
    return _bounded('dart/$exceptionType', exceptionType);
  }

  /// Produces a key of at most [maxLength] characters.
  ///
  /// When it fits, `identity` is used as-is and stays fully readable. When it
  /// does not, the key becomes the tail of `readable` plus a digest of the
  /// *whole* `identity`, so two errors whose readable parts trim to the same
  /// text still land in different groups.
  ///
  /// The tail of the member is kept rather than the head: the method name says
  /// more than the class prefix it hangs off, and the error type is already in
  /// the event title, so repeating it inside the key would spend scarce
  /// characters on nothing.
  static String _bounded(String identity, String readable) {
    if (identity.length <= maxLength) {
      return identity;
    }
    final String digest =
        _fnv1a(identity).toRadixString(16).padLeft(8, '0').substring(0, 6);
    final int budget = maxLength - digest.length - 3; // 'd/' and '#'
    final String tail = readable.length <= budget
        ? readable
        : readable.substring(readable.length - budget);
    return 'd/$tail#$digest';
  }

  /// FNV-1a, 32-bit, over the UTF-8 bytes of [text].
  ///
  /// Four lines long, and stable across runs, platforms and language runtimes —
  /// which `Object.hashCode` is not: it is seeded per process and would hand
  /// out a different grouping key on every launch. The iOS plugin carries a
  /// byte-for-byte equivalent in Swift as a fallback; the two must agree.
  static int _fnv1a(String text) {
    int hash = 2166136261;
    for (final int byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }
}
