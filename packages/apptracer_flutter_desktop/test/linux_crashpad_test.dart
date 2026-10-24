import 'dart:io';

import 'package:apptracer_flutter_desktop/src/linux_uploaders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('procfs inspection leaves unrelated running processes alone', () async {
    final temporary = await Directory.systemTemp.createTemp('tracer-proc-test');
    try {
      await LinuxUploaders.stop('${temporary.path}/never-used-queue');
    } finally {
      await temporary.delete();
    }
  }, skip: !Platform.isLinux);
  test('only the exact private queue and user authorize a Crashpad stop', () {
    const executable = '/opt/example/lib/crashpad_handler';
    const queue = '/home/user/.local/share/apptracer_desktop/example/v1/queue';
    expect(
        ownsLinuxCrashpad(executable, ['--database=$queue'], queue, 1000, 1000),
        true);
    expect(
        ownsLinuxCrashpad(
            executable, ['--database=$queue-other'], queue, 1000, 1000),
        false);
    expect(
        ownsLinuxCrashpad(executable, ['--database=$queue'], queue, 1001, 1000),
        false);
    expect(
        ownsLinuxCrashpad(
            '/usr/bin/unrelated', ['--database=$queue'], queue, 1000, 1000),
        false);
    expect(
        ownsLinuxCrashpad(
            executable, ['--annotation=$queue'], queue, 1000, 1000),
        false);
  });
  test('native daemon requires an open lock in the exact owned queue', () {
    const db = '/tmp/apptracer/queue';
    const lock = '$db/01234567-0123-0123-0123-0123456789ab.run.daemon.lock';
    expect(
        ownsLinuxNative('/opt/app/sentry-crash', lock, db, 1000, 1000), true);
    expect(
        ownsLinuxNative('/opt/app/sentry-crash', lock, '$db-other', 1000, 1000),
        false);
    expect(
        ownsLinuxNative('/opt/app/sentry-crash', lock, db, 1001, 1000), false);
    expect(ownsLinuxNative('/opt/app/unrelated', lock, db, 1000, 1000), false);
    expect(ownsLinuxNative('/opt/app/sentry-crash', '$db/file', db, 1000, 1000),
        false);
  });
}
