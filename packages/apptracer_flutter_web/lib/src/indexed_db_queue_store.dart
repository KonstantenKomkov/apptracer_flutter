import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:web/web.dart' as web;

/// IndexedDB-backed queue snapshot for the browser transport.
class IndexedDbQueueStore implements TracerQueueStore {
  /// Creates a store. A distinct [databaseName] isolates test or host accounts.
  IndexedDbQueueStore({this.databaseName = 'apptracer_flutter_delivery'});

  /// Browser database name.
  final String databaseName;

  static const _objectStore = 'queue';
  static const _recordKey = 'records';

  Future<bool>? _ownership;
  Completer<JSAny?>? _release;
  Future<JSAny?>? _lockRequest;

  String get _revocationKey => '$databaseName.clear_pending';

  // Each transport keeps a local snapshot between writes. Only its owner may
  // restore, replace or remove the shared snapshot until the page unloads.
  Future<bool> _acquire() {
    final acquired = Completer<bool>();
    final release = Completer<JSAny?>();
    _release = release;
    _lockRequest = web.window.navigator.locks
        .request(
          databaseName,
          web.LockOptions(ifAvailable: true),
          ((web.Lock? lock) {
            acquired.complete(lock != null);
            return lock == null
                ? Future<JSAny?>.value().toJS
                : release.future.toJS;
          }).toJS,
        )
        .toDart
        .then((_) => null, onError: (Object error) {
      if (!acquired.isCompleted) acquired.completeError(error);
      return null;
    });
    return acquired.future;
  }

  Future<bool> _ownsQueue() => _ownership ??= _acquire();

  /// Releases ownership without changing the snapshot, as when a page unloads.
  Future<void> release() async {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete();
    await _lockRequest;
    _ownership = null;
    _lockRequest = null;
    _release = null;
  }

  @override
  Future<List<TracerQueueRecord>> load() async {
    if (!await _ownsQueue()) throw StateError('Queue owned by another page');
    if (web.window.localStorage.getItem(_revocationKey) != null) {
      await _deleteSnapshot();
      web.window.localStorage.removeItem(_revocationKey);
    }
    final database = await _open();
    try {
      final transaction = database.transaction(_objectStore.toJS, 'readonly');
      final result = await _request(
          transaction.objectStore(_objectStore).get(_recordKey.toJS));
      final record = result?.dartify();
      if (record == null) return [];
      // A sentinel lets the transport diagnose and remove corrupt rows.
      if (record is! Map<Object?, Object?>) return [{}];
      final payload = record['payload'];
      if (payload is! String) return [{}];
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        return [{}];
      }
      if (decoded is! List<dynamic>) return [{}];
      return decoded.map<TracerQueueRecord>((entry) {
        if (entry is! Map<dynamic, dynamic>) return {};
        return entry.map((key, value) => MapEntry('$key', value));
      }).toList(growable: false);
    } finally {
      database.close();
    }
  }

  @override
  Future<void> save(List<TracerQueueRecord> records) async {
    if (!await _ownsQueue()) throw StateError('Queue owned by another page');
    if (web.window.localStorage.getItem(_revocationKey) != null) {
      throw StateError('Queue cleanup pending');
    }
    final database = await _open();
    try {
      final transaction = database.transaction(_objectStore.toJS, 'readwrite');
      final completed = _completed(transaction);
      final value = <String, Object?>{
        'payload': jsonEncode(records),
      }.jsify();
      transaction.objectStore(_objectStore).put(value, _recordKey.toJS);
      await completed;
    } finally {
      database.close();
    }
  }

  @override
  Future<void> clear() async {
    final wasStarted = _ownership != null;
    try {
      if (!await _ownsQueue()) {
        // A secondary page has only an in-memory queue of its own.
        if (wasStarted) return;
        throw StateError('Queue owned by another page');
      }
      var marked = false;
      try {
        web.window.localStorage.setItem(_revocationKey, '1');
        marked = true;
      } on Object {
        // The browser can deny localStorage independently of IndexedDB.
      }
      await _deleteSnapshot();
      if (marked) web.window.localStorage.removeItem(_revocationKey);
    } finally {
      await release();
    }
  }

  Future<void> _deleteSnapshot() async {
    final database = await _open();
    try {
      final transaction = database.transaction(_objectStore.toJS, 'readwrite');
      final completed = _completed(transaction);
      transaction.objectStore(_objectStore).clear();
      await completed;
    } finally {
      database.close();
    }
  }

  Future<web.IDBDatabase> _open() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      database.createObjectStore(_objectStore);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.complete(request.result as web.IDBDatabase);
      } else {
        (request.result as web.IDBDatabase).close();
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB open failed'));
      }
    }).toJS;
    request.onblocked = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB open blocked'));
      }
    }).toJS;
    return completer.future;
  }

  Future<JSAny?> _request(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB request failed'));
      }
    }).toJS;
    return completer.future;
  }

  Future<void> _completed(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    transaction.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB transaction failed'));
      }
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB transaction aborted'));
      }
    }).toJS;
    return completer.future;
  }
}
