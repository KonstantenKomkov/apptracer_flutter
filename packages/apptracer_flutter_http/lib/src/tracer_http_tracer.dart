import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'tracer_client_facts.dart';
import 'tracer_batch_item.dart';
import 'tracer_delivery.dart';
import 'tracer_log_buffer.dart';

/// Delivers Dart errors to Tracer's own HTTP ingest.
class TracerHttpTracer extends TracerPlatform {
  /// [httpClient], time, randomness and storage are injectable for deterministic tests.
  TracerHttpTracer({
    required this.facts,
    required this.sdkVersion,
    http.Client? httpClient,
    String backendName = 'tracer-http',
    TracerQueueStore? queueStore,
    TracerDeliveryPolicy deliveryPolicy = const TracerDeliveryPolicy(),
    TracerDeliveryListener? deliveryListener,
    DateTime Function()? clock,
    double Function()? random,
    Future<void> Function(Duration delay)? delay,
  })  : _ownsClient = httpClient == null,
        _client = httpClient ?? http.Client(),
        _backendName = backendName,
        _queueStore = queueStore ?? TracerMemoryQueueStore(),
        _policy = deliveryPolicy,
        _deliveryListener = deliveryListener,
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random().nextDouble,
        _delay = delay {
    if (_policy.maxAttempts < 1 ||
        _policy.maxEntries < 1 ||
        _policy.maxBytes < 1 ||
        _policy.requestTimeout <= Duration.zero ||
        _policy.initialBackoff.isNegative ||
        _policy.maxBackoff.isNegative ||
        _policy.maxRetryAfter.isNegative ||
        _policy.timeToLive.isNegative) {
      throw ArgumentError('Invalid HTTP delivery limits or durations');
    }
  }

  /// Default ingest host without a URL scheme.
  static const String defaultHost = 'sdk-api.apptracer.ru';

  /// Client facts serialized into each event.
  final TracerClientFacts facts;

  /// Package version sent as `tracerSdkVersion`.
  final String sdkVersion;

  http.Client _client;
  bool _clientClosed = false;
  final bool _ownsClient;
  final String _backendName;
  final TracerQueueStore _queueStore;
  final TracerDeliveryPolicy _policy;
  final TracerDeliveryListener? _deliveryListener;
  String? _apiUrl;
  final DateTime Function() _clock;
  final double Function() _random;
  final Future<void> Function(Duration delay)? _delay;

  String? _appToken;
  String _host = defaultHost;
  String _scheme = 'https';
  String _environment = 'prod';
  String _versionName = '0.0.0';
  int _versionCode = 1;
  bool _enabled = false;
  bool _debug = false;
  int _generation = 0;

  final TracerLogBuffer _logs = TracerLogBuffer();
  final Map<String, String> _customKeys = <String, String>{};
  String? _userId;

  final List<_QueueEntry> _queue = <_QueueEntry>[];
  Future<void> _mutation = Future<void>.value();
  int? _pumpingGeneration;
  Timer? _retryTimer;
  int _scheduleId = 0;
  int? _wakeAt;
  Completer<void>? _abort;
  bool _storageFailed = false;
  bool _canPersist = false;
  bool _cleanupPending = false;
  String _account = '';
  int _nextId = 1;

  @override
  String get backendName => _backendName;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get mirrorsBreadcrumbsToLog => true;

  @override
  void configureDelivery(TracerOptions options,
      {bool activateListener = true}) {
    if (!options.isCollectionEnabled ||
        options.resolvedAppToken != _appToken ||
        options.apiUrl != _apiUrl) {
      _endSession();
    }
    deliveryListener =
        activateListener ? options.deliveryListener ?? _deliveryListener : null;
  }

