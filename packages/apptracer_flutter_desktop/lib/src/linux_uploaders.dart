import 'dart:ffi';
import 'dart:io';
import 'dart:convert';

import 'package:ffi/ffi.dart';

final class _PollFd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

/// Identifies only a same-user Crashpad process using this exact private queue.
bool ownsLinuxCrashpad(String executable, List<String> arguments,
        String database, int uid, int currentUid) =>
    uid == currentUid &&
    executable.split('/').last == 'crashpad_handler' &&
    arguments.contains('--database=$database');

/// Identifies the native daemon by an open lock in this exact private queue.
bool ownsLinuxNative(String executable, String lock, String database, int uid,
        int currentUid) =>
    uid == currentUid &&
    executable.split('/').last == 'sentry-crash' &&
    File(lock).parent.path == database &&
    RegExp(r'^[0-9a-f-]{36}\.run\.daemon\.lock$')
        .hasMatch(lock.split('/').last);

/// Out-of-process uploaders may outlive their original application process.
/// Linux pidfds let us terminate only the handler for our locked queue, without
/// a PID-reuse race. Supported baseline: Ubuntu x86_64, kernel >= 5.3.
class LinuxUploaders {
  static final _libc = DynamicLibrary.open('libc.so.6');
  static final _uid =
      _libc.lookupFunction<Uint32 Function(), int Function()>('getuid');
  // glibc 2.35 has no pidfd wrappers, so use the x86_64 syscall ABI directly.
  static final _open = _libc.lookupFunction<
      IntPtr Function(IntPtr, Int32, Uint32),
      int Function(int, int, int)>('syscall');
  static final _signal = _libc.lookupFunction<
      IntPtr Function(IntPtr, Int32, Int32, Pointer<Void>, Uint32),
      int Function(int, int, int, Pointer<Void>, int)>('syscall');
  static final _close =
      _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _poll = _libc.lookupFunction<
      Int32 Function(Pointer<_PollFd>, UintPtr, Int32),
      int Function(Pointer<_PollFd>, int, int)>('poll');

  /// Stops detached handlers before clearing/reusing storage or returning stop.
  /// The caller must hold the namespace lock for the entire operation.
  static Future<void> stop(String database) async {
    if (Abi.current() != Abi.linuxX64) {
      throw UnsupportedError('linux_uploaders_require_x64');
    }
    // sentry-native normalizes its database path before launching Crashpad.
    final canonicalDatabase =
        '${await Directory(database).parent.resolveSymbolicLinks()}/${database.split('/').last}';
    final uid = _uid();
    // Refuse to claim successful cancellation without a readable procfs.
    await File('/proc/self/status').readAsString();
    await for (final entry in Directory('/proc').list()) {
      final pid = int.tryParse(entry.path.split('/').last);
      if (pid == null) continue;
      if (!await _matches(entry.path, canonicalDatabase, uid)) continue;
      final descriptor = _open(434, pid, 0); // pidfd_open
      if (descriptor < 0) {
        if (await _matches(entry.path, canonicalDatabase, uid)) {
          throw StateError('linux_uploader_pidfd_failed');
        }
        continue;
      }
      try {
        // Recheck after obtaining the stable handle, before sending any signal.
        if (!await _matches(entry.path, canonicalDatabase, uid)) continue;
        if (_signal(424, descriptor, 9, nullptr, 0) != 0) {
          throw StateError('linux_uploader_stop_failed');
        }
        final poll = calloc<_PollFd>();
        try {
          poll.ref
            ..fd = descriptor
            ..events = 1;
          if (_poll(poll, 1, 2000) <= 0 || poll.ref.revents & 1 == 0) {
            throw StateError('linux_uploader_stop_timeout');
          }
        } finally {
          calloc.free(poll);
        }
      } finally {
        _close(descriptor);
      }
    }
  }

  static Future<bool> _matches(String process, String database, int uid) async {
    try {
      final status = await File('$process/status').readAsString();
      final owner =
          RegExp(r'^Uid:\s+(\d+)\s+(\d+)', multiLine: true).firstMatch(status);
      if (owner == null ||
          int.parse(owner.group(1)!) != uid ||
          int.parse(owner.group(2)!) != uid) {
        return false;
      }
      // Check the readable command line first: same-user sandboxed processes
      // may deny access to exe/fd and are unrelated to our uploaders.
      final args = utf8
          .decode(await File('$process/cmdline').readAsBytes(),
              allowMalformed: true)
          .split('\u0000');
      final name = args.first.split('/').last;
      if (name != 'sentry-crash' && name != 'crashpad_handler') return false;
      final executable = await Link('$process/exe').target();
      if (executable.split('/').last == 'sentry-crash') {
        await for (final fd in Directory('$process/fd').list()) {
          try {
            final target = await Link(fd.path).target();
            if (ownsLinuxNative(executable, target, database, uid, uid)) {
              return true;
            }
          } on FileSystemException catch (error) {
            if (error.osError?.errorCode != 2) rethrow;
          }
        }
        return false;
      }
      if (executable.split('/').last != 'crashpad_handler') return false;
      if (!args.contains('--database=$database')) return false;
      return ownsLinuxCrashpad(executable, args, database, uid, uid);
    } on FileSystemException catch (error) {
      // Processes may exit during enumeration. Other access errors must not be
      // mistaken for a stopped uploader when we cannot inspect our own process.
      if (error.osError?.errorCode == 2 || error.osError?.errorCode == 3) {
        return false;
      }
      rethrow;
    }
  }
}
