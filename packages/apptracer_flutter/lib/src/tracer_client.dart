import 'dart:async';
import 'dart:convert';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';

import 'breadcrumb_buffer.dart';
import 'deduplicator.dart';
import 'error_handler_chain.dart';
import 'error_normalizer.dart';

/// The Dart-side engine behind the [Tracer] facade.
///
/// Kept as an ordinary object rather than a pile of statics so that the
/// handler-chaining, deduplication and breadcrumb rules can be tested without
/// process-wide state. Application code should use [Tracer].
class TracerClient {
  /// Creates a client.
  ///
  /// [platform] defaults to the registered platform implementation, resolved
  /// lazily so that a plugin registered after construction is still picked up.
  TracerClient({
    TracerPlatform? platform,
    ErrorHandlerBindings bindings = const ErrorHandlerBindings.live(),
    EventDeduplicator? deduplicator,
  })  : _platformOverride = platform,
        _bindings = bindings,
        _deduplicator = deduplicator ?? EventDeduplicator();

  final TracerPlatform? _platformOverride;
  final ErrorHandlerBindings _bindings;
  final EventDeduplicator _deduplicator;

  TracerOptions _options = const TracerOptions();
  BreadcrumbBuffer _breadcrumbs = BreadcrumbBuffer(maxLength: 100);
  final Map<String, String> _customKeys = <String, String>{};
  ErrorHandlerChain? _chain;
  bool _started = false;

  /// The platform implementation in use.
  TracerPlatform get platform => _platformOverride ?? TracerPlatform.instance;

  /// The options this client was started with.
  TracerOptions get options => _options;

  /// Whether the client started and collection is running.
  bool get isEnabled => _started && platform.isEnabled;

  /// The buffered breadcrumbs, oldest first.
  List<TracerBreadcrumb> get breadcrumbs => _breadcrumbs.entries;

  /// The custom keys currently applied to every event.
  Map<String, String> get customKeys =>
      Map<String, String>.unmodifiable(_customKeys);

  /// Whether the error handlers are installed.
  @visibleForTesting
  bool get hasInstalledHandlers => _chain?.isInstalled ?? false;

  /// Starts collection with [options].
  ///
  /// Never throws. A platform SDK that fails to start leaves the client
  /// disabled; the host application keeps running either way.
  Future<void> start(TracerOptions options) async {
    _options = options;
    _breadcrumbs = BreadcrumbBuffer(maxLength: options.maxBreadcrumbs);
    _customKeys
      ..clear()
      ..addAll(options.initialCustomKeys);

    if (!options.isCollectionEnabled) {
      _log('collection disabled by TracerOptions.isCollectionEnabled');
      _started = false;
      return;
    }

    try {
      await platform.initialize(options);
    } catch (error, stackTrace) {
      _log('platform initialization failed: $error');
      _log('$stackTrace');
      _started = false;
      return;
    }

    _started = true;

    if (_customKeys.isNotEmpty) {
      for (final entry in _customKeys.entries) {
        await _guard(
          () => platform.setCustomKey(key: entry.key, value: entry.value),
        );
      }
    }

    _installHandlers();
    _log('started with backend "${platform.backendName}"');
  }

  void _installHandlers() {
    if (!_options.captureFlutterErrors &&
        !_options.capturePlatformDispatcherErrors) {
      return;
    }
    final chain = _chain ??= ErrorHandlerChain(
      onFlutterError: recordFlutterError,
      onPlatformError: recordUnhandledError,
      bindings: _bindings,
      debug: _options.debug,
    );
    chain.install(
      captureFlutterErrors: _options.captureFlutterErrors,
      capturePlatformDispatcherErrors: _options.capturePlatformDispatcherErrors,
    );
  }

  /// Stops collection, removes the installed handlers and restores whatever
  /// was there before.
  ///
  /// Idempotent: calling it when not started does nothing.
  Future<void> stop() async {
    _chain?.restore();
    _chain = null;
    _deduplicator.clear();
    _breadcrumbs.clear();
    if (_started) {
      await _guard(platform.stopCollection);
    }
    _started = false;
  }

  /// Reports an error raised by the guarded zone.
  void handleZoneError(Object error, StackTrace stackTrace) =>
      recordUnhandledError(error, stackTrace);

  /// Reports an error that no application code caught.
  ///
  /// Reached from the guarded zone and from
  /// `PlatformDispatcher.instance.onError`. Severity follows
  /// [TracerOptions.reportUnhandledErrorsAsFatal], which defaults to `false`:
  /// an uncaught Dart error leaves the process running, and reporting it as
  /// fatal would count a crash that never happened against the crash-free
  /// metric.
  void recordUnhandledError(Object error, StackTrace stackTrace) {
    final fatal = _options.reportUnhandledErrorsAsFatal;
    unawaited(
      recordError(
        error,
        stackTrace,
        severity: fatal ? TracerSeverity.fatal : TracerSeverity.error,
        fatal: fatal,
      ),
    );
  }

