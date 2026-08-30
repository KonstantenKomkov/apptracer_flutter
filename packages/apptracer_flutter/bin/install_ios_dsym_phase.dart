// Adds the dSYM-upload build phase to an iOS application's Xcode project.
//
// On CocoaPods the podspec of apptracer_flutter_ios does this at `pod install`.
// Swift Package Manager evaluates no podspec, so the step has to be run once by
// hand:
//
//   dart run apptracer_flutter:install_ios_dsym_phase
//
// The work itself is in `tracer_add_upload_phase.rb`, shipped inside
// apptracer_flutter_ios; this command only finds that package and runs it, so
// nobody has to dig a path out of the pub cache. It needs Ruby with the
// `xcodeproj` gem — the same pair CocoaPods itself runs on. Without it, add the
// phase in Xcode by hand: the script it would install is
// `ios/tracer_dsym_upload_phase.sh` in that package.
import 'dart:io';
import 'dart:isolate';

const String _usage = '''
Usage:
  dart run apptracer_flutter:install_ios_dsym_phase [options]

Options:
  --project-dir=…   Directory holding the Xcode project. Defaults to ios.
  --project=…       Xcode project name. Defaults to Runner.xcodeproj.
  --target=…        Target to add the phase to. Defaults to Runner.

Adding the phase twice is not possible: an existing one is refreshed in place.
Delete it in Xcode if you upload symbols another way.''';

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--')) {
      stderr.writeln('unexpected argument "$argument".');
      stdout.writeln(_usage);
      exit(64);
    }
    final int eq = argument.indexOf('=');
    if (eq == -1) {
      options[argument.substring(2)] = '';
    } else {
      options[argument.substring(2, eq)] = argument.substring(eq + 1);
    }
  }

  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    exit(0);
  }

  final String? script = await _locateScript();
  if (script == null) {
    stderr.writeln(
      'could not find apptracer_flutter_ios. Run this from the application '
      'whose pubspec.yaml depends on apptracer_flutter, after flutter pub get.',
    );
    exit(66);
  }

  final ProcessResult result = Process.runSync('ruby', <String>[
    script,
    '--projectDirectory=${options['project-dir'] ?? 'ios'}',
    '--projectName=${options['project'] ?? 'Runner.xcodeproj'}',
    '--targetName=${options['target'] ?? 'Runner'}',
  ]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exit(result.exitCode);
}

/// Path to `tracer_add_upload_phase.rb` inside the resolved
/// apptracer_flutter_ios package, or null when that package is not resolvable.
Future<String?> _locateScript() async {
  final Uri? packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:apptracer_flutter_ios/apptracer_flutter_ios.dart'),
  );
  if (packageUri == null) {
    return null;
  }
  // .../apptracer_flutter_ios/lib/apptracer_flutter_ios.dart → .../ios/…
  final Uri script = packageUri.resolve('../ios/tracer_add_upload_phase.rb');
  final String path = script.toFilePath();
  return File(path).existsSync() ? path : null;
}