  @override
  Future<void> initialize(TracerOptions options) async {
    _debug = options.debug;
    configureDelivery(options);
    if (!options.isCollectionEnabled) {
      await stopCollection();
      return;
    }

    final String? token = options.resolvedAppToken;
    if (token == null || token.isEmpty) {
      _log('TracerOptions.appToken is required on web; collection is off.');
      await stopCollection();
      return;
    }

    _endSession();
    final generation = _generation;
    final host = hostFrom(options.apiUrl) ?? defaultHost;
    final url = Uri.tryParse(options.apiUrl ?? '');
    final loopback =
        const {'localhost', '127.0.0.1', '::1'}.contains(url?.host);
    _scheme = url?.scheme == 'http' && loopback ? 'http' : 'https';
    _host = host;
    _account = sha256
        .convert(utf8.encode(jsonEncode([_scheme, host, token])))
        .toString();
    _appToken = token;
    _apiUrl = options.apiUrl;
    _environment = options.resolvedEnvironment;
    _versionName = options.release ?? _versionName;
    _versionCode =
        int.tryParse(options.dist ?? '') ?? _versionCodeFrom(_versionName);
    final ready = await _synchronized(() async {
      if (generation != _generation) return false;
      if (_cleanupPending && !await _clearStore(generation)) return false;
      await _load(generation);
      return generation == _generation;
    });
    if (!ready || generation != _generation) return;
    if (_ownsClient && _clientClosed) {
      _client = http.Client();
      _clientClosed = false;
    }
    _enabled = true;
    unawaited(_pump());
  }

  void _endSession() {
    ++_generation;
    _enabled = false;
    ++_scheduleId;
    _wakeAt = null;
    _retryTimer?.cancel();
    if (_abort?.isCompleted == false) _abort!.complete();
    _abort = null;
    _appToken = null;
    _apiUrl = null;
    _logs.clear();
    _customKeys.clear();
    _userId = null;
    _queue.clear();
  }

  Future<bool> _clearStore(int generation) async {
    try {
      await _queueStore.clear();
      _cleanupPending = false;
      return true;
    } on Object {
      _cleanupPending = true;
      if (generation == _generation) {
        _diagnose(TracerDeliveryState.failed, reason: 'storage_clear_failed');
      }
      return false;
    }
  }

