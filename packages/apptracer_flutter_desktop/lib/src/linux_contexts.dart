import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Non-identifying Linux metadata, read only after collection is authorized.
/// The pinned C bridge cannot load native contexts into Dart events.
class LinuxContexts {
  LinuxContexts._(this.values);

  /// Allowlisted OS and hardware fields shared with the official native SDK.
  final Map<String, Map<String, dynamic>> values;

  /// Reads system metadata. [root] allows isolated filesystem fixtures in tests.
  static Future<LinuxContexts> collect({String root = ''}) async {
    Future<String?> read(String path) async {
      RandomAccessFile? file;
      try {
        file = await File('$root$path').open();
        final bytes = await file.read(65537);
        if (bytes.length > 65536) return null;
        final value = utf8.decode(bytes).trim();
        return value.isEmpty ? null : value;
      } on FileSystemException {
        return null;
      } on FormatException {
        return null;
      } finally {
        await file?.close();
      }
    }

    final release = await read('/etc/os-release') ??
        await read('/usr/lib/os-release') ??
        '';
    final fields = <String, String>{};
    for (final line in const LineSplitter().convert(release)) {
      final separator = line.indexOf('=');
      if (separator < 1) continue;
      final key = line.substring(0, separator);
      if (!const {'NAME', 'VERSION_ID', 'PRETTY_NAME', 'ID'}.contains(key)) {
        continue;
      }
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) fields[key] = value;
    }
    final kernel = await read('/proc/sys/kernel/osrelease');
    final model = await read('/sys/class/dmi/id/product_name');
    final manufacturer = await read('/sys/class/dmi/id/sys_vendor');
    final arch = switch (Abi.current()) {
      Abi.linuxX64 => 'x86_64',
      Abi.linuxArm64 => 'aarch64',
      Abi.linuxIA32 => 'x86',
      Abi.linuxArm => 'arm',
      _ => null,
    };
    return LinuxContexts._({
      'os': {
        'name': fields['NAME'] ?? 'Linux',
        if (fields['VERSION_ID'] != null) 'version': fields['VERSION_ID'],
        if (kernel != null) 'kernel_version': kernel,
        if (fields['PRETTY_NAME'] != null)
          'raw_description': fields['PRETTY_NAME'],
        if (fields['ID'] != null) 'distribution_name': fields['ID'],
      },
      'device': {
        if (arch != null) 'arch': arch,
        if (model != null) 'model': model,
        if (manufacturer != null) 'manufacturer': manufacturer,
      },
    });
  }

  /// Adds the same metadata to a Dart event, preserving unrelated contexts.
  void apply(SentryEvent event) {
    final current = event.contexts;
    current.operatingSystem = SentryOperatingSystem.fromJson({
      ...?current.operatingSystem?.toJson(),
      ...values['os']!,
    });
    current.device = SentryDevice.fromJson({
      ...?current.device?.toJson(),
      ...values['device']!,
    });
  }
}
