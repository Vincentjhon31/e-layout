import 'settings.dart';

/// A shared preset for a batch of photos plus per-photo overrides.
///
/// Overrides replace the shared value per setting. Per-photo overrides never
/// carry `extras` (they are stripped), so an override is empty exactly when
/// [SettingsPatch.isEmpty] says so, and empty ones are removed from [photos].
class BatchLook {
  const BatchLook() : _shared = null, sharedName = null, _photos = null;

  BatchLook._(this._shared, this.sharedName, this._photos);

  final SettingsPatch? _shared;
  final Map<int, SettingsPatch>? _photos;

  /// The name of the shared preset, or null for none or "Custom".
  final String? sharedName;

  SettingsPatch get shared => _shared ?? _emptyPatch;
  Map<int, SettingsPatch> get photos => _photos ?? const {};

  static final SettingsPatch _emptyPatch = SettingsPatch();

  static SettingsPatch _strip(SettingsPatch p) => p.extras.isEmpty
      ? p
      : SettingsPatch(
          values: p.values,
          curves: p.curves,
          profile: p.profile,
          grayscale: p.grayscale,
        );

  static BatchLook _make(
    SettingsPatch shared,
    String? name,
    Map<int, SettingsPatch> photos,
  ) {
    final clean = <int, SettingsPatch>{};
    for (final e in photos.entries) {
      final p = _strip(e.value);
      if (!p.isEmpty) clean[e.key] = p;
    }
    return BatchLook._(shared, name, Map.unmodifiable(clean));
  }

  EditSettings settingsFor(int id) {
    final own = photos[id];
    return EditSettings.resolve([shared, ?own]);
  }

  bool hasOwnChanges(int id) => photos.containsKey(id);

  /// Replaces the shared preset ([patch] null means "None"). Overrides stay.
  BatchLook withPresetForAll(SettingsPatch? patch, String? name) =>
      _make(patch ?? SettingsPatch(), patch == null ? null : name, photos);

  /// Merges [p] over this photo's overrides.
  BatchLook withPhotoPatch(int id, SettingsPatch p) {
    final merged = (photos[id] ?? SettingsPatch()).over(_strip(p));
    return _make(shared, sharedName, {...photos, id: merged});
  }

  /// Drops this photo's overrides so it follows the shared preset again.
  BatchLook resetPhoto(int id) => withoutPhoto(id);

  BatchLook withoutPhoto(int id) =>
      _make(shared, sharedName, {...photos}..remove(id));

  /// Makes [groups] of photo [fromId] the shared preset.
  ///
  /// The source loses those overrides (they are now shared). Other photos with
  /// overrides keep them when [keepSingle], otherwise lose those groups.
  BatchLook copyToAll(
    int fromId,
    Set<ToolGroup> groups, {
    required bool keepSingle,
  }) {
    final newShared = shared.over(settingsFor(fromId).toPatch().only(groups));
    final next = <int, SettingsPatch>{};
    for (final e in photos.entries) {
      if (e.key == fromId || !keepSingle) {
        next[e.key] = e.value.without(groups);
      } else {
        next[e.key] = e.value;
      }
    }
    return _make(newShared, null, next);
  }

  Map<String, dynamic> toJson() => {
    'shared': shared.toJson(),
    'sharedName': sharedName,
    'photos': {
      for (final id in (photos.keys.toList()..sort()))
        '$id': photos[id]!.toJson(),
    },
  };

  factory BatchLook.fromJson(Map<String, dynamic> json) {
    final rawShared = json['shared'];
    final rawName = json['sharedName'];
    final rawPhotos = json['photos'];
    final photos = <int, SettingsPatch>{};
    if (rawPhotos is Map) {
      for (final e in rawPhotos.entries) {
        final id = int.tryParse('${e.key}');
        final v = e.value;
        if (id != null && v is Map) {
          photos[id] = SettingsPatch.fromJson(Map<String, dynamic>.from(v));
        }
      }
    }
    return _make(
      rawShared is Map
          ? SettingsPatch.fromJson(Map<String, dynamic>.from(rawShared))
          : SettingsPatch(),
      rawName is String ? rawName : null,
      photos,
    );
  }
}
