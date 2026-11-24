import 'dart:io';

import 'package:apptracer_flutter_aurora/apptracer_flutter_aurora.dart';
import 'package:flutter/widgets.dart';

// Build only in the dedicated acceptance RPM. The normal example is inert.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final probe = await AuroraTracer.probe();
  stdout.writeln('Tracer Native ${probe['sdkVersion']}');

  final dir =
      '${Platform.environment['HOME']}/.local/share/'
      'ru.apptracer/apptracer_flutter_aurora_example';
  final input = File('$dir/explicit-test-input');
  if (!await input.exists()) return;
  final lines = await input.readAsLines();
  await input.delete();
  if (lines.length != 2 ||
      !const {'arm', 'upload'}.contains(lines.first) ||
      lines.last.isEmpty) {
    throw const FormatException('Invalid acceptance input');
  }

  final worker = await Process.start('/proc/self/exe', [
    '--apptracer-test-worker',
  ]);
  final output = Future.wait([
    worker.stdout.drain<void>(),
    worker.stderr.drain<void>(),
  ]);
  worker.stdin.writeln(lines.first);
  worker.stdin.writeln(lines.last);
  await worker.stdin.close();
  final status = await worker.exitCode;
  await output;
  stdout.writeln('Acceptance ${lines.first}, worker exit $status');
  await stdout.flush();
  if (status == 0 && lines.first == 'arm') {
    Process.killPid(pid, ProcessSignal.sigabrt);
  } else {
    exit(status);
  }
}