  @override
  Future<void> stopCollection() async {
    await stopAndClearCollection();
  }

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) async {
    await initialize(options);
    if (_cleanupPending) {
      return TracerCollectionResult(TracerCollectionState.error,
          reason: 'storage_clear_failed',
          failureReported: deliveryListener != null);
    }
    return getCollectionState();
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() async {
    _endSession();
    if (_ownsClient && !_clientClosed) {
      _client.close();
      _clientClosed = true;
    }
    final generation = _generation;
    final cleared = await _synchronized(() => _clearStore(generation));
    return cleared
        ? const TracerCollectionResult(TracerCollectionState.disabled)
        : TracerCollectionResult(TracerCollectionState.error,
            reason: 'storage_clear_failed',
            failureReported: deliveryListener != null);
  }

  /// Queues the event without waiting for its first HTTP response.
  @override
  Future<void> recordError(TracerEvent event) async {
    if (!_enabled) return;
    final generation = _generation;
    final item = buildBatchItem(
      event: event,
      facts: facts,
      versionName: _versionName,
      versionCode: _versionCode,
      environment: _environment,
      sdkVersion: sdkVersion,
      customKeys: _customKeys,
      userId: _userId,
      logsFile: _logs.encode(),
    );
    final payload = jsonEncode(<Map<String, Object?>>[item]);
    final entry = _QueueEntry(
      id: '${_nowMicros()}-${_nextId++}',
      account: _account,
      payload: payload,
      createdAt: _nowMicros(),
      nextAttemptAt: _nowMicros(),
    );
    await _synchronized(() async {
      if (!_enabled || generation != _generation) {
        return;
      }
      final expired = _dropExpired();
      if (generation != _generation) return;
      if (entry.bytes > _policy.maxBytes) {
        if (expired) await _persist();
        if (generation != _generation) return;
        _diagnose(TracerDeliveryState.dropped, reason: 'event_too_large');
        return;
      }
      _queue.add(entry);
      _trimToLimits();
      if (generation != _generation) return;
      await _persist();
      if (generation != _generation) return;
      _diagnose(TracerDeliveryState.queued,
          reason: _storageFailed ? 'memory_only' : 'persisted');
    });
    if (_enabled && generation == _generation) unawaited(_pump());
  }

  Future<void> _pump() async {
    final generation = _generation;
    if (!_enabled || _pumpingGeneration == generation) return;
    _pumpingGeneration = generation;
    try {
      while (_enabled && generation == _generation) {
        final entry = await _synchronized(() async {
          if (generation != _generation) return null;
          if (_dropExpired()) await _persist();
          final head = _queue.firstOrNull;
          if (head == null || _scheduleIfWaiting(head)) return null;
          // A reload can interrupt an upload before a response is observed.
          // Reserve its attempt and recovery delay before starting the request.
          head.attempts++;
          head.nextAttemptAt = _nowMicros() +
              _backoff(head.attempts, const _AttemptResult()).inMicroseconds;
          await _persist();
          return head;
        });
        if (generation != _generation || entry == null) return;
        if (!identical(_queue.firstOrNull, entry)) continue;
        if (_expired(entry)) continue;
        final attempt = entry.attempts;
        final outcome = await _send(entry);
        await _synchronized(() async {
          if (!_enabled || generation != _generation) return;
          if (!identical(_queue.firstOrNull, entry)) return;
          if (outcome.sent) {
            _queue.removeAt(0);
            await _persist();
            if (generation != _generation) return;
            _diagnose(TracerDeliveryState.sent,
                attempt: attempt, reason: 'http_${outcome.statusCode}');
            return;
          }
          if (!outcome.retryable || attempt >= _policy.maxAttempts) {
            _queue.removeAt(0);
            await _persist();
            if (generation != _generation) return;
            _diagnose(TracerDeliveryState.dropped,
                attempt: attempt,
                reason: outcome.retryable ? 'retry_exhausted' : outcome.reason);
            return;
          }
          entry.nextAttemptAt =
              _nowMicros() + _backoff(attempt, outcome).inMicroseconds;
          await _persist();
          if (generation != _generation) return;
          _diagnose(TracerDeliveryState.retry,
              attempt: attempt, reason: outcome.reason);
          if (generation == _generation) _scheduleIfWaiting(entry);
        });
      }
    } finally {
      if (_pumpingGeneration == generation) _pumpingGeneration = null;
    }
  }

  Future<_AttemptResult> _send(_QueueEntry entry) async {
    final query = <String, String>{
      'crashToken': _appToken!,
      'compressType': 'NONE',
      'sdkVersion': sdkVersion,
    };
    final abort = Completer<void>();
    _abort = abort;
    try {
      final uri = _scheme == 'http'
          ? Uri.http(_host, '/api/crash/uploadBatch', query)
          : Uri.https(_host, '/api/crash/uploadBatch', query);
      final request =
          http.AbortableRequest('POST', uri, abortTrigger: abort.future)
            ..headers['Content-Type'] = 'application/octet-stream'
            ..bodyBytes = utf8.encode(entry.payload);
      final response = await _client.send(request).then((response) async {
        await response.stream.drain<void>();
        return response;
      }).timeout(_policy.requestTimeout, onTimeout: () {
        if (!abort.isCompleted) abort.complete();
        throw TimeoutException('upload');
      });
      if (response.statusCode < 400) {
        _log('upload accepted by HTTP: ${response.statusCode}');
        return _AttemptResult.sent(response.statusCode);
      }
      final retryable = response.statusCode == 408 ||
          response.statusCode == 429 ||
          const <int>{500, 502, 503, 504}.contains(response.statusCode);
      _log('upload rejected: ${response.statusCode}');
      return _AttemptResult(
        statusCode: response.statusCode,
        retryable: retryable,
        reason: 'http_${response.statusCode}',
        retryAfter: response.headers['retry-after'],
      );
    } on Object catch (error) {
      _log('upload failed: ${error.runtimeType}');
      return const _AttemptResult(
          retryable: true, reason: 'network_or_timeout');
    } finally {
      if (identical(_abort, abort)) _abort = null;
    }
  }

  Duration _backoff(int attempt, _AttemptResult outcome) {
    final exponent = math.min(attempt - 1, 30);
    final baseMs = math
        .min(
          _policy.initialBackoff.inMilliseconds * math.pow(2, exponent),
          _policy.maxBackoff.inMilliseconds.toDouble(),
        )
        .toInt();
    final jitteredMs = (baseMs * (0.5 + _random() * 0.5)).round();
    var result = Duration(milliseconds: jitteredMs);
    final retryAfter = _retryAfter(outcome.retryAfter);
    if (retryAfter != null && retryAfter > result) result = retryAfter;
    if (result > _policy.maxRetryAfter) result = _policy.maxRetryAfter;
    return result;
  }

  Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final header = value.trim();
    if (RegExp(r'^\d+$').hasMatch(header)) {
      final seconds = int.tryParse(header);
      if (seconds == null || seconds > _policy.maxRetryAfter.inSeconds) {
        return _policy.maxRetryAfter;
      }
      return Duration(seconds: seconds);
    }
    try {
      return parseHttpDate(header).difference(_clock().toUtc());
    } on FormatException {
      return null;
    }
  }

  bool _scheduleIfWaiting(_QueueEntry entry) {
    final at = math.min(entry.nextAttemptAt,
        entry.createdAt + _policy.timeToLive.inMicroseconds);
    final wait = Duration(microseconds: at - _nowMicros());
    if (wait <= Duration.zero) return false;
    if (_wakeAt == at) return true;
    _wakeAt = at;
    final id = ++_scheduleId;
    _retryTimer?.cancel();
    void wake() {
      if (id != _scheduleId || !_enabled) return;
      _wakeAt = null;
      unawaited(_pump());
    }

    final delay = _delay;
    if (delay == null) {
      _retryTimer = Timer(wait, wake);
    } else {
      unawaited(Future<void>.sync(() => delay(wait)).then((_) => wake(),
          onError: (Object _) {
        if (id != _scheduleId) return;
        _diagnose(TracerDeliveryState.failed, reason: 'retry_schedule_failed');
        _retryTimer = Timer(wait, wake);
      }));
    }
    return true;
  }

  Future<void> _load(int generation) async {
    _canPersist = false;
    List<TracerQueueRecord> records;
    try {
      records = await _queueStore.load();
    } on Object {
      if (generation != _generation) return;
      _storageFailed = true;
      _diagnose(TracerDeliveryState.failed, reason: 'storage_unavailable');
      return;
    }
    if (generation != _generation) return;
    _canPersist = true;
    var changed = false;
    for (final record in records) {
      if (generation != _generation) return;
      final entry = _QueueEntry.tryParse(record);
      if (entry == null) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'malformed_record');
      } else if (entry.account != _account) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'account_mismatch');
      } else if (_expired(entry)) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'ttl_expired');
      } else if (entry.bytes > _policy.maxBytes ||
          entry.attempts >= _policy.maxAttempts) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'policy_limit');
      } else {
        _queue.add(entry);
      }
    }
    if (generation != _generation) return;
    if ((_trimToLimits() || changed) && generation == _generation) {
      await _persist();
    }
  }

  bool _trimToLimits() {
    final length = _queue.length;
    var bytes = _queueBytes();
    final generation = _generation;
    while (generation == _generation &&
        (_queue.length > _policy.maxEntries || bytes > _policy.maxBytes)) {
      final dropped = _queue.removeAt(0);
      bytes -= dropped.bytes;
      _diagnose(TracerDeliveryState.dropped, reason: 'queue_overflow');
    }
    return length != _queue.length;
  }

  bool _dropExpired() {
    final length = _queue.length;
    _queue.removeWhere(_expired);
    final removed = length - _queue.length;
    final generation = _generation;
    for (var i = 0; i < removed && generation == _generation; ++i) {
      _diagnose(TracerDeliveryState.dropped, reason: 'ttl_expired');
    }
    return removed > 0;
  }

  bool _expired(_QueueEntry entry) =>
      _nowMicros() - entry.createdAt >= _policy.timeToLive.inMicroseconds;

  int _queueBytes() => _queue.fold(0, (sum, entry) => sum + entry.bytes);

  Future<void> _persist() async {
    if (!_canPersist) return;
    final generation = _generation;
    try {
      await _queueStore.save(
          _queue.map((entry) => entry.toRecord()).toList(growable: false));
      if (generation == _generation) _storageFailed = false;
    } on Object {
      if (generation != _generation) return;
      _storageFailed = true;
      _diagnose(TracerDeliveryState.failed, reason: 'storage_unavailable');
    }
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutation = _mutation.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  int _nowMicros() => _clock().toUtc().microsecondsSinceEpoch;

  @override
  Future<void> recordLog(String message) async {
    if (_enabled) _logs.add(message);
  }

  @override
  Future<void> setCustomKey(
      {required String key, required String value}) async {
    if (_enabled) _customKeys[key] = value;
  }

  @override
  Future<void> removeCustomKey(String key) async {
    if (_enabled) _customKeys.remove(key);
  }

  @override
  Future<void> setUserId(String? userId) async {
    if (_enabled) _userId = userId;
  }

  /// Converts a bare host or full API URL to the ingest host.
  @visibleForTesting
  static String? hostFrom(String? value) {
    if (value == null || value.isEmpty) return null;
    final Uri? parsed = Uri.tryParse(value);
    if (parsed != null && parsed.host.isNotEmpty) {
      final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
      return parsed.hasPort ? '$host:${parsed.port}' : host;
    }
    return value;
  }

  static int _versionCodeFrom(String versionName) {
    final Match? match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(versionName);
    if (match == null) return 1;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    return major * 10000 + minor * 100 + patch;
  }

  void _diagnose(TracerDeliveryState state,
      {int attempt = 0, required String reason}) {
    TracerDeliveryDiagnostic(state,
            attempt: attempt, reason: reason, backend: _backendName)
        .notify(deliveryListener);
  }

  void _log(String message) {
    if (_debug) {
      // ignore: avoid_print
      print('apptracer_flutter: $message');
    }
  }
}