  /// Reports a `FlutterErrorDetails`.
  void recordFlutterError(FlutterErrorDetails details) {
    if (!isEnabled) {
      return;
    }
    if (_deduplicator.isDuplicate(details.exception, details.stack)) {
      return;
    }
    final fatal = _options.reportUnhandledErrorsAsFatal;
    final event = ErrorNormalizer.fromFlutterError(
      details,
      severity: fatal ? TracerSeverity.fatal : TracerSeverity.error,
      fatal: fatal,
      customKeys: customKeys,
      breadcrumbs: breadcrumbs,
    );
    unawaited(_dispatch(event));
  }

  /// Reports [error] with [stackTrace].
  Future<void> recordError(
    Object? error,
    Object? stackTrace, {
    TracerSeverity severity = TracerSeverity.error,
    bool fatal = false,
    String? issueKey,
    Map<String, String> customKeys = const <String, String>{},
  }) async {
    if (!isEnabled) {
      return;
    }
    if (_deduplicator.isDuplicate(error, stackTrace)) {
      return;
    }
    final merged = <String, String>{...this.customKeys, ...customKeys};
    final event = ErrorNormalizer.fromError(
      error,
      stackTrace,
      severity: severity,
      fatal: fatal,
      issueKey: issueKey,
      customKeys: merged,
      breadcrumbs: breadcrumbs,
    );
    await _dispatch(event);
  }

  Future<void> _dispatch(TracerEvent event) async {
    var outgoing = event;
    final beforeSend = _options.beforeSend;
    if (beforeSend != null) {
      try {
        final filtered = beforeSend(outgoing);
        if (filtered == null) {
          _log('event dropped by beforeSend: ${event.title}');
          return;
        }
        outgoing = filtered;
      } catch (error) {
        // A throwing hook must not take the error report down with it.
        _log('beforeSend threw, sending the original event: $error');
      }
    }

    // После beforeSend, чтобы ключ, выставленный хуком, не затирался, и до
    // отправки. Бэкенды, которые группируют сами по достаточным данным,
    // оставляют флаг false и ключ не получают.
    if (outgoing.issueKey == null && platform.needsSyntheticIssueKey) {
      final String key = SyntheticIssueKey.forError(
        exceptionType: outgoing.exceptionType,
        frames: outgoing.stackTrace.frames,
      );
      // Ключ определяет группу в Tracer, поэтому в debug его печать экономит
      // час на вопрос «почему это событие оказалось не там, где я ждал».
      _log('issueKey synthesised for ${outgoing.exceptionType}: $key');
      outgoing = outgoing.copyWith(issueKey: key);
    }

    if (_options.attachRawStackTraceAsLog &&
        outgoing.stackTrace.raw.isNotEmpty) {
      await _guard(
        () => platform.recordLog(
          _rawStackTraceLog(outgoing, _options.maxRawStackTraceLogBytes),
        ),
      );
    }

    final limited = outgoing.stackTrace.limitFrames(_options.maxStackFrames);
    await _guard(
      () => platform.recordError(
        identical(limited, outgoing.stackTrace)
            ? outgoing
            : outgoing.copyWith(stackTrace: limited),
      ),
    );
  }

  /// Builds the verbatim stack-trace log line.
  ///
  /// An obfuscated AOT trace is a list of addresses plus a header; only the
  /// exact original text can be fed to `flutter symbolize`. Reformatting it,
  /// or sending only the parsed frames, would destroy the one artefact that
  /// makes the report decodable.
  static String _rawStackTraceLog(TracerEvent event, int maxBytes) {
    final buffer = StringBuffer()
      ..writeln('--- apptracer_flutter: verbatim Dart stack trace ---')
      ..writeln(event.title);
    if (event.stackTrace.isObfuscated) {
      buffer.writeln(
        'obfuscated build; decode with: flutter symbolize '
        '-d app.<platform>-<arch>.symbols',
      );
    }
    final prefix = buffer.toString();
    // Обфусцированный трейс уходит дословно: только его принимает
    // flutter symbolize, и он же единственный, ради которого вся эта запись
    // существует. Читаемый трейс symbolize не нужен, поэтому его номера
    // кадров можно обезвредить.
    final raw = event.stackTrace.isObfuscated
        ? event.stackTrace.raw
        : defuseFrameNumbers(event.stackTrace.raw);
    if (maxBytes <= 0) {
      return '$prefix$raw';
    }
    final budget = maxBytes - utf8.encode(prefix).length;
    if (budget <= 0) {
      return prefix;
    }
    return '$prefix${truncateToBytes(raw, budget)}';
  }

