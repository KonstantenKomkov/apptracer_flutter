import 'dart:convert';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'tracer_client_facts.dart';
import 'tracer_batch_item.dart';
import 'tracer_log_buffer.dart';

/// Delivers Dart errors to Tracer's own HTTP ingest.
///
/// Not the Sentry protocol, on any platform. Tracer's JavaScript SDK posts to
/// `/api/crash/uploadBatch` authenticated by the same `appToken` the Android
/// plugin uses, and a JS project is issued no Sentry DSN at all — measured
/// 2026-08-26, see `docs/web-protocol.md`. The wire format there was recovered
/// from a captured request rather than from documentation, so treat every field
/// name as observed rather than promised.
///
/// Web registers this automatically. Desktop and Aurora OS register it by hand:
/// the vendor has no SDK for the first and a C/C++ one for the second, and
/// neither is reachable from Dart.
class TracerHttpTracer extends TracerPlatform {
  /// Creates a transport.
  ///
  /// [httpClient] is injectable so tests can assert on the exact bytes sent.
  TracerHttpTracer({
    required this.facts,
    required this.sdkVersion,
    http.Client? httpClient,
    String backendName = 'tracer-http',
  })  : _ownsClient = httpClient == null,
        _client = httpClient ?? http.Client(),
        _backendName = backendName;

  /// Default ingest host. `initUrl` in the vendor's SDK always prefixes
  /// `https://`, so this is a bare host rather than a URL.
  static const String defaultHost = 'sdk-api.apptracer.ru';

  /// Client facts sent with every event.
  final TracerClientFacts facts;

  /// Reported as `tracerSdkVersion`; this package's version, not the vendor's.
  final String sdkVersion;

  final http.Client _client;
  final bool _ownsClient;
  final String _backendName;

  String? _appToken;
  String _host = defaultHost;
  String _environment = 'prod';
  String _versionName = '0.0.0';
  int _versionCode = 1;
  bool _enabled = false;
  bool _debug = false;

  final TracerLogBuffer _logs = TracerLogBuffer();
  final Map<String, String> _customKeys = <String, String>{};
  String? _userId;

  @override
  String get backendName => _backendName;

  @override
  bool get isEnabled => _enabled;

  /// Breadcrumbs are mirrored into the log, because that is where the vendor
  /// puts them too: they travel in `logsFile`, and [recordLog] is what fills
  /// it. Until 2026-08-27 this was `false` and the log was dropped, the format
  /// being unknown; it was then read out of the SDK's own bundle. See
  /// `docs/web-protocol.md`.
  @override
  bool get mirrorsBreadcrumbsToLog => true;

  @override
  Future<void> initialize(TracerOptions options) async {
    _debug = options.debug;
    if (!options.isCollectionEnabled) {
      _enabled = false;
      return;
    }

    final String? token = options.appToken;
    if (token == null || token.isEmpty) {
      _log('TracerOptions.appToken is required on web; collection is off.');
      _enabled = false;
      return;
    }

    _appToken = token;
    _host = hostFrom(options.apiUrl) ?? defaultHost;
    _environment = options.environment ?? 'prod';
    _versionName = options.release ?? _versionName;
    _versionCode = _versionCodeFrom(_versionName);
    _enabled = true;
  }

  @override
  Future<void> stopCollection() async {
    _enabled = false;
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<void> recordError(TracerEvent event) async {
    if (!_enabled) {
      return;
    }

    final Map<String, Object?> item = buildBatchItem(
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

    // compressType=NONE is the vendor's own path when gzip is unavailable, and
    // it is the only one open to us: dart:io, and with it GZipCodec, does not
    // exist on the web.
    final Uri uri = Uri.https(_host, '/api/crash/uploadBatch', <String, String>{
      'crashToken': _appToken!,
      'compressType': 'NONE',
      'sdkVersion': sdkVersion,
    });

    final String payload = jsonEncode(<Map<String, Object?>>[item]);

    try {
      final http.Response response = await _client.post(
        uri,
        headers: const <String, String>{
          'Content-Type': 'application/octet-stream',
        },
        body: utf8.encode(payload),
      );
      if (response.statusCode >= 400) {
        _log('upload rejected: ${response.statusCode} ${response.body}');
      } else {
        _log('uploaded ${event.exceptionType}: ${response.statusCode}');
      }
    } catch (error) {
      // A crash reporter that throws is worse than one that misses an event.
      _log('upload failed: $error');
    }
  }

  @override
  Future<void> recordLog(String message) async {
    if (!_enabled) {
      return;
    }
    _logs.add(message);
  }

  @override
  Future<void> setCustomKey({
    required String key,
    required String value,
  }) async {
    _customKeys[key] = value;
  }

  @override
  Future<void> removeCustomKey(String key) async {
    _customKeys.remove(key);
  }

  @override
  Future<void> setUserId(String? userId) async {
    _userId = userId;
  }

  /// Accepts either a bare host or a full URL, because both look reasonable to
  /// someone filling in `TracerOptions.apiUrl`.
  @visibleForTesting
  static String? hostFrom(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final Uri? parsed = Uri.tryParse(value);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
    }
    return value;
  }

  /// Mirrors the vendor's rule: `versionCode` is derived from a
  /// `major.minor.patch` version name when it is not given.
  static int _versionCodeFrom(String versionName) {
    final Match? match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(versionName);
    if (match == null) {
      return 1;
    }
    final int major = int.parse(match.group(1)!);
    final int minor = int.parse(match.group(2)!);
    final int patch = int.parse(match.group(3)!);
    return major * 10000 + minor * 100 + patch;
  }

  void _log(String message) {
    if (_debug) {
      // ignore: avoid_print
      print('apptracer_flutter: $message');
    }
  }
}
