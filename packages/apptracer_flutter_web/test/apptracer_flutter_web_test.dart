@TestOn('browser')
library;

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_web/apptracer_flutter_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void main() {
  test('registers itself as the web implementation', () {
    AppTracerWeb.registerWith(Registrar());

    expect(TracerPlatform.instance, isA<AppTracerWeb>());
    expect(TracerPlatform.instance.backendName, 'web-tracer-http');
  });

  test('stays disabled without an appToken', () async {
    final AppTracerWeb tracer = AppTracerWeb();

    await tracer.initialize(const TracerOptions());

    expect(tracer.isEnabled, isFalse);
  });

  test('starts with an appToken', () async {
    final AppTracerWeb tracer = AppTracerWeb();

    await tracer.initialize(const TracerOptions(appToken: 'token'));

    expect(tracer.isEnabled, isTrue);
  });

  test('reads the browser for the facts Tracer expects', () {
    final AppTracerWeb tracer = AppTracerWeb();

    // The values differ per browser; what matters is that reading them does not
    // throw and that the identifiers are shaped like UUIDs.
    expect(tracer.facts.deviceId, hasLength(36));
    expect(tracer.facts.sessionUuid, hasLength(36));
    expect(tracer.facts.host, isNotEmpty);
    expect(tracer.facts.documentVisibilityState, isNotEmpty);
  });

  test('keeps the device identifier across instances', () {
    final AppTracerWeb first = AppTracerWeb();
    final AppTracerWeb second = AppTracerWeb();

    expect(second.facts.deviceId, first.facts.deviceId);
    expect(second.facts.sessionUuid, isNot(first.facts.sessionUuid));
  });
}
