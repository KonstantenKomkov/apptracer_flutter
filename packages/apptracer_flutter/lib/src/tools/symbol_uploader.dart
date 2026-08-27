import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'zip_writer.dart';

/// Where Tracer accepts symbols and source maps.
const String kSymbolEndpoint =
    'https://plugin-api.apptracer.ru/api/symbol/upload';

/// Where Tracer accepts web source maps.
const String kSourceMapEndpoint =
    'https://plugin-api.apptracer.ru/api/sourcemap/upload';

/// What an upload did, in a form a command can print and exit on.
class UploadResult {
  /// Creates a result.
  const UploadResult({
    required this.ok,
    required this.message,
    this.fileCount = 0,
    this.byteCount = 0,
  });

  /// Whether the server confirmed the upload.
  final bool ok;

  /// A line for the operator. Never contains the token.
  final String message;

  /// How many files went into the archive.
  final int fileCount;

  /// How large the archive was.
  final int byteCount;
}

/// Uploads the `.dSYM` bundles in [dsymDir].
///
/// [versionName] and [versionCode] must match what the application reports, or
/// the symbols attach to a version nothing looks up.
Future<UploadResult> uploadDsym({
  required String token,
  required Directory dsymDir,
  required String versionName,
  required String versionCode,
  String endpoint = kSymbolEndpoint,
  HttpClient? httpClient,
}) async {
  if (!dsymDir.existsSync()) {
    return UploadResult(
        ok: false, message: 'no such directory: ${dsymDir.path}');
  }

  final ZipWriter zip = ZipWriter()..addDirectory(dsymDir);
  if (zip.isEmpty) {
    return UploadResult(
      ok: false,
      message: 'no files under ${dsymDir.path}; nothing to upload',
    );
  }

  final Uint8List archive = zip.build();
  return _post(
    uri: Uri.parse('$endpoint?symbolToken=$token'),
    fields: <String, String>{
      'versionName': versionName,
      'versionCode': versionCode,
    },
    archive: archive,
    filename: 'dsym.zip',
    fileCount: zip.length,
    httpClient: httpClient,
  );
}

/// Uploads the JavaScript and source maps in [buildDir].
///
/// The archive is built from paths relative to [buildDir], because Tracer
/// matches source maps by file path rather than by debug id: a path that does
/// not match the frames matches nothing at all.
Future<UploadResult> uploadSourceMaps({
  required String token,
  required Directory buildDir,
  required String versionName,
  String endpoint = kSourceMapEndpoint,
  HttpClient? httpClient,
}) async {
  if (!buildDir.existsSync()) {
    return UploadResult(
      ok: false,
      message: 'no such directory: ${buildDir.path}',
    );
  }

  final ZipWriter zip = ZipWriter()
    ..addDirectory(
      buildDir,
      keep: (String path) => path.endsWith('.js') || path.endsWith('.map'),
    );
  final bool anyMaps = zip.length > 0;
  if (!anyMaps) {
    return UploadResult(
      ok: false,
      message: 'no .js or .map files under ${buildDir.path}; '
          'was the build made with --source-maps?',
    );
  }

  final Uint8List archive = zip.build();
  return _post(
    uri: Uri.parse(endpoint),
    fields: <String, String>{
      'sourcemapToken': token,
      'versionName': versionName,
    },
    archive: archive,
    filename: 'sourcemaps.zip',
    fileCount: zip.length,
    httpClient: httpClient,
  );
}

Future<UploadResult> _post({
  required Uri uri,
  required Map<String, String> fields,
  required Uint8List archive,
  required String filename,
  required int fileCount,
  HttpClient? httpClient,
}) async {
  const String boundary = 'apptracerflutterboundary8f2c1d';
  final BytesBuilder body = BytesBuilder();
  fields.forEach((String name, String value) {
    body.add(utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="$name"\r\n\r\n'
      '$value\r\n',
    ));
  });
  body
    ..add(utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
      'Content-Type: application/zip\r\n\r\n',
    ))
    ..add(archive)
    ..add(utf8.encode('\r\n--$boundary--\r\n'));
  final Uint8List payload = body.toBytes();

  final HttpClient client = httpClient ?? HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );
    request.headers.set(HttpHeaders.contentLengthHeader, payload.length);
    request.add(payload);

    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();

    // The ingest answers 200 with `{"success":true}` and nothing else; a body
    // that does not say so is a refusal however encouraging the status code.
    final bool ok = response.statusCode < 400 &&
        text.contains('"success"') &&
        text.replaceAll(' ', '').contains('"success":true');
    return UploadResult(
      ok: ok,
      message: ok
          ? 'accepted'
          : 'rejected: HTTP ${response.statusCode} ${text.trim()}',
      fileCount: fileCount,
      byteCount: payload.length,
    );
  } on Object catch (error) {
    // The error can quote the request line, and the request line can carry the
    // token; report the type and nothing more.
    return UploadResult(
      ok: false,
      message: 'the request failed: ${error.runtimeType}',
      fileCount: fileCount,
      byteCount: payload.length,
    );
  } finally {
    if (httpClient == null) {
      client.close(force: true);
    }
  }
}
