import 'package:meta/meta.dart';

/// One parsed frame of a Dart stack trace.
///
/// A frame is either *symbolic* (it carries [member] and usually [uri]/[line]),
/// or *address-only* (it carries [absoluteAddress]/[virtualAddress] and comes
/// from an AOT build compiled with `--obfuscate --split-debug-info`), or the
/// `<asynchronous suspension>` marker.
@immutable
class DartStackFrame {
  /// Creates a frame. Prefer [DartStackTrace.parse] over calling this directly.
  const DartStackFrame({
    required this.raw,
    this.index,
    this.member,
    this.uri,
    this.line,
    this.column,
    this.absoluteAddress,
    this.virtualAddress,
    this.symbol,
    this.isAsynchronousSuspension = false,
  });

  /// The `<asynchronous suspension>` marker frame.
  factory DartStackFrame.asynchronousSuspension(String raw) =>
      DartStackFrame(raw: raw, isAsynchronousSuspension: true);

  /// The original text of the frame, verbatim.
  final String raw;

  /// Zero-based position of the frame as printed by the Dart VM, if present.
  final int? index;

  /// The function or method name, for example `MyWidget.build`.
  final String? member;

  /// The source URI, for example `package:example/main.dart` or
  /// `dart:async/zone.dart`, or a JavaScript URL on the web.
  final String? uri;

  /// 1-based line number within [uri].
  final int? line;

  /// 1-based column number within [uri].
  final int? column;

  /// Absolute program counter as hex, present only in obfuscated AOT traces.
  final String? absoluteAddress;

  /// Virtual (DSO-relative) address as hex, present only in obfuscated AOT
  /// traces. This is the value `flutter symbolize` resolves.
  final String? virtualAddress;

  /// Trailing symbol reference of an obfuscated frame, for example
  /// `_kDartIsolateSnapshotInstructions+0x24b2f0`.
  final String? symbol;

  /// Whether this frame is the `<asynchronous suspension>` marker.
  final bool isAsynchronousSuspension;

  /// Whether the frame carries a resolvable source location.
  bool get isSymbolic => member != null;

  /// Whether the frame is address-only and therefore needs symbolication.
  bool get needsSymbolication => absoluteAddress != null;

  /// The file name portion of [uri], for example `main.dart`.
  String? get fileName {
    final value = uri;
    if (value == null) {
      return null;
    }
    final slash = value.lastIndexOf('/');
    return slash == -1 ? value : value.substring(slash + 1);
  }

  /// The package name when [uri] is a `package:` URI, otherwise `null`.
  String? get packageName {
    final value = uri;
    if (value == null || !value.startsWith('package:')) {
      return null;
    }
    final rest = value.substring('package:'.length);
    final slash = rest.indexOf('/');
    return slash == -1 ? rest : rest.substring(0, slash);
  }

  /// Serializes the frame for the method channel and the HTTP transport.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'raw': raw,
      if (index != null) 'index': index,
      if (member != null) 'member': member,
      if (uri != null) 'uri': uri,
      if (line != null) 'line': line,
      if (column != null) 'column': column,
      if (absoluteAddress != null) 'absAddress': absoluteAddress,
      if (virtualAddress != null) 'virtAddress': virtualAddress,
      if (symbol != null) 'symbol': symbol,
      if (isAsynchronousSuspension) 'asyncSuspension': true,
    };
  }

  @override
  String toString() => raw;
}
