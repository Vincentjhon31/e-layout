import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../develop/batch_look.dart';
import 'batch_store_memory.dart'
    if (dart.library.js_interop) 'batch_store_web.dart'
    if (dart.library.io) 'batch_store_io.dart'
    as impl;

/// One kept photo: its number in the batch and where its bytes are stored.
class BatchPhoto {
  const BatchPhoto({
    required this.id,
    required this.name,
    required this.key,
    this.size,
    this.modified,
  });

  final int id;
  final String name;

  /// The store key from [BatchStore.putPhoto].
  final String key;
  final int? size;
  final DateTime? modified;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'key': key,
    'size': size,
    'modified': modified?.toIso8601String(),
  };

  factory BatchPhoto.fromJson(Map<String, dynamic> j) => BatchPhoto(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String,
    key: j['key'] as String,
    size: (j['size'] as num?)?.toInt(),
    modified: j['modified'] == null
        ? null
        : DateTime.parse(j['modified'] as String),
  );
}

/// The kept photos in order, and the look (shared preset plus overrides).
class BatchManifest {
  const BatchManifest({required this.photos, required this.look});

  final List<BatchPhoto> photos;
  final BatchLook look;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'photos': [for (final p in photos) p.toJson()],
    'look': look.toJson(),
  };

  factory BatchManifest.fromJson(Map<String, dynamic> j) => BatchManifest(
    photos: [
      for (final p in (j['photos'] as List))
        BatchPhoto.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    look: BatchLook.fromJson(Map<String, dynamic>.from(j['look'] as Map)),
  );

  /// The manifest as JSON text.
  String encode() => jsonEncode(toJson());

  /// The manifest from JSON text, or null when it can't be read.
  static BatchManifest? tryDecode(String text) {
    try {
      return BatchManifest.fromJson(
        Map<String, dynamic>.from(jsonDecode(text) as Map),
      );
    } catch (_) {
      return null;
    }
  }
}

final Random _rng = Random.secure();

/// A fresh file-safe key: 16 random hex characters plus the file's extension
/// (lower-case letters and digits, at most 5; none when it is unusual).
String newPhotoKey(String name) {
  final hex = [
    for (var i = 0; i < 16; i++) _rng.nextInt(16).toRadixString(16),
  ].join();
  final dot = name.lastIndexOf('.');
  if (dot < 0) return hex;
  final ext = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? '$hex.$ext' : hex;
}

/// Where the batch's photos and edits are kept between sessions.
abstract class BatchStore {
  /// The kept manifest, or null when there is none or it can't be read.
  Future<BatchManifest?> load();
  Future<void> saveManifest(BatchManifest m);

  /// Stores [bytes] and returns a new key for them.
  Future<String> putPhoto(String name, Uint8List bytes);

  /// The bytes for [key]; throws a StateError when they are gone.
  Future<Uint8List> readPhoto(String key);
  Future<void> removePhoto(String key);

  /// Removes every photo and the manifest.
  Future<void> clear();

  /// Bytes used by the photos plus the manifest.
  Future<int> usedBytes();
}

/// Files under the app support folder `batch/` on devices; IndexedDB on the web.
BatchStore createBatchStore() => impl.createStore();