class _QueueEntry {
  _QueueEntry({
    required this.id,
    required this.account,
    required this.payload,
    required this.createdAt,
    required this.nextAttemptAt,
    this.attempts = 0,
  });

  final String id;
  final String account;
  final String payload;
  final int createdAt;
  int nextAttemptAt;
  int attempts;

  late final int bytes = utf8.encode(payload).length;

  TracerQueueRecord toRecord() => <String, Object?>{
        'id': id,
        'account': account,
        'payload': payload,
        'createdAt': createdAt,
        'nextAttemptAt': nextAttemptAt,
        'attempts': attempts,
      };

  static _QueueEntry? tryParse(TracerQueueRecord record) {
    final id = record['id'];
    final account = record['account'];
    final payload = record['payload'];
    final createdAt = record['createdAt'];
    final nextAttemptAt = record['nextAttemptAt'];
    final attempts = record['attempts'];
    if (id is! String ||
        id.isEmpty ||
        account is! String ||
        payload is! String) {
      return null;
    }
    if (createdAt is! int ||
        nextAttemptAt is! int ||
        attempts is! int ||
        attempts < 0) {
      return null;
    }
    try {
      if (jsonDecode(payload) is! List<dynamic>) return null;
    } on Object {
      return null;
    }
    return _QueueEntry(
      id: id,
      account: account,
      payload: payload,
      createdAt: createdAt,
      nextAttemptAt: nextAttemptAt,
      attempts: attempts,
    );
  }
}

class _AttemptResult {
  const _AttemptResult({
    this.statusCode = 0,
    this.retryable = false,
    this.reason = 'sent',
    this.retryAfter,
  });

  const _AttemptResult.sent(int statusCode)
      : this(statusCode: statusCode, retryable: false, reason: 'sent');

  final int statusCode;
  final bool retryable;
  final String reason;
  final String? retryAfter;

  bool get sent => statusCode >= 100 && statusCode < 400 && reason == 'sent';
}
