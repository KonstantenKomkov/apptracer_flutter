import 'dart:io';

import 'package:apptracer_flutter_desktop/src/linux_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserved native cache retries with unchanged payload and age',
      () async {
    final temp = await Directory.systemTemp.createTemp('tracer-native-retry');
    final storage = LinuxStorage('${temp.path}/owned');
    try {
      await storage.prepare(false);
      final cache = await Directory('${storage.queue}/cache').create();
      const id = '01234567-0123-0123-0123-0123456789ab';
      final envelope =
          await File('${cache.path}/$id.envelope').writeAsBytes([0, 10, 255]);
      await envelope
          .setLastModified(DateTime.fromMillisecondsSinceEpoch(1700000000000));
      final dump = await File('${cache.path}/$id.dmp').writeAsString('MDMP');
      final unrelated = await File(
              '${cache.path}/aaaaaaaa-0123-0123-0123-0123456789ab.envelope')
          .writeAsString('other');
      await storage.prepare(true);
      final retry = File('${cache.path}/1700000000000-00-$id.envelope');
      final bytes = await retry.readAsBytes();
      expect(
          (await retry.stat()).modified.millisecondsSinceEpoch, 1700000000000);
      expect(bytes.take(3), [0, 10, 255]);
      expect(bytes.skip(bytes.length - 4), [77, 68, 77, 80]);
      expect(await envelope.exists(), false);
      expect(await dump.readAsString(), 'MDMP');
      expect(await unrelated.exists(), true);
      // Recover a crash between publishing the retry and deleting its source.
      await envelope.writeAsBytes([0, 10, 255]);
      await envelope
          .setLastModified(DateTime.fromMillisecondsSinceEpoch(1700000000000));
      await storage.prepare(true);
      expect(await retry.readAsBytes(), bytes);
      expect(await envelope.exists(), false);
      await storage.revoke();
      await storage.prepare(true);
      expect(await retry.exists(), false);
    } finally {
      await storage.release();
      await temp.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
  test('revocation overrides preserve, clear blocks late queue writers',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('tracer storage Кириллица');
    final storage = LinuxStorage('${temp.path}/owned');
    try {
      await storage.prepare(false);
      final pending = File('${storage.queue}/pending');
      await pending.writeAsString('previous account');
      await storage.prepare(true);
      expect(await pending.exists(), true);
      await storage.revoke();
      await storage.prepare(true);
      expect(await pending.exists(), false);
      await pending.writeAsString('new account');
      await storage.clear();
      expect(await File(storage.queue).exists(), true);
      await expectLater(Directory(storage.queue).create(),
          throwsA(isA<FileSystemException>()));
      await storage.prepare(true);
      expect(await Directory(storage.queue).exists(), true);
      expect(await pending.exists(), false);
    } finally {
      await storage.release();
      await temp.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);

  test('rejects symlinked queue without deleting its target', () async {
    final temp = await Directory.systemTemp.createTemp('tracer-link');
    final storage = LinuxStorage('${temp.path}/owned');
    try {
      await storage.acquire();
      final outside = await Directory('${temp.path}/outside').create();
      final evidence = await File('${outside.path}/keep').writeAsString('keep');
      await Link(storage.queue).create(outside.path);
      await expectLater(storage.prepare(false), throwsStateError);
      await expectLater(storage.clear(), throwsStateError);
      expect(await evidence.readAsString(), 'keep');
    } finally {
      await storage.release();
      await temp.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
}
