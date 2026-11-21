import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
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
        _delay = delay ?? Future<void>.delayed;

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
  final DateTime Function() _clock;
  final double Function() _random;
  final Future<void> Function(Duration delay) _delay;

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
  bool _loaded = false;
  Future<void>? _loadFuture;
  Future<void> _mutation = Future<void>.value();
  bool _pumping = false;
  bool _scheduled = false;
  bool _storageFailed = false;
  int _nextId = 1;

  @override
  String get backendName => _backendName;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get mirrorsBreadcrumbsToLog => true;

  @override
  Future<void> initialize(TracerOptions options) async {
    _debug = options.debug;
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

    if (_ownsClient && _clientClosed) {
      _client = http.Client();
      _clientClosed = false;
    }
    ++_generation;
    _enabled = true;
    _appToken = token;
    _host = hostFrom(options.apiUrl) ?? defaultHost;
    _scheme =
        Uri.tryParse(options.apiUrl ?? '')?.scheme == 'http' ? 'http' : 'https';
    _environment = options.resolvedEnvironment;
    _versionName = options.release ?? _versionName;
    _versionCode =
        int.tryParse(options.dist ?? '') ?? _versionCodeFrom(_versionName);
    _loaded = false;
    _loadFuture = null;
    _scheduled = false;
    _queue.clear();
    unawaited(_pump());
  }

  @override
  Future<void> stopCollection() async {
    ++_generation;
    _enabled = false;
    _scheduled = false;
    _appToken = null;
    _logs.clear();
    _customKeys.clear();
    _userId = null;
    for (final entry in _queue) {
      if (!entry.attempted.isCompleted) entry.attempted.complete();
    }
    _queue.clear();
    _loaded = true;
    _loadFuture = null;
    try {
      await _queueStore.clear();
    } on Object {
      _diagnose(TracerDeliveryState.failed, reason: 'storage_clear_failed');
    }
    if (_ownsClient && !_clientClosed) {
      _client.close();
      _clientClosed = true;
    }
  }

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) async {
    await initialize(options);
    return getCollectionState();
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() async {
    await stopCollection();
    return const TracerCollectionResult(TracerCollectionState.disabled);
  }

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
      account: _accountFingerprint(),
      payload: payload,
      createdAt: _nowMicros(),
      nextAttemptAt: _nowMicros(),
    );
    await _synchronized(() async {
      await _ensureLoaded();
      if (!_enabled || generation != _generation) {
        if (!entry.attempted.isCompleted) entry.attempted.complete();
        return;
      }
      _dropExpired();
      if (entry.bytes > _policy.maxBytes) {
        if (!entry.attempted.isCompleted) entry.attempted.complete();
        _diagnose(TracerDeliveryState.dropped, reason: 'event_too_large');
        return;
      }
      _queue.add(entry);
      while (_queue.length > _policy.maxEntries ||
          _queueBytes() > _policy.maxBytes) {
        final dropped = _queue.removeAt(0);
        if (!dropped.attempted.isCompleted) dropped.attempted.complete();
        _diagnose(TracerDeliveryState.dropped, reason: 'queue_overflow');
      }
      await _persist();
      _diagnose(TracerDeliveryState.queued,
          reason: _storageFailed ? 'memory_only' : 'persisted');
    });
    if (_enabled && generation == _generation) await _pump();
    await entry.attempted.future;
  }

  Future<void> _pump() async {
    if (_pumping || !_enabled) return;
    _pumping = true;
    try {
      while (_enabled) {
        await _ensureLoaded();
        if (!_enabled || _queue.isEmpty) return;
        final entry = _queue.first;
        final wait = entry.nextAttemptAt - _nowMicros();
        if (wait > 0) {
          _schedule(Duration(microseconds: wait));
          return;
        }
        final generation = _generation;
        final attempt = entry.attempts + 1;
        final outcome = await _send(entry, attempt);
        if (!entry.attempted.isCompleted) entry.attempted.complete();
        await _synchronized(() async {
          if (!_enabled || generation != _generation) return;
          if (_queue.isEmpty || _queue.first.id != entry.id) return;
          if (outcome.sent) {
            _queue.removeAt(0);
            await _persist();
            _diagnose(TracerDeliveryState.sent,
                attempt: attempt, reason: 'http_${outcome.statusCode}');
            return;
          }
          if (!outcome.retryable || attempt >= _policy.maxAttempts) {
            _queue.removeAt(0);
            await _persist();
            _diagnose(TracerDeliveryState.dropped,
                attempt: attempt,
                reason: outcome.retryable ? 'retry_exhausted' : outcome.reason);
            return;
          }
          entry.attempts = attempt;
          entry.nextAttemptAt =
              _nowMicros() + _backoff(attempt, outcome).inMicroseconds;
          await _persist();
          _diagnose(TracerDeliveryState.retry,
              attempt: attempt, reason: outcome.reason);
          _schedule(Duration(microseconds: entry.nextAttemptAt - _nowMicros()));
        });
        if (_scheduled) return;
      }
    } finally {
      _pumping = false;
    }
  }

  Future<_AttemptResult> _send(_QueueEntry entry, int attempt) async {
    final query = <String, String>{
      'crashToken': _appToken!,
      'compressType': 'NONE',
      'sdkVersion': sdkVersion,
    };
    final uri = _scheme == 'http'
        ? Uri.http(_host, '/api/crash/uploadBatch', query)
        : Uri.https(_host, '/api/crash/uploadBatch', query);
    try {
      final response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/octet-stream'
            },
            body: utf8.encode(entry.payload),
          )
          .timeout(_policy.requestTimeout);
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
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: math.max(0, seconds));
    final date = DateTime.tryParse(value);
    if (date == null) return null;
    return Duration(
        microseconds: math.max(0, date.microsecondsSinceEpoch - _nowMicros()));
  }

  void _schedule(Duration delay) {
    if (_scheduled || !_enabled) return;
    _scheduled = true;
    final generation = _generation;
    unawaited(Future<void>.sync(() => _delay(delay)).then((_) {
      if (generation != _generation) return;
      _scheduled = false;
      if (_enabled) unawaited(_pump());
    }).catchError((_) {
      if (generation == _generation) {
        _scheduled = false;
        _diagnose(TracerDeliveryState.failed, reason: 'retry_schedule_failed');
      }
    }));
  }

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final existing = _loadFuture;
    if (existing != null) return existing;
    final generation = _generation;
    final future = _load(generation);
    _loadFuture = future;
    return future;
  }

  Future<void> _load(int generation) async {
    List<TracerQueueRecord> records;
    try {
      records = await _queueStore.load();
    } on Object {
      _storageFailed = true;
      _loaded = true;
      _diagnose(TracerDeliveryState.failed, reason: 'storage_unavailable');
      return;
    }
    if (generation != _generation) return;
    var changed = false;
    for (final record in records) {
      final entry = _QueueEntry.tryParse(record);
      if (entry == null) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'malformed_record');
      } else if (entry.account != _accountFingerprint()) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'account_mismatch');
      } else if (_expired(entry)) {
        changed = true;
        _diagnose(TracerDeliveryState.dropped, reason: 'ttl_expired');
      } else {
        _queue.add(entry);
      }
    }
    _loaded = true;
    if (changed) await _persist();
  }

  void _dropExpired() {
    _queue.removeWhere((entry) {
      if (!_expired(entry)) return false;
      if (!entry.attempted.isCompleted) entry.attempted.complete();
      _diagnose(TracerDeliveryState.dropped, reason: 'ttl_expired');
      return true;
    });
  }

  bool _expired(_QueueEntry entry) =>
      _nowMicros() - entry.createdAt >= _policy.timeToLive.inMicroseconds;

  int _queueBytes() => _queue.fold(0, (sum, entry) => sum + entry.bytes);

  Future<void> _persist() async {
    try {
      await _queueStore.save(
          _queue.map((entry) => entry.toRecord()).toList(growable: false));
      _storageFailed = false;
    } on Object {
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

  String _accountFingerprint() {
    var hash = 0;
    for (final code in '$_host|${_appToken ?? ''}'.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
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
      return parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
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
    try {
      _deliveryListener?.call(
          TracerDeliveryDiagnostic(state, attempt: attempt, reason: reason));
    } on Object {
      // Diagnostics must never affect delivery.
    }
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
  final Completer<void> attempted = Completer<void>();

  int get bytes => utf8.encode(payload).length;

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

  bool get sent => statusCode >= 200 && statusCode < 400 && reason == 'sent';
}
