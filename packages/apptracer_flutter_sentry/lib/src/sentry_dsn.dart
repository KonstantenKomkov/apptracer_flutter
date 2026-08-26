import 'package:meta/meta.dart';

/// A parsed Sentry DSN as issued by Tracer.
///
/// Tracer accepts events over the Sentry protocol on platforms where it has no
/// SDK of its own, and hands out a DSN in the project settings — but only for a
/// project created through VK Cloud. The grammar is Sentry's:
///
/// ```
/// <scheme>://<publicKey>@<host>[:<port>][/<path>]/<projectId>
/// ```
@immutable
class SentryDsn {
  /// Creates a DSN from its parts.
  const SentryDsn({
    required this.publicKey,
    required this.uri,
    required this.projectId,
  });

  /// The public key, sent in the `X-Sentry-Auth` header.
  final String publicKey;

  /// Origin and path prefix, without the project id.
  final Uri uri;

  /// The numeric project id, the last path segment of the DSN.
  final String projectId;

  /// Where envelopes are posted.
  Uri get envelopeUri {
    final List<String> segments = <String>[
      ...uri.pathSegments.where((String s) => s.isNotEmpty),
      'api',
      projectId,
      'envelope',
      '',
    ];
    return uri.replace(path: '/${segments.join('/')}');
  }

  /// Parses [dsn].
  ///
  /// Throws [FormatException] when [dsn] is not a valid DSN, because a
  /// mistyped DSN silently swallowing every event is far worse than a loud
  /// failure at startup.
  static SentryDsn parse(String dsn) {
    final Uri? uri = Uri.tryParse(dsn.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw FormatException('not a Sentry DSN: "$dsn"');
    }

    final String publicKey = uri.userInfo.split(':').first;
    if (publicKey.isEmpty) {
      throw FormatException('a Sentry DSN needs a public key: "$dsn"');
    }

    final List<String> segments =
        uri.pathSegments.where((String s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw FormatException('a Sentry DSN needs a project id: "$dsn"');
    }

    final String projectId = segments.removeLast();
    return SentryDsn(
      publicKey: publicKey,
      uri: Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: segments.isEmpty ? '' : segments.join('/'),
      ),
      projectId: projectId,
    );
  }

  @override
  String toString() => 'SentryDsn($projectId at ${uri.host})';
}
