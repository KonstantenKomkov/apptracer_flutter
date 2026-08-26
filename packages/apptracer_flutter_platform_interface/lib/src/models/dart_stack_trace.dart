import 'dart:convert';

import 'package:meta/meta.dart';

import 'dart_stack_frame.dart';

/// A parsed Dart stack trace.
///
/// [DartStackTrace.parse] understands every stack-trace shape a Flutter app can
/// produce:
///
/// * JIT and non-obfuscated AOT frames — `#0 Foo.bar (package:x/y.dart:1:2)`;
/// * obfuscated AOT frames — `#00 abs 00007f.. virt 00002c..`, together with
///   the `build_id` / `isolate_dso_base` header the Dart VM prints above them;
/// * `dart2js` frames in both V8 (`at foo (url:1:2)`) and
///   SpiderMonkey (`foo@url:1:2`) notation;
/// * the `<asynchronous suspension>` marker.
///
/// [raw] is always preserved verbatim. That matters: an obfuscated trace can
/// only be decoded by `flutter symbolize`, and that command needs the header
/// lines as well as the frames. Anything that forwards a trace to Tracer must
/// keep [raw] intact rather than shipping only the parsed frames.
@immutable
class DartStackTrace {
  /// Creates a parsed stack trace. Prefer [DartStackTrace.parse].
  const DartStackTrace({
    required this.raw,
    required this.frames,
    this.buildId,
    this.os,
    this.architecture,
    this.isolateDsoBase,
    this.vmDsoBase,
    this.isolateInstructions,
    this.vmInstructions,
  });

  /// An empty trace, used when an error arrives without one.
  static const DartStackTrace empty =
      DartStackTrace(raw: '', frames: <DartStackFrame>[]);

  /// The original stack trace text, verbatim and unmodified.
  final String raw;

  /// The parsed frames, in the order the VM printed them.
  final List<DartStackFrame> frames;

  /// GNU build id of `libapp.so`, printed by the VM as `build_id: '...'`.
  ///
  /// The matching `app.<platform>-<arch>.symbols` file emitted by
  /// `--split-debug-info` carries the same build id, which is what lets
  /// `flutter symbolize` decode the trace.
  final String? buildId;

  /// Operating system reported in the trace header, for example `android`.
  final String? os;

  /// CPU architecture reported in the trace header, for example `arm64`.
  final String? architecture;

  /// `isolate_dso_base` from the trace header, as hex.
  final String? isolateDsoBase;

  /// `vm_dso_base` from the trace header, as hex.
  final String? vmDsoBase;

  /// `isolate_instructions` from the trace header, as hex.
  final String? isolateInstructions;

  /// `vm_instructions` from the trace header, as hex.
  final String? vmInstructions;

  /// Whether any frame is address-only and therefore unreadable without the
  /// `--split-debug-info` symbol file.
  bool get isObfuscated =>
      frames.any((DartStackFrame frame) => frame.needsSymbolication);

  /// Whether the trace carries no frames at all.
  bool get isEmpty => frames.isEmpty;

  /// Frames that carry a source location, excluding async markers.
  List<DartStackFrame> get symbolicFrames => frames
      .where((DartStackFrame frame) => frame.isSymbolic)
      .toList(growable: false);

  // `#0      Foo.bar (package:x/y.dart:12:5)`
  static final RegExp _vmFrame = RegExp(r'^\s*#(\d+)\s+(.+?)\s+\((.*)\)\s*$');

  // `#00 abs 0000007938a1c2f0 virt 00000000002cc2f0 _kDart...+0x24b2f0`
  static final RegExp _obfuscatedFrame = RegExp(
    r'^\s*#(\d+)\s+abs\s+([0-9a-fA-F]+)'
    r'(?:\s+virt\s+([0-9a-fA-F]+))?'
    r'(?:\s+(\S.*?))?\s*$',
  );

