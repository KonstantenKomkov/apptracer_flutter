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

  @override
  Future<List<TracerQueueRecord>> load() async {
    final database = await _open();
    try {
      final transaction = database.transaction(_objectStore.toJS, 'readonly');
      final result = await _request(
          transaction.objectStore(_objectStore).get(_recordKey.toJS));
      final record = result?.dartify();
      if (record is! Map<Object?, Object?>) return <TracerQueueRecord>[];
      final payload = record['payload'];
      if (payload is! String) return <TracerQueueRecord>[];
      final decoded = jsonDecode(payload);
      if (decoded is! List<dynamic>) return <TracerQueueRecord>[];
      return decoded.whereType<Map<dynamic, dynamic>>().map((entry) {
        return entry.map((key, value) => MapEntry('$key', value));
      }).toList(growable: false);
    } finally {
      database.close();
    }
  }

  @override
  Future<void> save(List<TracerQueueRecord> records) async {
    final database = await _open();
    try {
      final transaction = database.transaction(_objectStore.toJS, 'readwrite');
      final completed = _completed(transaction);
      final value = <String, Object?>{
        'payload': jsonEncode(records),
      }.jsify();
      await _request(
          transaction.objectStore(_objectStore).put(value, _recordKey.toJS));
      await completed;
    } finally {
      database.close();
    }
  }

  @override
  Future<void> clear() async {
    final database = await _open();
    try {
      final transaction = database.transaction(_objectStore.toJS, 'readwrite');
      final completed = _completed(transaction);
      await _request(transaction.objectStore(_objectStore).clear());
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
