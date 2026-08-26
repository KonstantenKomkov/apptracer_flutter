import 'dart:convert';
import 'dart:math';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;

import 'sentry_dsn.dart';
import 'sentry_event_builder.dart';

/// Delivers Dart errors to Tracer over the Sentry protocol.
///
/// Tracer documents this route for platforms where it has no SDK of its own —
/// Java, Go, Python, PHP, C/C++ on Windows, Linux and macOS — and issues a
/// Sentry DSN for a project created through VK Cloud. For a Flutter
/// application that means desktop, and Aurora OS when the vendor's C/C++ SDK
/// is out of reach.
///
/// Web does **not** use this: Tracer has its own JavaScript SDK there, an
/// ordinary JS project is issued no DSN, and `apptracer_flutter_web` speaks the
/// same HTTP ingest that SDK speaks. See `docs/web-protocol.md`.
class SentryProtocolTracer extends TracerPlatform {
  /// Creates a transport.
  ///
  /// [httpClient] is injectable so tests can assert on the exact bytes sent.
  SentryProtocolTracer({
    http.Client? httpClient,
    String backendName = 'sentry-http',
    Random? random,
  })  : _ownsClient = httpClient == null,
        _client = httpClient ?? http.Client(),
        _backendName = backendName,
        _random = random ?? Random.secure();

  /// Identifies this client to the ingest, as Sentry's protocol requires.
  static const String clientName = 'apptracer_flutter';

  /// Version reported in `X-Sentry-Auth`.
  static const String clientVersion = '0.1.0';

  http.Client _client;
  final bool _ownsClient;
  final String _backendName;
  final Random _random;

  SentryDsn? _dsn;
  String? _release;
  String? _environment;
  bool _enabled = false;
  bool _debug = false;
  DateTime? _mutedUntil;

  @override
  String get backendName => _backendName;

  @override
  bool get isEnabled => _enabled;

  /// Breadcrumbs travel inside the event, so mirroring them into a platform
  /// log would send every one of them twice.
  @override
  bool get mirrorsBreadcrumbsToLog => false;

  @override
  Future<void> initialize(TracerOptions options) async {
    _debug = options.debug;
    if (!options.isCollectionEnabled) {
      _enabled = false;
      return;
    }

    final String? dsn = options.dsn;
    if (dsn == null || dsn.isEmpty) {
      _log('TracerOptions.dsn is required for the Sentry transport; '
          'collection is off.');
      _enabled = false;
      return;
    }

    try {
      _dsn = SentryDsn.parse(dsn);
    } on FormatException catch (error) {
      // Loudly, and only here: a DSN is typed once, and a typo that silently
      // swallowed every event afterwards would be far worse than this line.
      _log('$error');
      _enabled = false;
      return;
    }

    _release = options.release;
    _environment = options.environment;
    _enabled = true;
  }

  @override
  Future<void> stopCollection() async {
    _enabled = false;
    if (_ownsClient) {
      _client.close();
      _client = http.Client();
    }
  }

  @override
  Future<void> recordError(TracerEvent event) async {
    final SentryDsn? dsn = _dsn;
    if (!_enabled || dsn == null) {
      return;
    }
    if (_mutedUntil != null && DateTime.now().isBefore(_mutedUntil!)) {
      return;
    }

    final String eventId = _eventId();
    final String body = _envelope(
      eventId: eventId,
      event: buildSentryEvent(
        event: event,
        eventId: eventId,
        release: _release,
        environment: _environment,
      ),
    );

    try {
      final http.Response response = await _client.post(
        dsn.envelopeUri,
        headers: <String, String>{
          'Content-Type': 'application/x-sentry-envelope',
          'X-Sentry-Auth': 'Sentry sentry_version=7, '
              'sentry_client=$clientName/$clientVersion, '
              'sentry_key=${dsn.publicKey}',
        },
        body: body,
      );

      if (response.statusCode == 429) {
        _mute(response.headers['retry-after']);
        _log('rate limited until $_mutedUntil');
      } else if (response.statusCode >= 400) {
        _log('rejected: ${response.statusCode} ${response.body}');
      } else {
        _log('sent ${event.exceptionType} as $eventId');
      }
    } catch (error) {
      // A crash reporter that throws is worse than one that misses an event.
      _log('send failed: $error');
    }
  }

  @override
  Future<void> recordLog(String message) async {}

  @override
  Future<void> setCustomKey({
    required String key,
    required String value,
  }) async {}

  @override
  Future<void> removeCustomKey(String key) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  /// Frames one event as a Sentry envelope.
  ///
  /// The item header carries the body length in **bytes**, not characters. A
  /// message with anything outside ASCII makes those differ, and an ingest
  /// reading the wrong number of bytes rejects the whole envelope.
  String _envelope({
    required String eventId,
    required Map<String, Object?> event,
  }) {
    final String payload = jsonEncode(event);
    final int length = utf8.encode(payload).length;
    final String header = jsonEncode(<String, Object?>{
      'event_id': eventId,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    });
    final String itemHeader = jsonEncode(<String, Object?>{
      'type': 'event',
      'length': length,
    });
    return '$header\n$itemHeader\n$payload\n';
  }

  /// Sentry event ids are 32 hex characters with no dashes.
  String _eventId() {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  void _mute(String? retryAfter) {
    final int seconds = int.tryParse(retryAfter ?? '') ?? 60;
    _mutedUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  void _log(String message) {
    if (_debug) {
      // ignore: avoid_print
      print('apptracer_flutter: $message');
    }
  }
}