  // `    at Object.foo (http://host/main.dart.js:12:5)` / `    at foo`
  static final RegExp _jsV8Frame =
      RegExp(r'^\s*at\s+(?:(.+?)\s+\((.+)\)|(.+?))\s*$');

  // `foo@http://host/main.dart.js:12:5`
  static final RegExp _jsMozillaFrame = RegExp(r'^\s*([^@\s]*)@(\S+)\s*$');

  // `<uri>:<line>:<column>` where `<uri>` may itself contain colons.
  static final RegExp _location = RegExp(r'^(.*?)(?::(\d+))?(?::(\d+))?$');

  static final RegExp _buildId = RegExp("build_id:\\s*'([0-9a-fA-F]+)'");
  static final RegExp _os = RegExp(r'\bos:\s*(\S+)');
  static final RegExp _arch = RegExp(r'\barch:\s*(\S+)');
  static final RegExp _isolateDsoBase =
      RegExp(r'\bisolate_dso_base:\s*([0-9a-fA-F]+)');
  static final RegExp _vmDsoBase = RegExp(r'\bvm_dso_base:\s*([0-9a-fA-F]+)');
  static final RegExp _isolateInstructions =
      RegExp(r'\bisolate_instructions:\s*([0-9a-fA-F]+)');
  static final RegExp _vmInstructions =
      RegExp(r'\bvm_instructions:\s*([0-9a-fA-F]+)');

  /// Parses [stackTrace] into frames plus the obfuscation header.
  ///
  /// Parsing never throws: any line that does not match a known shape is kept
  /// as an opaque [DartStackFrame] whose [DartStackFrame.raw] is the line
  /// itself, so no information is silently dropped.
  static DartStackTrace parse(Object? stackTrace) {
    if (stackTrace == null) {
      return empty;
    }
    final raw = stackTrace.toString();
    if (raw.trim().isEmpty) {
      return empty;
    }

    final frames = <DartStackFrame>[];
    for (final line in LineSplitter.split(raw)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed == '<asynchronous suspension>') {
        frames.add(DartStackFrame.asynchronousSuspension(line));
        continue;
      }
      if (_isHeaderLine(trimmed)) {
        continue;
      }

      final frame = _parseObfuscated(line) ??
          _parseVm(line) ??
          _parseJs(line) ??
          DartStackFrame(raw: line);
      frames.add(frame);
    }

