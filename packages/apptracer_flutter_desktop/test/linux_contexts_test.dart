import 'dart:io';

import 'package:apptracer_flutter_desktop/src/linux_contexts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('collects distro and hardware model without identifiers', () async {
    final root = await Directory.systemTemp.createTemp('linux-contexts-');
    addTearDown(() => root.delete(recursive: true));
    Future<void> write(String path, String value) async {
      final file = File('${root.path}$path');
      await file.parent.create(recursive: true);
      await file.writeAsString(value);
    }

    await write('/etc/os-release',
        'NAME="Ubuntu"\nVERSION_ID="22.04"\nPRETTY_NAME="Ubuntu 22.04.5 LTS"\nID=ubuntu\nSECRET=must-not-collect');
    await write('/proc/sys/kernel/osrelease', '5.15.0-198-generic\n');
    await write('/sys/class/dmi/id/product_name', 'Standard PC\n');
    await write('/sys/class/dmi/id/sys_vendor', 'QEMU\n');
    await write('/sys/class/dmi/id/product_serial', 'must-not-collect');
    final contexts = await LinuxContexts.collect(root: root.path);
    final event = SentryEvent(
        contexts: Contexts.fromJson({
      'os': {'theme': 'dark'},
      'apptracer': {'fatal': false},
    }));
    contexts.apply(event);
    expect(event.contexts.operatingSystem?.name, 'Ubuntu');
    expect(event.contexts.operatingSystem?.version, '22.04');
    expect(event.contexts.operatingSystem?.kernelVersion, '5.15.0-198-generic');
    expect(event.contexts.operatingSystem?.theme, 'dark');
    expect(event.contexts.device?.model, 'Standard PC');
    expect(event.contexts.device?.manufacturer, 'QEMU');
    expect(event.contexts.toJson().toString(),
        isNot(contains('must-not-collect')));
    expect(event.contexts['apptracer'], {'fatal': false});
  });

  test('missing metadata files do not prevent reporting', () async {
    final root = await Directory.systemTemp.createTemp('linux-contexts-');
    addTearDown(() => root.delete(recursive: true));
    final contexts = await LinuxContexts.collect(root: root.path);
    expect(contexts.values['os'], {'name': 'Linux'});
    expect(contexts.values['device'], isNot(contains('model')));
  });
}
