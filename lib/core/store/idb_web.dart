import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A tiny key-value layer over the browser's IndexedDB: one database, one
/// object store, values are anything a JS object can hold. Same idea as the
/// web app's `js/store.js`.
class IdbBox {
  IdbBox(this.dbName, {this.storeName = 'items'});

  final String dbName;
  final String storeName;
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
        final done = Completer<web.IDBDatabase>();
        final req = web.window.indexedDB.open(dbName, 1);
        req.onupgradeneeded = ((web.Event _) {
          final db = req.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(storeName)) db.createObjectStore(storeName);
        }).toJS;
        req.onsuccess = ((web.Event _) => done.complete(req.result as web.IDBDatabase)).toJS;
        req.onerror = ((web.Event _) => done.completeError(StateError('IndexedDB: ${req.error?.message}'))).toJS;
        req.onblocked = ((web.Event _) => done.completeError(StateError('IndexedDB is blocked by another tab.'))).toJS;
        return done.future;
      }();

  Future<JSAny?> _request(web.IDBRequest req) {
    final done = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => done.complete(req.result)).toJS;
    req.onerror = ((web.Event _) => done.completeError(StateError('IndexedDB: ${req.error?.message}'))).toJS;
    return done.future;
  }

  Future<void> _transaction(String mode, void Function(web.IDBObjectStore store) work) async {
    final db = await _open();
    final tx = db.transaction(storeName.toJS, mode);
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onerror = ((web.Event _) => done.completeError(StateError('IndexedDB: ${tx.error?.message}'))).toJS;
    tx.onabort = ((web.Event _) => done.completeError(StateError('IndexedDB: ${tx.error?.message ?? 'aborted'}'))).toJS;
    work(tx.objectStore(storeName));
    await done.future;
  }

  Future<void> put(String key, JSAny value) => _transaction('readwrite', (s) => s.put(value, key.toJS));

  Future<void> delete(String key) => _transaction('readwrite', (s) => s.delete(key.toJS));

  /// Every value, in key order.
  Future<List<JSAny?>> values() async {
    final db = await _open();
    final store = db.transaction(storeName.toJS, 'readonly').objectStore(storeName);
    final result = await _request(store.getAll());
    return (result as JSArray<JSAny?>).toDart;
  }

  /// Every key.
  Future<List<String>> keys() async {
    final db = await _open();
    final store = db.transaction(storeName.toJS, 'readonly').objectStore(storeName);
    final result = await _request(store.getAllKeys());
    return [for (final k in (result as JSArray<JSAny?>).toDart) (k as JSString).toDart];
  }
}
