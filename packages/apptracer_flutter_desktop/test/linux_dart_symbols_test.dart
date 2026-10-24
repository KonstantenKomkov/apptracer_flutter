import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_desktop/src/event_mapping.dart';
import 'package:apptracer_flutter_desktop/src/linux_dart_symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  const id = 'fed6889c5704bdde60d6ce8804d49225';
  const raw = "os: linux arch: x64 comp: no sim: no\nbuild_id: '$id'\n"
      'isolate_dso_base: 1000\n'
      '#00 abs 00001234 virt 00000234 _kDartSnapshotText+0x34\n';
  late Directory directory;
  setUp(() async =>
      directory = await Directory.systemTemp.createTemp('dart-map-'));
  tearDown(() async => directory.delete(recursive: true));
  TracerEvent source([String stack = raw]) => TracerEvent(
      exceptionType: 'StateError',
      message: 'filtered',
      stackTrace: DartStackTrace.parse(StackTrace.fromString(stack)),
      customKeys: const {'kept': 'yes'});
  SentryEvent event(TracerEvent source, {String codeId = id}) =>
      toSentryEvent(source)
        ..debugMeta = DebugMeta(images: [
          DebugImage(
              type: 'elf',
              codeId: codeId,
              codeFile: '/bundle/lib/libapp.so',
              imageAddr: '0x1000',
              imageSize: 4096)
        ]);
  Future<void> writeMap({String identity = id, bool corrupt = false}) async {
    await File('${directory.path}/$id.json.gz').writeAsBytes(corrupt
        ? [1, 2, 3]
        : gzip.encode(utf8.encode(jsonEncode({
            'schema': 1,
            'build_id': identity,
            'arch': 'x64',
            'files': ['package:app/main.dart'],
            'functions': [
              [0x234, 4, 'performAction']
            ],
            'lines': [
              [0x234, 4, 0, 73]
            ]
          }))));
  }

  test(
      'matches loaded ELF and resolves exact range start without PC subtraction',
      () async {
    await writeMap();
    final input = source();
    final output = event(input);
    await LinuxDartSymbols(directory: directory.path).resolve(output, input);
    final frame = output.exceptions!.single.stackTrace!.frames.single;
    expect(frame.function, 'performAction');
    expect(frame.fileName, 'package:app/main.dart');
    expect(frame.lineNo, 73);
    expect(frame.instructionAddr, '0x00001234');
    expect(output.contexts['apptracer']['dart_stack_trace'], raw);
    expect(output.tags, {'kept': 'yes'});
  });

  test('missing, corrupt and mismatched maps preserve the entire event',
      () async {
    for (final mode in ['missing', 'corrupt', 'mismatched']) {
      if (mode != 'missing') {
        await writeMap(corrupt: mode == 'corrupt', identity: 'bad');
      }
      final input = source();
      final output = event(input);
      final before = jsonEncode(output.toJson());
      await LinuxDartSymbols(directory: directory.path).resolve(output, input);
      expect(jsonEncode(output.toJson()), before, reason: mode);
    }
  });

  test(
      'rejects foreign loaded ELF, inconsistent PCs and addresses outside ranges',
      () async {
    await writeMap();
    for (final variant in ['elf', 'pc', 'outside']) {
      final input = source(variant == 'pc'
          ? raw.replaceAll('00000234', '00000235')
          : variant == 'outside'
              ? raw
                  .replaceAll('00001234', '00001238')
                  .replaceAll('00000234', '00000238')
              : raw);
      final output = event(input, codeId: variant == 'elf' ? 'bad' : id);
      final before = jsonEncode(output.toJson());
      await LinuxDartSymbols(directory: directory.path).resolve(output, input);
      expect(jsonEncode(output.toJson()), before, reason: variant);
    }
  });

  test(
      'does not restore frames removed by filtering or replace existing source fields',
      () async {
    await writeMap();
    final filtered = source('');
    final output = event(source());
    final before = jsonEncode(output.toJson());
    await LinuxDartSymbols(directory: directory.path).resolve(output, filtered);
    expect(jsonEncode(output.toJson()), before);
    final frame = output.exceptions!.single.stackTrace!.frames.single;
    frame.fileName = 'filtered.dart';
    frame.lineNo = 9;
    await LinuxDartSymbols(directory: directory.path).resolve(output, source());
    expect(frame.fileName, 'filtered.dart');
    expect(frame.lineNo, 9);
  });
}