  /// Rewrites Dart frame numbers so Tracer's console cannot mistake them for
  /// log records.
  ///
  /// The console parses the event log by looking for the *next* record marker
  /// in sequence — `#3` after `#2` — and expects `#0 timestamp | text` where it
  /// finds one. A Dart stack trace numbers its frames the same way, so a trace
  /// sitting in record `#2` hands the parser a `#3` of its own a few lines
  /// down. The table view then renders nothing but
  /// «Ошибка форматирования текста … Match line error», and points at the text
  /// tab instead. Measured against a live project on 2026-08-26, and confirmed
  /// by the case that works: an obfuscated trace numbers its frames `#00`,
  /// `#01`, `#02`, so a parser hunting for `#2` never matches it.
  ///
  /// Indentation does not help — the leading space was tried first and the
  /// parser found `#3` anyway. Only removing the `#N` sequence does. Frames
  /// become `[0]`, `[1]`, which reads as a frame index and matches nothing the
  /// console looks for.
  ///
  /// Applied to readable traces only. An obfuscated AOT trace has to survive
  /// byte for byte, because `flutter symbolize` is the one thing that makes it
  /// decodable, and it is also the case the console renders correctly anyway.
  @visibleForTesting
  static String defuseFrameNumbers(String raw) =>
      raw.replaceAllMapped(_frameNumber, (Match m) => '${m[1]}[${m[2]}]');

  static final RegExp _frameNumber = RegExp(r'^(\s*)#(\d+)', multiLine: true);

  /// Truncates [text] to at most [maxBytes] UTF-8 bytes, on a line boundary.
  ///
  /// Whole lines only: half a stack frame is not a stack frame, and
  /// `flutter symbolize` parses line by line. The beginning is kept, because
  /// that is where the `build_id` header and the frames nearest the throw
  /// live. What was dropped is stated rather than left to be guessed at.
  @visibleForTesting
  static String truncateToBytes(String text, int maxBytes) {
    if (maxBytes <= 0) {
      return '';
    }
    if (utf8.encode(text).length <= maxBytes) {
      return text;
    }

    final lines = const LineSplitter().convert(text);
    // Reserve room for the marker so the result still fits the budget.
    const markerTemplate =
        '... [apptracer_flutter] truncated, 999999 more line(s); '
        'raise TracerOptions.maxRawStackTraceLogBytes';
    final reserve = utf8.encode(markerTemplate).length + 1;

    final kept = <String>[];
    var used = 0;
    for (final line in lines) {
      final cost = utf8.encode(line).length + 1;
      if (used + cost > maxBytes - reserve) {
        break;
      }
      kept.add(line);
      used += cost;
    }

    final dropped = lines.length - kept.length;
    if (kept.isEmpty) {
      return '... [apptracer_flutter] stack trace omitted, '
          '$dropped line(s) did not fit\n';
    }
    return '${kept.join('\n')}\n'
        '... [apptracer_flutter] truncated, $dropped more line(s); '
        'raise TracerOptions.maxRawStackTraceLogBytes\n';
  }

  /// Buffers [breadcrumb] and mirrors it into the platform log buffer.
  ///
  /// The mirror matters: a native crash or an ANR is captured by the native
  /// SDK, which knows nothing about the Dart-side buffer, so breadcrumbs are
  /// only present in such a report if they were written to the native log as
  /// they happened.
  void addBreadcrumb(TracerBreadcrumb breadcrumb) {
    var incoming = breadcrumb;
    final beforeBreadcrumb = _options.beforeBreadcrumb;
    if (beforeBreadcrumb != null) {
      try {
        final filtered = beforeBreadcrumb(incoming);
        if (filtered == null) {
          return;
        }
        incoming = filtered;
      } catch (error) {
        _log('beforeBreadcrumb threw, keeping the original: $error');
      }
    }
    _breadcrumbs.add(incoming);
    if (isEnabled && platform.mirrorsBreadcrumbsToLog) {
      unawaited(_guard(() => platform.recordLog(incoming.toLogLine())));
    }
  }

  /// Writes [message] straight to the platform log buffer.
  Future<void> recordLog(String message) async {
    if (!isEnabled) {
      return;
    }
    await _guard(() => platform.recordLog(message));
  }

  /// Sets a custom key on every subsequent event.
  Future<void> setCustomKey({
    required String key,
    required String value,
  }) async {
    if (key.isEmpty) {
      return;
    }
    _customKeys[key] = value;
    if (!isEnabled) {
      return;
    }
    await _guard(() => platform.setCustomKey(key: key, value: value));
  }

  /// Removes a previously set custom key.
  Future<void> removeCustomKey(String key) async {
    _customKeys.remove(key);
    if (!isEnabled) {
      return;
    }
    await _guard(() => platform.removeCustomKey(key));
  }

  /// Associates subsequent events with [userId], or clears it when `null`.
  Future<void> setUserId(String? userId) async {
    if (!isEnabled) {
      return;
    }
    await _guard(() => platform.setUserId(userId));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _log('platform call failed: $error');
    }
  }

  void _log(String message) {
    if (_options.debug) {
      debugPrint('apptracer_flutter: $message');
    }
  }
}
