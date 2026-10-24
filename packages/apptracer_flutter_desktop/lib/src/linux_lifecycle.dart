// This bridge is pinned to sentry_flutter 9.30.1 / sentry-native 0.16.6.
// The official SDK still owns mapping, HTTP delivery, scope and crash capture.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_flutter/src/native/c/binding.dart' as binding;
import 'package:sentry_flutter/src/native/c/sentry_native.dart' as sdk;

import 'linux_storage.dart';
import 'linux_contexts.dart';
import 'linux_uploaders.dart';

/// Adds consent and owned storage around the official Linux native SDK.
/// Detached native uploaders are stopped through Linux pidfds on revocation.
class LinuxLifecycle implements Integration<SentryFlutterOptions>, Transport {
  /// Queue shared by authorized restarts of this application.
  final storage = LinuxStorage.forApplication();
  SentryFlutterOptions? _options;
  bool _started = false;
  bool _revoked = false;
  DynamicLibrary? _library;
  Pointer<Void> Function(Pointer<Uint8>, int)? _deserialize;
  void Function(Pointer<Void>)? _capture;
  bool Function() _isAuthorized = () => false;

  /// Metadata collected only during authorized native startup.
  LinuxContexts? contexts;

  /// Prepares writable storage before any native initialization.
  Future<void> prepare(bool preserve) async {
    await storage.acquire();
    await LinuxUploaders.stop(storage.queue);
    await storage.prepare(preserve);
  }

  /// Uses the official native HTTP/cache worker for SDK-serialized Dart events.
  void configure(SentryFlutterOptions options,
      {required bool Function() isAuthorized}) {
    _isAuthorized = isAuthorized;
    _revoked = false;
    _options = options;
    options.transport = this;
    options.nativeDatabasePath = storage.queue;
    options.addIntegration(this);
  }

  @override
  Future<void> call(Hub hub, SentryFlutterOptions options) async {
    if (!_isAuthorized()) throw StateError('linux_start_revoked');
    contexts = await LinuxContexts.collect();
    if (!_isAuthorized()) throw StateError('linux_start_revoked');
    final library = _library = DynamicLibrary.open('libsentry.so');
    // Resolve every required symbol before allocating options or starting SDK.
    final requireConsent = library.lookupFunction<
        Void Function(Pointer<binding.sentry_options_s>, Int),
        void Function(Pointer<binding.sentry_options_s>,
            int)>('sentry_options_set_require_user_consent');
    final give = library.lookupFunction<Void Function(), void Function()>(
        'sentry_user_consent_give');
    final cache = library.lookupFunction<
        Void Function(Pointer<binding.sentry_options_s>, Int),
        void Function(Pointer<binding.sentry_options_s>,
            int)>('sentry_options_set_cache_keep');
    final retry = library.lookupFunction<
        Void Function(Pointer<binding.sentry_options_s>, Int),
        void Function(Pointer<binding.sentry_options_s>,
            int)>('sentry_options_set_http_retry');
    final timeout = library.lookupFunction<
        Void Function(Pointer<binding.sentry_options_s>, Uint64),
        void Function(Pointer<binding.sentry_options_s>,
            int)>('sentry_options_set_shutdown_timeout');
    _deserialize = library.lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, UintPtr),
        Pointer<Void> Function(
            Pointer<Uint8>, int)>('sentry_envelope_deserialize');
    _capture = library.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('sentry_capture_envelope');
    library
        .lookup<NativeFunction<Void Function()>>('sentry_user_consent_revoke');
    final enabled = library
        .lookupFunction<Int Function(), int Function()>('sentry_is_enabled');
    if (enabled() != 0) throw StateError('native_sentry_already_owned');
    final directory = File(Platform.resolvedExecutable).parent.path;
    String? handlerPath;
    for (final relative in [
      'lib/sentry-crash',
      'bin/sentry-crash',
      'sentry-crash'
    ]) {
      final file = File('$directory/$relative');
      if (file.existsSync() && file.statSync().mode & 0x49 != 0) {
        handlerPath = file.resolveSymbolicLinksSync();
        break;
      }
    }
    if (handlerPath == null) throw StateError('linux_native_handler_missing');
    final handler = library.lookupFunction<
        Void Function(Pointer<binding.sentry_options_s>, Pointer<Utf8>),
        void Function(Pointer<binding.sentry_options_s>,
            Pointer<Utf8>)>('sentry_options_set_handler_path');
    final reporting = library.lookupFunction<
        Void Function(Pointer<binding.sentry_options_s>, Int),
        void Function(Pointer<binding.sentry_options_s>,
            int)>('sentry_options_set_crash_reporting_mode');
    final nativeOptions = sdk.SentryNative(options).createOptions(options);
    final path = handlerPath.toNativeUtf8();
    try {
      handler(nativeOptions, path);
    } finally {
      calloc.free(path);
    }
    // Official native stackwalking + minidump attachment over /envelope/.
    reporting(nativeOptions, 2);
    requireConsent(nativeOptions, 1);
    cache(nativeOptions, 1); // SENTRY_CACHE_KEEP_OFFLINE
    retry(nativeOptions, 1);
    // The crash daemon shares this value and needs time to receive the HTTP
    // acknowledgement. Stop revokes consent before close, so queued uploads
    // remain forbidden; an in-flight app transfer is cancelled within 2 s.
    timeout(nativeOptions, 2000);
    if (sdk.SentryNative.native.init(nativeOptions) != 0) {
      throw StateError('linux_native_init_failed');
    }
    _started = true;
    final native = sdk.SentryNative(options);
    for (final entry in contexts!.values.entries) {
      native.setContexts(entry.key, entry.value);
    }
    give();
    options.sdk.addIntegration('apptracerLinuxLifecycle');
  }

  /// Cancels before waiting for the adapter's serialized operations to finish.
  void cancel() {
    _revoked = true;
    // Both Dart envelopes and minidumps now obey native consent.
    if (_started) {
      _library!.lookupFunction<Void Function(), void Function()>(
          'sentry_user_consent_revoke')();
    }
  }

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    if (!_started || _revoked || !_isAuthorized()) return SentryId.empty();
    envelope.header.sentAt = _options!.clock();
    final bytes = BytesBuilder(copy: false);
    await for (final block in envelope.envelopeStream(_options!)) {
      bytes.add(block);
    }
    // Consent may change while the official SDK serializes attachments/items.
    if (_revoked || !_isAuthorized()) return SentryId.empty();
    final data = bytes.takeBytes();
    final buffer = calloc<Uint8>(data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      final nativeEnvelope = _deserialize!(buffer, data.length);
      if (nativeEnvelope == nullptr) {
        throw StateError('linux_envelope_deserialization_failed');
      }
      // Ownership transfers to the official SDK, including offline persistence.
      _capture!(nativeEnvelope);
    } finally {
      calloc.free(buffer);
    }
    return envelope.header.eventId;
  }

  /// Disables new uploads and durably revokes replay in future processes.
  Future<void> revoke() async {
    cancel();
    await storage.revoke();
    await LinuxUploaders.stop(storage.queue);
  }

  @override
  Future<void> close() async {
    await revoke();
    if (_started) {
      sdk.SentryNative.native.close();
      _started = false;
    }
  }

  /// Purges only the adapter's owned queue, after native shutdown.
  Future<void> clear() => storage.clear();
}
