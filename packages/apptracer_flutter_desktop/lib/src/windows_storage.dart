import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'windows_uploaders.dart';

/// Private Windows queue, with a durable revocation marker and process lock.
/// Never follows symlinks while preparing or deleting SDK data.
class WindowsStorage {
  /// Creates storage in an explicitly owned namespace.
  WindowsStorage(this.root);

  /// Uses writable per-user storage, independently of the install directory.
  factory WindowsStorage.forApplication() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null ||
        !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(base) ||
        base.split(RegExp(r'[\\/]')).any((p) => p == '.' || p == '..')) {
      throw StateError('windows_local_app_data_invalid');
    }
    final app = Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last;
    return WindowsStorage('$base/apptracer_desktop/$app/v1');
  }

  /// Adapter-owned namespace; never a shared SDK cache.
  final String root;

  /// Native SDK database or a tombstone after clear.
  String get queue => '$root/queue';
  RandomAccessFile? _lock;

  Future<void> _validate(String path) async {
    WindowsUploaders.validate(path);
  }

  /// Excludes other processes until this process exits.
  Future<void> acquire() async {
    if (_lock != null) return;
    await _validate('$root/lock');
    await Directory(root).create(recursive: true);
    final file = await File('$root/lock').open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
      _lock = file;
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<void> _removeQueue() async {
    await _validate(queue);
    final type = await FileSystemEntity.type(queue, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      // Directory.delete does not follow links inside the tree.
      await Directory(queue).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(queue).delete();
    }
  }

  /// Revoked reports are always discarded, regardless of preservation policy.
  Future<void> prepare(bool preserve) async {
    await acquire();
    await _validate('$root/revoked');
    await _validate(queue);
    final revokedType = await FileSystemEntity.type('$root/revoked');
    if (revokedType != FileSystemEntityType.notFound &&
        revokedType != FileSystemEntityType.file) {
      throw StateError('windows_revocation_marker_invalid');
    }
    if (!preserve || await File('$root/revoked').exists()) {
      await _removeQueue();
    }
    await Directory(queue).create(recursive: true);
    await _prepareNativeRetry();
    // Probe actual write access before handing the directory to native code.
    final probe = File('$root/write-probe');
    await _validate(probe.path);
    await probe.writeAsString('', flush: true);
    await probe.delete();
    final revoked = File('$root/revoked');
    if (await revoked.exists()) await revoked.delete();
  }

  // sentry-native 0.16.6 disables retry polling in its crash daemon. Failed
  // native uploads have a bare UUID envelope plus a matching cached minidump.
  // Enroll these in the SDK's retry queue before init, while the namespace is
  // locked and its old daemon is stopped. The daemon splits the minidump out
  // of its cached envelope; reattach it with the official SDK item header.
  Future<void> _prepareNativeRetry() async {
    final cache = Directory('$queue/cache');
    await _validate(cache.path);
    if (!await cache.exists()) return;
    final pattern = RegExp(
        r'^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.envelope$');
    await for (final entry in cache.list(followLinks: false)) {
      final match = pattern.firstMatch(entry.path.split(RegExp(r'[\\/]')).last);
      if (match == null) continue;
      await _validate(entry.path);
      final dump = '${cache.path}/${match.group(1)}.dmp';
      await _validate(dump);
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await FileSystemEntity.type(dump, followLinks: false) !=
              FileSystemEntityType.file) {
        continue;
      }
      final age = (await entry.stat()).modified.millisecondsSinceEpoch;
      final target = '${cache.path}/$age-00-${match.group(1)}.envelope';
      await _validate(target);
      final bytes = await File(dump).readAsBytes();
      final item = SentryEnvelopeItem.fromAttachment(
        SentryAttachment.fromUint8List(bytes, '${match.group(1)}.dmp',
            attachmentType: SentryAttachment.typeMinidump,
            contentType: 'application/octet-stream'),
      );
      final combined = BytesBuilder(copy: false)
        ..add(await File(entry.path).readAsBytes())
        ..add([10])
        ..add(utf8.encode(jsonEncode(await item.header.toJson(bytes.length))))
        ..add([10])
        ..add(bytes);
      final payload = combined.takeBytes();
      final output = File(target);
      if (await output.exists()) {
        // A previous process may have exited after atomic publication but
        // before removal of the original. Never overwrite a different report.
        final existing = await output.readAsBytes();
        if (existing.length != payload.length) {
          throw StateError('windows_native_retry_collision');
        }
        for (var i = 0; i < payload.length; i++) {
          if (existing[i] != payload[i]) {
            throw StateError('windows_native_retry_collision');
          }
        }
      } else {
        final staging = File('${entry.path}.recovery.tmp');
        await _validate(staging.path);
        await staging.writeAsBytes(payload, flush: true);
        await staging.setLastModified(DateTime.fromMillisecondsSinceEpoch(age));
        await staging.rename(target);
      }
      await File(entry.path).delete();
    }
  }

  /// Persists revocation before the SDK can flush or the process can exit.
  Future<void> revoke() async {
    await acquire();
    await _validate('$root/revoked');
    await File('$root/revoked').writeAsString('revoked\n', flush: true);
  }

  /// Removes reports and prevents late writes from recreating the directory.
  Future<void> clear() async {
    await revoke();
    await _removeQueue();
    // Prevent a late SDK writer from recreating the revoked queue.
    await File(queue).writeAsString('', flush: true);
  }

  /// Used by storage tests; production retains the lock until process exit.
  Future<void> release() async {
    await _lock?.close();
    _lock = null;
  }
}
