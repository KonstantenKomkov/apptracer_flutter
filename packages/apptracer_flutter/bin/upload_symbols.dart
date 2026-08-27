// Uploads iOS dSYMs and web source maps to Tracer.
//
// Android needs none of this: the `ru.ok.tracer` Gradle plugin uploads
// mappings and native symbols during the build. On iOS the vendor's Fastlane
// plugin and Xcode Run Script phase do the same on archive, and this command is
// for builds that have neither. On web nothing else exists.
//
//   dart run apptracer_flutter:upload_symbols ios --token=…
//   dart run apptracer_flutter:upload_symbols web --token=…
//
// Exits non-zero unless the server confirmed the upload, so a release pipeline
// stops instead of shipping a build whose crashes cannot be read.
import 'dart:io';

import 'package:apptracer_flutter/src/tools/symbol_uploader.dart';

const String _usage = '''
Usage:
  dart run apptracer_flutter:upload_symbols ios [options]
  dart run apptracer_flutter:upload_symbols web [options]

Options:
  --token=…      Project's pluginToken. Defaults to TRACER_PLUGIN_TOKEN.
  --version=…    Version name. Defaults to the version in pubspec.yaml.
  --build=…      Build number, iOS only. Defaults to the one in pubspec.yaml.
  --dir=…        Directory to upload. Defaults to
                 build/ios/archive/Runner.xcarchive/dSYMs for ios,
                 build/web for web.
  --endpoint=…   Overrides the ingest URL, for proxying setups.

The version has to match what the application reports, or the symbols attach to
a version nothing looks up. Upload before the release reaches users: Tracer
applies symbols only to events received afterwards and has no
re-symbolication.''';

Future<void> main(List<String> arguments) async {
  final List<String> positional =
      arguments.where((String a) => !a.startsWith('--')).toList();
  final Map<String, String> options = <String, String>{};
  for (final String argument
      in arguments.where((String a) => a.startsWith('--'))) {
    final int eq = argument.indexOf('=');
    if (eq == -1) {
      options[argument.substring(2)] = '';
    } else {
      options[argument.substring(2, eq)] = argument.substring(eq + 1);
    }
  }

  if (positional.length != 1 || options.containsKey('help')) {
    stdout.writeln(_usage);
    exit(positional.isEmpty ? 64 : 0);
  }

  final String platform = positional.single;
  if (platform != 'ios' && platform != 'web') {
    stderr.writeln('unknown platform "$platform"; expected ios or web.');
    exit(64);
  }

  final String token =
      options['token'] ?? Platform.environment['TRACER_PLUGIN_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln(
      'No token. Pass --token=… or set TRACER_PLUGIN_TOKEN. This is the '
      'pluginToken of the ${platform.toUpperCase()} project, not the appToken.',
    );
    exit(64);
  }

  final _PubspecVersion? fromPubspec = _readPubspecVersion();
  final String? versionName = options['version'] ?? fromPubspec?.name;
  if (versionName == null || versionName.isEmpty) {
    stderr.writeln(
      'No version. Pass --version=…, or run this where pubspec.yaml is.',
    );
    exit(64);
  }

  final UploadResult result;
  if (platform == 'ios') {
    result = await uploadDsym(
      token: token,
      dsymDir: Directory(
        options['dir'] ?? 'build/ios/archive/Runner.xcarchive/dSYMs',
      ),
      versionName: versionName,
      versionCode: options['build'] ?? fromPubspec?.code ?? '1',
      endpoint: options['endpoint'] ?? kSymbolEndpoint,
    );
  } else {
    result = await uploadSourceMaps(
      token: token,
      buildDir: Directory(options['dir'] ?? 'build/web'),
      versionName: versionName,
      endpoint: options['endpoint'] ?? kSourceMapEndpoint,
    );
  }

  final String size =
      '${(result.byteCount / 1024 / 1024).toStringAsFixed(1)} MB';
  if (result.ok) {
    stdout.writeln(
      '$platform: ${result.fileCount} file(s), $size, version $versionName — '
      '${result.message}',
    );
    return;
  }

  stderr.writeln('$platform: ${result.message}');
  exit(1);
}

class _PubspecVersion {
  const _PubspecVersion(this.name, this.code);

  final String name;
  final String? code;
}

/// Reads `version:` out of pubspec.yaml without a YAML dependency.
_PubspecVersion? _readPubspecVersion() {
  final File pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    return null;
  }
  for (final String line in pubspec.readAsLinesSync()) {
    final Match? match = RegExp(r'^version:\s*([^\s#]+)').firstMatch(line);
    if (match == null) {
      continue;
    }
    final String value = match.group(1)!;
    final int plus = value.indexOf('+');
    if (plus == -1) {
      return _PubspecVersion(value, null);
    }
    return _PubspecVersion(value.substring(0, plus), value.substring(plus + 1));
  }
  return null;
}