    return DartStackTrace(
      raw: raw,
      frames: List<DartStackFrame>.unmodifiable(frames),
      buildId: _buildId.firstMatch(raw)?.group(1),
      os: _os.firstMatch(raw)?.group(1),
      architecture: _arch.firstMatch(raw)?.group(1),
      isolateDsoBase: _isolateDsoBase.firstMatch(raw)?.group(1),
      vmDsoBase: _vmDsoBase.firstMatch(raw)?.group(1),
      isolateInstructions: _isolateInstructions.firstMatch(raw)?.group(1),
      vmInstructions: _vmInstructions.firstMatch(raw)?.group(1),
    );
  }

  static bool _isHeaderLine(String trimmed) {
    if (trimmed.startsWith('***')) {
      return true;
    }
    return trimmed.startsWith('pid:') ||
        trimmed.startsWith('os:') ||
        trimmed.startsWith('build_id:') ||
        trimmed.startsWith('isolate_dso_base:') ||
        trimmed.startsWith('vm_dso_base:') ||
        trimmed.startsWith('isolate_instructions:') ||
        trimmed.startsWith('vm_instructions:') ||
        trimmed.startsWith('version:') ||
        trimmed.startsWith('Warning: This VM has been configured');
  }

  static DartStackFrame? _parseObfuscated(String line) {
    final match = _obfuscatedFrame.firstMatch(line);
    if (match == null) {
      return null;
    }
    return DartStackFrame(
      raw: line,
      index: int.tryParse(match.group(1)!),
      absoluteAddress: match.group(2),
      virtualAddress: match.group(3),
      symbol: match.group(4),
    );
  }

  static DartStackFrame? _parseVm(String line) {
    final match = _vmFrame.firstMatch(line);
    if (match == null) {
      return null;
    }
    final location = match.group(3) ?? '';
    final parsed = _parseLocation(location);
    return DartStackFrame(
      raw: line,
      index: int.tryParse(match.group(1)!),
      member: match.group(2),
      uri: parsed.uri,
      line: parsed.line,
      column: parsed.column,
    );
  }

  static DartStackFrame? _parseJs(String line) {
    final v8 = _jsV8Frame.firstMatch(line);
    if (v8 != null) {
      final member = v8.group(1) ?? v8.group(3);
      final location = v8.group(2);
      if (location == null) {
        return DartStackFrame(raw: line, member: member);
      }
      final parsed = _parseLocation(location);
      return DartStackFrame(
        raw: line,
        member: member,
        uri: parsed.uri,
        line: parsed.line,
        column: parsed.column,
      );
    }

    final moz = _jsMozillaFrame.firstMatch(line);
    if (moz != null) {
      final parsed = _parseLocation(moz.group(2)!);
      final member = moz.group(1);
      return DartStackFrame(
        raw: line,
        member: member != null && member.isEmpty ? '<anonymous>' : member,
        uri: parsed.uri,
        line: parsed.line,
        column: parsed.column,
      );
    }
    return null;
  }

  static _Location _parseLocation(String location) {
    if (location.isEmpty) {
      return const _Location(null, null, null);
    }
    final match = _location.firstMatch(location);
    if (match == null) {
      return _Location(location, null, null);
    }
    final uri = match.group(1);
    final first = match.group(2);
    final second = match.group(3);
    if (uri == null || uri.isEmpty) {
      return _Location(location, null, null);
    }
    // With a single numeric tail the VM prints `<uri>:<line>`; with two it
    // prints `<uri>:<line>:<column>`.
    if (second != null) {
      return _Location(uri, int.tryParse(first!), int.tryParse(second));
    }
    if (first != null) {
      return _Location(uri, int.tryParse(first), null);
    }
    return _Location(uri, null, null);
  }

  /// Returns a copy holding at most [maxFrames] frames.
  ///
  /// The frames nearest the throw are kept, since a Dart trace is printed
  /// newest-first and those are the ones that explain the failure.
  ///
  /// [raw] is deliberately left untouched. It is the only artefact an
  /// obfuscated trace can be decoded from, and trimming it here would silently
  /// destroy that; callers that need to bound the verbatim text should do so
  /// where it is written, not by rewriting the trace.
  DartStackTrace limitFrames(int maxFrames) {
    if (maxFrames <= 0 || frames.length <= maxFrames) {
      return this;
    }
    return DartStackTrace(
      raw: raw,
      frames: List<DartStackFrame>.unmodifiable(frames.take(maxFrames)),
      buildId: buildId,
      os: os,
      architecture: architecture,
      isolateDsoBase: isolateDsoBase,
      vmDsoBase: vmDsoBase,
      isolateInstructions: isolateInstructions,
      vmInstructions: vmInstructions,
    );
  }

  /// Serializes the trace for the method channel and the HTTP transport.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'raw': raw,
      'frames': frames.map((DartStackFrame f) => f.toMap()).toList(),
      'obfuscated': isObfuscated,
      if (buildId != null) 'buildId': buildId,
      if (os != null) 'os': os,
      if (architecture != null) 'arch': architecture,
      if (isolateDsoBase != null) 'isolateDsoBase': isolateDsoBase,
      if (vmDsoBase != null) 'vmDsoBase': vmDsoBase,
      if (isolateInstructions != null)
        'isolateInstructions': isolateInstructions,
      if (vmInstructions != null) 'vmInstructions': vmInstructions,
    };
  }

  @override
  String toString() => raw;
}

@immutable
class _Location {
  const _Location(this.uri, this.line, this.column);

  final String? uri;
  final int? line;
  final int? column;
}
