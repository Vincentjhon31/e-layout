import '../../platform/device_noun.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/analysis/frame_split.dart';
import '../../core/develop/auto_masks.dart';
import '../../core/develop/batch_look.dart';
import '../../core/develop/photo_developer.dart';
import '../../core/develop/profile_table.dart';
import '../../core/develop/settings.dart';
import '../../core/export/photo_exporter.dart';
import '../../core/fonts/font_registry.dart';
import '../../core/model/layout_codec.dart';
import '../../core/model/layout_doc.dart';
import '../../core/model/layout_ops.dart';
import '../../core/render/layout_prep.dart';
import '../../core/presets/builtin_presets.dart';
import '../../core/presets/preset.dart';
import '../../core/presets/preset_codec.dart';
import '../../core/presets/preset_import.dart';
import '../../core/render/photo_geometry.dart';
import '../../core/store/batch_store.dart';
import '../../core/store/bundled_layouts.dart';
import '../../core/store/font_store.dart';
import '../../core/store/layout_store.dart';
import '../../core/store/preset_store.dart';
import '../../core/store/settings_store.dart';
import '../../platform/file_sharer.dart';
import '../../platform/gallery_saver.dart';
import '../../platform/photo_picker.dart';
import '../../platform/temp_files.dart';
import '../../ui/widgets/note_box.dart';
import '../layouts/import_layout.dart';
import 'export_job.dart';

/// Long edge of the small copy kept in memory per photo.
const int kPreviewEdge = 480;

/// Warn when a layout picture gets enlarged more than this (app.js SOFT_SCALE).
const double kSoftScale = 1.5;

/// Preset files bigger than this are not read.
const int kPresetFileCap = 300 * 1024 * 1024;

const String _tooBigLine = ' Some files were too big to read.';

class LayoutItem {
  LayoutItem(this.doc, this.builtin, this.prep);
  LayoutDoc doc;
  final bool builtin;
  LayoutPrep prep;

  /// Bumped whenever the doc or its pictures change, so thumbnails repaint.
  int revision = 0;
  String get id => doc.id;
}

enum PhotoStatus { loading, ready, error }

class PhotoItem {
  PhotoItem(this.id, this.source, {this.key}) : name = source.name;
  final int id;

  /// Where the bytes come from: the picked file until the batch store holds
  /// a copy, then the store.
  PickedPhoto source;
  final String name;

  /// Where the batch store keeps this photo's bytes (null until it is kept,
  /// and when keeping it failed).
  String? key;

  // Waiting to be copied into the batch store (new photos only).
  bool _toCopy = false;

  // Copying into the batch store failed.
  bool _keepFailed = false;
  PhotoStatus status = PhotoStatus.loading;
  int width = 0, height = 0;
  ui.Image? preview;

  /// [preview] with the photo's edits (null when they are neutral).
  ui.Image? developed;

  /// The settings and profile [developed] was made with.
  String? developedKey;
  String? error;
}

/// One photo's automatic maps while they are computed and after.
class _MapsEntry {
  late final Future<AutoMaps?> future;
  AutoMaps? maps;
  bool freed = false;

  void free() {
    freed = true;
    maps?.dispose();
    maps = null;
  }
}

/// A note under the layout row (the web app's notices).
class Notice {
  const Notice(this.kind, this.text, {this.actionLabel, this.action});
  final NoteKind kind;
  final String text;
  final String? actionLabel;
  final Future<void> Function()? action;
}

/// app.js ratioText().
String ratioText(double r) {
  const known = [
    (1.0, '1:1'),
    (4 / 5, '4:5'),
    (3 / 4, '3:4'),
    (2 / 3, '2:3'),
    (3 / 2, '3:2'), //
    (4 / 3, '4:3'),
    (16 / 9, '16:9'),
    (9 / 16, '9:16'),
    (math.sqrt2, 'A4, 1.41:1'),
  ];
  for (final (v, t) in known) {
    if ((v - r).abs() < 0.02) return t;
  }
  return '${r.toStringAsFixed(2)}:1';
}

/// The photos screen: layouts, photos, notices and saving.
class HomeController extends ChangeNotifier {
  HomeController({
    required this.layoutStore,
    required this.settingsStore,
    required this.picker,
    required this.saver,
    required this.sharer,
    required this.temp,
    PhotoExporter? exporter,
    Future<List<LayoutDoc>> Function()? bundled,
    FontStore? fontStore,
    this.convertFont,
    PresetStore? presetStore,
    BatchStore? batchStore,
    PhotoDeveloper? developer,
    Future<PhotoDeveloper?>? developerLoad,
  }) : _developer = developer,
       _ownExporter = exporter == null,
       exporter = exporter ?? PhotoExporter(developer: developer),
       bundled = bundled ?? loadBundledLayouts,
       fontStore = fontStore ?? createFontStore(),
       presetStore = presetStore ?? createPresetStore(),
       batchStore = batchStore ?? createBatchStore() {
    if (developer == null && developerLoad != null) {
      _developerReady = developerLoad.then(
        (d) {
          _developerReady = null;
          if (d != null) _useDeveloper(d);
          _changed();
        },
        onError: (Object e) {
          _developerReady = null;
          debugPrint('Photo editing is not available: $e');
          _changed();
        },
      );
    }
  }

  final LayoutStore layoutStore;
  final SettingsStore settingsStore;
  final PhotoPicker picker;
  final GallerySaver saver;
  final FileSharer sharer;
  final TempFiles temp;

  /// Renders saved photos. The default one is replaced when the developer
  /// arrives later.
  PhotoExporter exporter;
  final bool _ownExporter;
  final Future<List<LayoutDoc>> Function() bundled;

  /// Fonts the person added, kept on this phone.
  final FontStore fontStore;

  /// Turns WOFF font bytes into TTF (null when it can't).
  final FontConverter? convertFont;

  /// Presets and colour profiles kept on this device.
  final PresetStore presetStore;

  /// The photos and their edits, kept between visits.
  final BatchStore batchStore;

  /// Applies photo edits; null while it loads and when it could not be
  /// loaded here.
  PhotoDeveloper? get developer => _developer;
  PhotoDeveloper? _developer;

  // Set while the developer passed as `developerLoad` is still loading.
  Future<void>? _developerReady;

  void _useDeveloper(PhotoDeveloper d) {
    if (_disposed) return;
    _developer = d;
    if (_ownExporter) exporter = PhotoExporter(developer: d);
    _developChanged();
  }

  List<Preset> presets = [];

  /// The looks shipped with the app. Kept apart from [presets]: never stored,
  /// never removed.
  List<Preset> builtinPresets = const [];

  /// Colour profiles by id.
  Map<String, Profile> profiles = {};

  /// The shared preset and each photo's own changes.
  BatchLook look = const BatchLook();

  /// Bytes the kept batch takes on this device.
  int keptBytes = 0;

  /// False after a photo could not be kept or the manifest could not be
  /// saved: photos may not survive a restart.
  bool batchOk = true;

  /// False while the developer loads and when it could not be loaded.
  bool get editingAvailable => developer != null;

  List<LayoutItem> layouts = [];
  String? selectedId;
  List<PhotoItem> photos = [];
  AppSettings settings = AppSettings();
  ExportJob? job;

  /// The line under the save button (result of the last save).
  String message = '';

  /// Notes from the last import or layout action.
  List<Notice> layoutNotes = [];
  bool ready = false;
  bool storageOk = true;
  List<String> lastSaved = [];

  int _nextId = 1;
  // Created lazily, in the zone of the first add (a future made earlier would
  // deliver its callbacks in the zone it was made in).
  Future<void>? _queue;
  // Every batch-store write and measurement, one after another (also lazy).
  Future<void>? _storeQueue;
  // A manifest write that is queued but has not started: later changes join it.
  Future<void>? _pendingManifest;

  /// True when the photo set changed since the kept bytes were measured. A
  /// look-only manifest write does not measure.
  bool _measureDirty = false;
  // Bumped by clearPhotos: copies started before it are thrown away.
  int _batchGen = 0;
  // The photo being developed: its images are freed by that job, not by
  // remove or clear.
  PhotoItem? _developing;
  bool _disposed = false;

  LayoutItem? get current {
    for (final l in layouts) {
      if (l.id == selectedId) return l;
    }
    return null;
  }

  List<PhotoItem> get readyPhotos => [
    for (final p in photos)
      if (p.status == PhotoStatus.ready) p,
  ];
  int get loadingCount =>
      photos.where((p) => p.status == PhotoStatus.loading).length;
  int get errorCount =>
      photos.where((p) => p.status == PhotoStatus.error).length;
  bool get saving => job != null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    settings = await settingsStore.load();
    await loadStoredFonts();
    final list = <LayoutItem>[];
    for (final doc in await bundled()) {
      list.add(LayoutItem(doc, true, await prepareLayout(doc)));
    }
    List<LayoutDoc> saved = [];
    try {
      saved = await layoutStore.loadAll();
    } catch (e) {
      storageOk = false;
      debugPrint('Saved layouts are unavailable: $e');
    }
    for (final doc in saved) {
      // Older layouts: pins now follow their pieces. Saved back so this happens once.
      if (upgradePins(doc)) await _store(doc);
      list.add(LayoutItem(doc, false, await prepareLayout(doc)));
    }
    layouts = list;
    final remembered = list.any((l) => l.id == settings.layoutId);
    selectedId = remembered
        ? settings.layoutId
        : (list.isEmpty ? null : list.first.id);
    await _loadPresets();
    await _restoreBatch();
    ready = true;
    _changed();
  }

  Future<void> _loadPresets() async {
    try {
      builtinPresets = await loadBuiltinPresets();
    } catch (e) {
      debugPrint('Built-in presets are unavailable: $e');
    }
    try {
      presets = await presetStore.loadPresets();
    } catch (e) {
      debugPrint('Presets are unavailable: $e');
    }
    try {
      profiles = {for (final p in await presetStore.loadProfiles()) p.id: p};
    } catch (e) {
      debugPrint('Profiles are unavailable: $e');
    }
  }

  /// One photo per kept entry; its bytes are read from the store when needed.
  Future<void> _restoreBatch() async {
    BatchManifest? m;
    try {
      m = await _storeOp(batchStore.load);
    } catch (e) {
      debugPrint('The kept photos are unavailable: $e');
    }
    if (m != null) {
      var next = m.look;
      final ids = <int>{};
      for (final bp in m.photos) {
        if (!ids.add(bp.id)) continue;
        final source = _storedSource(bp.key, bp.name, bp.size, bp.modified);
        final item = PhotoItem(bp.id, source, key: bp.key);
        photos.add(item);
        _nextId = math.max(_nextId, bp.id + 1);
        _queuePreview(item);
      }
      // Changes for photos that are no longer kept are dropped.
      for (final id in m.look.photos.keys) {
        if (!ids.contains(id)) next = next.withoutPhoto(id);
      }
      look = next;
    }
    await _storeOp(_measureKept);
  }

  PickedPhoto _storedSource(
    String key,
    String name,
    int? size,
    DateTime? modified, {
    String? path,
  }) => PickedPhoto(
    name: name,
    path: path,
    readBytes: () => batchStore.readPhoto(key),
    size: size,
    modified: modified,
  );

  /// Runs [op] after every batch-store operation queued before it. A failure
  /// reaches only this caller; later operations still run.
  Future<T> _storeOp<T>(Future<T> Function() op) {
    final done = Completer<T>();
    _storeQueue = (_storeQueue ?? Future<void>.value()).then((_) async {
      try {
        done.complete(await op());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Reads the bytes the batch takes. Runs inside the store queue. A failed
  /// measurement keeps the last value and does not change [batchOk].
  Future<void> _measureKept() async {
    try {
      keptBytes = await batchStore.usedBytes();
      _measureDirty = false;
    } catch (e) {
      // Try again on the next manifest write.
      _measureDirty = true;
      debugPrint('The kept photos could not be measured: $e');
    }
  }

  /// Writes the manifest (the photos kept at that moment and the look), then
  /// measures. A write that is still waiting covers later changes too.
  Future<void> _saveManifest() {
    final waiting = _pendingManifest;
    if (waiting != null) return waiting;
    final next = _storeOp(() {
      _pendingManifest = null;
      return _writeManifest();
    });
    _pendingManifest = next;
    return next;
  }

  Future<void> _writeManifest() async {
    if (_disposed) return;
    final m = BatchManifest(
      photos: [
        for (final p in photos)
          if (p.key != null)
            BatchPhoto(
              id: p.id,
              name: p.name,
              key: p.key!,
              size: p.source.size,
              modified: p.source.modified,
            ),
      ],
      look: look,
    );
    try {
      await batchStore.saveManifest(m);
      // Good again, unless a photo in the batch could not be kept.
      batchOk = !photos.any((p) => p._keepFailed);
    } catch (e) {
      batchOk = false;
      debugPrint('The kept photos could not be saved: $e');
    }
    if (_measureDirty) await _measureKept();
    _changed();
  }

  /// Registers every font kept on this phone (app.js loadStoredFonts).
  Future<void> loadStoredFonts() async {
    try {
      for (final f in await fontStore.loadAll()) {
        try {
          await FontRegistry.instance.register(
            f.family,
            f.weight,
            f.style,
            f.bytes,
            variable: f.variable,
            source: f.source,
          );
        } catch (e) {
          debugPrint('Font ${f.family} could not be loaded: $e');
        }
      }
    } catch (e) {
      debugPrint('Fonts kept on this phone are unavailable: $e');
    }
  }

  Future<void> _store(LayoutDoc doc) async {
    doc.updated = DateTime.now().millisecondsSinceEpoch;
    try {
      await layoutStore.save(doc);
    } catch (e) {
      debugPrint('Layout not saved: $e');
    }
  }

  Future<void> selectLayout(String id) async {
    selectedId = id;
    settings.layoutId = id;
    message = '';
    _changed();
    await settingsStore.save(settings);
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    message = '';
    _changed();
    await settingsStore.save(settings);
  }

  // ---------- photos ----------

  Future<void> pickPhotos() async => addPhotos(await picker.pickPhotos());

  /// "Add a folder" (Windows): every photo in a folder and its subfolders.
  Future<void> addFolder() async => addPhotos(await picker.pickFolder());

  /// Files dropped on Home (Windows and the website). On the layout row every
  /// file is a layout or a picture to import; elsewhere layout files are
  /// imported and the pictures are added as photos.
  Future<void> handleDrop(
    List<PickedPhoto> files, {
    bool onLayouts = false,
  }) async {
    if (files.isEmpty) return;
    if (onLayouts) return importFiles(files);
    final layoutFiles = [
      for (final f in files)
        if (isLayoutFileName(f.name)) f,
    ];
    final photoFiles = [
      for (final f in files)
        if (!isLayoutFileName(f.name)) f,
    ];
    if (layoutFiles.isNotEmpty) await importFiles(layoutFiles);
    if (photoFiles.isNotEmpty) await addPhotos(photoFiles);
  }

  /// Adds the new photos at once, loading. Each one is copied into the batch
  /// store by its preview job.
  Future<void> addPhotos(List<PickedPhoto> picked) async {
    final known = {for (final p in photos) p.source.key};
    final fresh = <PickedPhoto>[];
    for (final f in picked) {
      if (known.add(f.key)) fresh.add(f);
    }
    fresh.sort((a, b) => naturalCompare(a.name, b.name));
    for (final f in fresh) {
      final item = PhotoItem(_nextId++, f).._toCopy = true;
      photos.add(item);
      _queuePreview(item);
    }
    message = '';
    _changed();
  }

  /// Copies [bytes] into the batch store and switches [p] to that copy. When
  /// the copy fails the photo stays for this visit only. A copy that finishes
  /// after [p] was removed or the batch was cleared is deleted again.
  Future<void> _keep(PhotoItem p, Uint8List bytes) async {
    final gen = _batchGen;
    p._toCopy = false;
    final String key;
    try {
      key = await _storeOp(() => batchStore.putPhoto(p.name, bytes));
    } catch (e) {
      debugPrint('Could not keep ${p.name}: $e');
      if (gen == _batchGen && photos.contains(p)) {
        p._keepFailed = true;
        batchOk = false;
        _changed();
      }
      return;
    }
    if (gen != _batchGen || !photos.contains(p) || _disposed) {
      _storeOp(() async {
        try {
          await batchStore.removePhoto(key);
        } catch (e) {
          debugPrint('Could not delete a copy no longer needed: $e');
        }
        await _measureKept();
        _changed();
      });
      return;
    }
    final f = p.source;
    p
      ..key = key
      ..source = _storedSource(key, f.name, f.size, f.modified, path: f.path);
    _measureDirty = true;
    _saveManifest();
  }

  void _enqueue(Future<void> Function() job) {
    _queue = (_queue ?? Future<void>.value()).then((_) => job()).catchError((
      Object e,
    ) {
      debugPrint('Preview failed: $e');
    });
  }

  void _queuePreview(PhotoItem item) => _enqueue(() => _loadPreview(item));

  /// Completes when every queued preview and batch-store operation is done.
  Future<void> whenIdle() async {
    Future<void>? previews, store;
    do {
      previews = _queue;
      store = _storeQueue;
      if (previews != null) await previews;
      if (store != null) await store;
    } while (!identical(previews, _queue) || !identical(store, _storeQueue));
  }

  Future<void> _loadPreview(PhotoItem p) async {
    if (!photos.contains(p) || _disposed) return;
    try {
      final bytes = await p.source.readBytes();
      // New photos: the same bytes go into the batch store, then the preview.
      if (p._toCopy) await _keep(p, bytes);
      if (!photos.contains(p) || _disposed) return;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? desc;
      try {
        desc = await ui.ImageDescriptor.encoded(buffer);
        final w = desc.width, h = desc.height;
        final s = math.min(1.0, kPreviewEdge / math.max(w, h));
        final codec = await desc.instantiateCodec(
          targetWidth: math.max(1, (w * s).round()),
          targetHeight: math.max(1, (h * s).round()),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        final img = frame.image;
        // The codec turns sideways phone photos upright (EXIF); the descriptor does not.
        final turned = w != h && (img.width > img.height) != (w > h);
        p
          ..width = turned ? h : w
          ..height = turned ? w : h
          ..preview = img
          ..status = PhotoStatus.ready;
        if (!photos.contains(p) || _disposed) {
          img.dispose();
          p.preview = null;
        }
      } finally {
        desc?.dispose();
        buffer.dispose();
      }
    } catch (_) {
      p
        ..status = PhotoStatus.error
        ..error = "Can't open this file.";
    }
    _changed();
    final dev = developer;
    if (dev != null && p.preview != null) {
      await _developThumb(p);
      dev.clearCache();
    }
  }

  /// What [p]'s thumbnail depends on: its settings and the profile table.
  String _thumbKey(EditSettings s) {
    final table = profileFor(s);
    return '${s.key}|${table == null ? '' : identityHashCode(table)}';
  }

  /// Makes [p]'s developed thumbnail again when its settings changed.
  Future<void> _developThumb(PhotoItem p) async {
    final dev = developer;
    final src = p.preview;
    if (dev == null ||
        src == null ||
        _disposed ||
        !photos.contains(p) ||
        p.width <= 0) {
      return;
    }
    final s = settingsFor(p);
    final k = _thumbKey(s);
    if (k == p.developedKey) return;
    ui.Image? next;
    _developing = p;
    try {
      if (!s.isNeutral) {
        final auto = await autoMapsFor(p);
        try {
          next = await dev.develop(
            src,
            s,
            profile: profileFor(s),
            scale: src.width / p.width,
            fullSize: ui.Size(src.width.toDouble(), src.height.toDouble()),
            lutSize: 33,
            auto: auto,
          );
        } finally {
          auto?.dispose();
        }
      }
    } catch (e) {
      debugPrint('Could not develop ${p.name}: $e');
    } finally {
      _developing = null;
    }
    if (_disposed || !photos.contains(p)) {
      next?.dispose();
      _release(p);
      return;
    }
    p.developed?.dispose();
    p
      ..developed = next
      ..developedKey = k;
    _changed();
  }

  /// Makes the thumbnails whose settings changed again, one after another.
  void _developChanged() {
    if (developer == null) return;
    _enqueue(() async {
      for (final p in [...photos]) {
        await _developThumb(p);
      }
      developer?.clearCache();
    });
  }

  /// Frees [p]'s images and automatic maps (left to the develop job while it
  /// uses them).
  void _release(PhotoItem p) {
    if (identical(p, _developing)) return;
    p.preview?.dispose();
    p.preview = null;
    p.developed?.dispose();
    p.developed = null;
    _autoMaps.remove(p.id)?.free();
  }

  // Each photo's automatic maps, by photo id, made when first needed.
  final Map<int, _MapsEntry> _autoMaps = {};

  /// [p]'s automatic maps (Subject and Sky) for previews and saves, as a
  /// clone the caller owns and disposes once its render is done.
  ///
  /// The maps are computed once, from the photo's upright preview, the first
  /// time its settings need them ([needsAutoMaps]; [settings] stands for its
  /// settings when given, such as the editor's while a slider moves). The
  /// cache keeps the original and frees it with the photo (removePhoto,
  /// clearPhotos, dispose); clones handed out stay valid until their owners
  /// dispose them. Calls at the same time share one computation. Null when
  /// the settings do not need them, before the preview is ready, and when
  /// they could not be computed (the next call tries again).
  Future<AutoMaps?> autoMapsFor(PhotoItem p, [EditSettings? settings]) async {
    final entry = _autoMaps[p.id] ?? _startAutoMaps(p, settings);
    if (entry == null) return null;
    final maps = await entry.future;
    // Freed meanwhile (the photo went): nothing to hand out.
    if (maps == null || entry.freed) return null;
    return maps.clone();
  }

  /// Starts computing [p]'s maps when they are needed; null when not.
  _MapsEntry? _startAutoMaps(PhotoItem p, EditSettings? settings) {
    final src = p.preview;
    if (_disposed ||
        src == null ||
        !photos.contains(p) ||
        !needsAutoMaps(settings ?? settingsFor(p))) {
      return null;
    }
    // Its own handle, so freeing the preview meanwhile is safe.
    final copy = src.clone();
    final entry = _MapsEntry();
    entry.future = () async {
      try {
        final maps = await (computeAutoMapsOverride ?? computeAutoMaps)(copy);
        if (entry.freed) {
          maps.dispose();
          return null;
        }
        return entry.maps = maps;
      } catch (e) {
        debugPrint('Could not find the subject and sky of ${p.name}: $e');
        // Not kept: the next call tries again.
        if (identical(_autoMaps[p.id], entry)) _autoMaps.remove(p.id);
        return null;
      } finally {
        copy.dispose();
      }
    }();
    _autoMaps[p.id] = entry;
    return entry;
  }

  /// Replaces [computeAutoMaps], for tests (such as one that always fails).
  @visibleForTesting
  Future<AutoMaps> Function(ui.Image photo)? computeAutoMapsOverride;

  /// The cached original of [p]'s maps, for tests (never dispose it).
  @visibleForTesting
  AutoMaps? debugCachedAutoMaps(PhotoItem p) => _autoMaps[p.id]?.maps;

  Future<void> removePhoto(int id) async {
    final i = photos.indexWhere((p) => p.id == id);
    if (i < 0 || saving) return;
    final p = photos.removeAt(i);
    _release(p);
    look = look.withoutPhoto(id);
    message = '';
    _changed();
    // The manifest first, so a restart never lists bytes that are gone.
    await _saveManifest();
    final key = p.key;
    if (key != null) {
      await _storeOp(() async {
        try {
          await batchStore.removePhoto(key);
        } catch (e) {
          debugPrint('Could not remove the kept copy of ${p.name}: $e');
        }
        await _measureKept();
      });
      _changed();
    }
  }

  /// Removes every photo, its kept copy and the look. Copies still on their
  /// way into the store are deleted when they arrive.
  Future<void> clearPhotos() async {
    if (saving) return;
    _batchGen++;
    for (final p in photos) {
      _release(p);
    }
    photos = [];
    look = const BatchLook();
    message = '';
    _changed();
    try {
      await _storeOp(batchStore.clear);
    } catch (e) {
      debugPrint('Could not clear the kept photos: $e');
    }
    _measureDirty = true;
    await _saveManifest();
  }

  // ---------- looks and presets ----------

  EditSettings settingsFor(PhotoItem p) => look.settingsFor(p.id);

  bool hasOwnChanges(PhotoItem p) => look.hasOwnChanges(p.id);

  /// The colour table for [s]'s profile; null for none or one not imported
  /// (the profile's amount then does nothing).
  ProfileTable? profileFor(EditSettings s) => _profileOf(s.profile)?.table;

  Profile? _profileOf(ProfileRef? ref) {
    if (ref == null || ref.isNone) return null;
    final direct = profiles[ref.id];
    if (direct != null) return direct;
    final upper = ref.id.trim().toUpperCase();
    for (final p in profiles.values) {
      if (p.id.trim().toUpperCase() == upper) return p;
    }
    return null;
  }

  /// Uses [next] as the look: kept at once, changed thumbnails made again.
  Future<void> setLook(BatchLook next) async {
    look = next;
    _changed();
    _developChanged();
    await _saveManifest();
  }

  /// [src] (a preview of a photo [srcPhotoWidth] pixels wide) with [preset]
  /// applied, at a fast table size, for the picker's thumbnails. The caller
  /// owns the result. Null when editing is not available.
  Future<ui.Image?> developPreview(
    ui.Image src,
    int srcPhotoWidth,
    Preset preset,
  ) async {
    final dev = developer;
    if (dev == null || srcPhotoWidth <= 0) return null;
    final s = EditSettings.resolve([preset.patch]);
    return dev.develop(
      src,
      s,
      profile: profileFor(s),
      scale: src.width / srcPhotoWidth,
      fullSize: ui.Size(src.width.toDouble(), src.height.toDouble()),
      lutSize: 17,
    );
  }

  /// Makes [p] the shared preset (null for none); single-photo changes stay.
  Future<void> choosePresetForAll(Preset? p) =>
      setLook(look.withPresetForAll(p?.patch, p?.name, p?.id));

  /// Reads preset and profile files, keeps what they hold and returns the
  /// line to show. Files over [kPresetFileCap] are not read.
  Future<String> importPresets(List<PickedPhoto> files) async {
    final read = <(String, Uint8List)>[];
    var tooBig = false;
    for (final f in files) {
      if ((f.size ?? 0) > kPresetFileCap) {
        tooBig = true;
        continue;
      }
      try {
        read.add((f.name, await f.readBytes()));
      } catch (e) {
        debugPrint('Could not read ${f.name}: $e');
      }
    }
    final r = importPresetFiles(read, known: profiles);
    for (final p in r.profiles) {
      profiles[p.id] = p;
      try {
        await presetStore.saveProfile(p);
      } catch (e) {
        debugPrint('Profile not kept: $e');
      }
    }
    for (final p in r.presets) {
      await _keepPreset(p);
    }
    var line = r.line;
    if (tooBig && !line.endsWith(_tooBigLine)) line += _tooBigLine;
    _changed();
    if (r.profiles.isNotEmpty) _developChanged();
    return line;
  }

  /// Adds [p] to [presets] (replacing one with its id) and stores it.
  Future<void> _keepPreset(Preset p) async {
    final i = presets.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      presets[i] = p;
    } else {
      presets.add(p);
    }
    try {
      await presetStore.savePreset(p);
    } catch (e) {
      debugPrint('Preset not kept: $e');
    }
  }

  /// Keeps [s] as a preset of the person's own.
  Future<Preset> savePreset(String name, EditSettings s) async {
    final p = Preset(
      id: uid('P'),
      name: name,
      kind: PresetKind.user,
      created: DateTime.now(),
      patch: s.toPatch(),
    );
    await _keepPreset(p);
    _changed();
    return p;
  }

  /// The built-in or kept preset with [id], or null.
  Preset? presetById(String id) {
    for (final p in [...builtinPresets, ...presets]) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Deletes a preset of the person's own. A built-in look stays.
  Future<void> removePreset(Preset p) async {
    if (p.kind == PresetKind.builtin) return;
    presets.removeWhere((e) => e.id == p.id);
    if (look.sharedId == p.id) {
      look = look.withoutPresetName();
      unawaited(_saveManifest());
    }
    _changed();
    try {
      await presetStore.removePreset(p.id);
    } catch (e) {
      debugPrint('Could not delete the preset: $e');
    }
  }

  /// Writes `<name>.preset.json` (with its profile) and opens the share sheet.
  Future<void> sharePreset(Preset p) async {
    final bytes = encodePresetFile(p, _profileOf(p.patch.profile));
    final name = '${safeFileName(p.name)}.preset.json';
    if (!sharer.needsCopies) {
      await sharer.exportFile(name, bytes);
      return;
    }
    await temp.clear('export');
    final path = await temp.write('export', name, bytes);
    await sharer.shareFiles([path]);
  }

  // ---------- notices ----------

  List<Notice> get notices {
    final out = [...layoutNotes];
    final item = current;
    if (item != null) {
      var widest = 0;
      for (final p in readyPhotos) {
        widest = math.max(widest, photoGeometry(p.width, p.height, item.doc).w);
      }
      // Thin pictures (borders, lines) don't visibly blur, so only bigger ones are mentioned.
      final soft = widest > 0
          ? softPictures(
              item.doc,
              item.prep,
              widest,
              kSoftScale,
            ).where((s) => s.natural >= 60).toList()
          : <SoftPicture>[];
      if (soft.length == 1) {
        final s = soft.first;
        out.add(
          Notice(
            NoteKind.warning,
            '"${s.name}" is ${s.natural} px wide but gets stretched to ${s.shown} px on your largest photo, so it will look soft. Replace it with a bigger picture in the editor.',
          ),
        );
      } else if (soft.length > 1) {
        final list = soft
            .take(4)
            .map((s) => '"${s.name}" (${s.natural} to ${s.shown} px)')
            .join(', ');
        final more = soft.length > 4 ? ' and ${soft.length - 4} more' : '';
        out.add(
          Notice(
            NoteKind.warning,
            'Some pictures get stretched on your largest photo and will look soft: $list$more. Use a bigger original picture for a sharp result.',
          ),
        );
      }
      final missing = FontRegistry.instance.missing(item.doc);
      if (missing.isNotEmpty) {
        final names = missing.map((f) => '"$f"').join(', ');
        out.add(
          Notice(
            NoteKind.warning,
            "This phone doesn't have the font $names, so a stand-in is used. Add the font under Fonts to fix it.",
          ),
        );
      }
      if (item.doc.fit == DocFit.crop && hasFramePicture(item.doc)) {
        out.add(
          Notice(
            NoteKind.warning,
            "Photos are cropped to this layout's shape (${ratioText(item.doc.ratio)}), so taller or wider photos lose their edges.",
            actionLabel: 'Fit every photo shape',
            action: () => fitEveryShape(item),
          ),
        );
      }
    }
    if (!storageOk) {
      out.add(
        Notice(
          NoteKind.warning,
          "Saved layouts can't be read on this $deviceNoun, so layouts you make or import may be gone when the app closes.",
        ),
      );
    }
    if (!batchOk) {
      out.add(
        Notice(
          NoteKind.warning,
          "Photos can't be kept on this $deviceNoun, so they will be gone when the app closes.",
        ),
      );
    }
    if (!editingAvailable && _developerReady == null) {
      out.add(
        Notice(
          NoteKind.info,
          "Photo editing isn't available on this $deviceNoun.",
        ),
      );
    }
    return out;
  }

  // ---------- layouts ----------

  /// Adds a layout made or imported on this phone and stores it.
  Future<LayoutItem> addLayout(LayoutDoc doc) async {
    await _store(doc);
    final item = LayoutItem(doc, false, await prepareLayout(doc));
    layouts.add(item);
    _changed();
    return item;
  }

  /// Office layouts are never changed: a copy is made first.
  Future<LayoutItem> editableCopy(LayoutItem item) async {
    if (!item.builtin) return item;
    final copy = item.doc.clone()
      ..id = uid('L')
      ..name = '${item.doc.name} (copy)'
      ..created = DateTime.now().millisecondsSinceEpoch;
    copy.updated = copy.created;
    final added = await addLayout(copy);
    await selectLayout(added.id);
    return added;
  }

  /// Stores [item]'s doc after a change and redraws its pictures.
  Future<void> layoutChanged(LayoutItem item, {bool repaint = true}) async {
    await _store(item.doc);
    if (repaint) {
      final old = item.prep;
      item.prep = await prepareLayout(item.doc);
      old.dispose();
    }
    item.revision++;
    _changed();
  }

  /// app.js fitEveryShape(): cuts full-frame pictures into edge parts.
  Future<void> fitEveryShape(LayoutItem item) async {
    final target = await editableCopy(item);
    final doc = target.doc;
    final result = await fitAnyShape(doc, target.prep, frameHeight(doc));
    if (result.failed != null) {
      layoutNotes = [
        Notice(
          NoteKind.error,
          "\"${result.failed!.name}\" has no see-through middle, so it can't be cut into edge parts. Photos stay cropped to its shape.",
        ),
      ];
      _changed();
      return;
    }
    doc.fit = DocFit.keep;
    cleanGroups(doc); // the cut parts keep their own edges, outside any group
    pruneAssets(doc);
    await layoutChanged(target);
    layoutNotes = [
      const Notice(
        NoteKind.info,
        "Done. The layout is now pinned to the photo's edges, so every photo keeps its full size and shape.",
      ),
    ];
    await selectLayout(target.id);
  }

  /// "New layout": an empty layout, stored and selected.
  Future<LayoutItem> newLayout() async {
    final item = await addLayout(LayoutDoc.blank('New layout'));
    await selectLayout(item.id);
    return item;
  }

  /// "Import a layout file".
  Future<void> importLayoutFile() async =>
      importFiles(await picker.pickFiles(extensions: ['json']));

  /// "Use a picture": a PNG, JPG or WebP becomes a layout.
  Future<void> usePicture() async => importFiles(
    await picker.pickFiles(extensions: ['png', 'jpg', 'jpeg', 'webp']),
  );

  /// app.js importFiles(): layout files and pictures become layouts.
  Future<void> importFiles(List<PickedPhoto> files) async {
    if (files.isEmpty) return;
    final notes = <Notice>[];
    LayoutItem? last;
    for (final f in files) {
      try {
        LayoutDoc doc;
        if (isLayoutFileName(f.name)) {
          doc = readLayoutBytes(await f.readBytes());
          await adoptDocFonts(doc, fontStore, convert: convertFont);
        } else if (isPictureFileName(f.name)) {
          final (d, n) = await layoutFromPicture(f.name, await f.readBytes());
          doc = d;
          notes.addAll(n);
        } else {
          throw const ImportProblem(
            'use a layout file (.json) or a PNG, JPG or WebP picture.',
          );
        }
        last = await addLayout(doc);
      } catch (e) {
        final text = e is ImportProblem
            ? e.message
            : "this file couldn't be read.";
        notes.add(Notice(NoteKind.error, '${f.name}: $text'));
      }
    }
    if (last != null) {
      notes.insert(
        0,
        Notice(
          NoteKind.info,
          'Added "${last.doc.name}". Use Edit layout to adjust it.',
        ),
      );
    }
    layoutNotes = notes;
    if (last != null) {
      await selectLayout(last.id);
    } else {
      _changed();
    }
  }

  Future<LayoutItem> duplicateLayout(LayoutItem item) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final copy = item.doc.clone()
      ..id = uid('L')
      ..name = '${item.doc.name} (copy)'
      ..created = now
      ..updated = now;
    final added = await addLayout(copy);
    await selectLayout(added.id);
    return added;
  }

  /// Renames a layout (an office layout gets a copy first). An empty name keeps the old one.
  Future<void> renameLayout(LayoutItem item, String name) async {
    final clean = name.replaceAll(RegExp(r'[\u0000-\u001f]'), '').trim();
    if (clean.isEmpty || clean == item.doc.name) return;
    final target = await editableCopy(item);
    target.doc.name = clean.length > 80 ? clean.substring(0, 80) : clean;
    await layoutChanged(target, repaint: false);
  }

  /// Writes `<name>.layout.json` with the fonts it uses and opens the share sheet.
  Future<void> exportLayout(LayoutItem item) async {
    final doc = item.doc.clone()
      ..fonts = FontRegistry.instance.embedFor(item.doc);
    final json = jsonEncode(writeLayout(doc, envelope: true));
    final name = '${safeFileName(doc.name)}.layout.json';
    final bytes = Uint8List.fromList(utf8.encode(json));
    if (!sharer.needsCopies) {
      await sharer.exportFile(name, bytes);
      return;
    }
    await temp.clear('export');
    final path = await temp.write('export', name, bytes);
    await sharer.shareFiles([path]);
  }

  /// Removes a layout made on this phone (office layouts stay).
  Future<void> removeLayout(LayoutItem item) async {
    if (item.builtin) return;
    try {
      await layoutStore.remove(item.id);
    } catch (e) {
      debugPrint('Could not delete the saved layout: $e');
    }
    layouts.remove(item);
    item.prep.dispose();
    layoutNotes = [];
    if (selectedId == item.id) {
      await selectLayout(layouts.isEmpty ? '' : layouts.first.id);
      if (layouts.isEmpty) selectedId = null;
    }
    _changed();
  }

  // ---------- saving ----------

  ExportSettings get exportSettings => ExportSettings(
    format: settings.format,
    quality: settings.quality,
    suffix: settings.suffix,
  );

  String get outputExt => settings.format == OutputFormat.png ? 'png' : 'jpg';

  /// What a photo is saved as: "IMG_1_PIO.jpg".
  String outputName(PhotoItem p) =>
      '${outputStem(p.name, settings.suffix)}.$outputExt';

  /// Renders [p] with its own settings; exactly as before when editing is
  /// off or the settings are neutral.
  Future<RenderedPhoto> _render(
    PhotoItem p,
    Uint8List bytes,
    LayoutItem item,
  ) async {
    final s = developer == null ? null : settingsFor(p);
    if (s == null || s.isNeutral) {
      return exporter.render(bytes, item.doc, item.prep, exportSettings);
    }
    // A clone of the cached maps, so the exporter does not compute them
    // again; ours to free, so removing the photo meanwhile is safe.
    final auto = await autoMapsFor(p);
    try {
      return await exporter.render(
        bytes,
        item.doc,
        item.prep,
        exportSettings,
        edit: s,
        profile: profileFor(s),
        auto: auto,
      );
    } finally {
      auto?.dispose();
    }
  }

  Future<void> saveAll() async {
    final item = current;
    if (item == null || saving) return;
    await whenIdle();
    await _developerReady; // edits are not dropped while the developer loads
    final list = readyPhotos;
    if (list.isEmpty) return;
    final j = job = ExportJob(list.length);
    message = '';
    _changed();
    final used = <String>{};
    final paths = <String>[];
    var result = '';
    var started = false;
    try {
      // A computer asks for its folder here; cancelling the dialog starts nothing.
      if (!await saver.beginBatch(list.length)) {
        job = null;
        _changed();
        return;
      }
      started = true;
      if (sharer.needsCopies) await temp.clear('saved');
      String? stopped;
      for (
        var i = 0;
        i < list.length && !j.cancelRequested && stopped == null;
        i++
      ) {
        final p = list[i];
        j
          ..current = i + 1
          ..currentName = p.name;
        _changed();
        try {
          final bytes = await p.source.readBytes();
          final out = await _render(p, bytes, item);
          final name = uniqueName(
            outputStem(p.name, settings.suffix),
            out.ext,
            used,
          );
          if (sharer.needsCopies) {
            paths.add(await temp.write('saved', name, out.bytes));
          }
          final where = await saver.saveImage(out.bytes, name);
          if (where != null && !sharer.needsCopies) paths.add(where);
          j
            ..saved += 1
            ..bytes += out.bytes.length;
        } catch (e) {
          if (e is GalleryAccessException) rethrow;
          if (e is SaveStoppedException) {
            stopped = e.message;
          } else if (isMemoryFailure(e)) {
            stopped = 'The computer ran out of memory, so saving stopped here.';
          } else {
            debugPrint('Could not save ${p.name}: $e');
            j.failed.add(p.name);
          }
        }
        if (stopped == null) j.done = i + 1;
        _changed();
      }
      await saver.endBatch(keep: !j.cancelRequested);
      started = false;
      if (j.cancelRequested) {
        result = saver.cancelledLine(j.saved);
      } else if (j.saved == 0 && stopped == null) {
        result = 'Nothing was saved. None of the photos could be processed.';
      } else if (j.saved == 0) {
        result = 'Nothing was saved. $stopped';
      } else {
        result = saver.resultLine(j.saved, formatBytes(j.bytes));
        if (stopped != null) {
          result +=
              ' $stopped ${plural(list.length - j.saved - j.failed.length, 'photo was', 'photos were')} not saved.';
        }
      }
      if (j.failed.isNotEmpty) {
        result += " Couldn't process ${failedList(j.failed)}.";
      }
    } catch (e) {
      result = 'Saving stopped: $e';
      if (started) {
        try {
          await saver.endBatch(keep: false);
        } catch (_) {}
      }
    }
    developer?.clearCache();
    lastSaved = paths;
    job = null;
    message = result;
    _changed();
  }

  void cancelSave() {
    final j = job;
    if (j == null || j.cancelRequested) return;
    j.cancelRequested = true;
    _changed();
  }

  Future<void> shareLast() => sharer.shareFiles(lastSaved);

  /// Renders one photo at full size.
  Future<(String name, Uint8List bytes)> _renderOne(PhotoItem p) async {
    final item = current;
    if (item == null) throw StateError('Choose a layout first.');
    await _developerReady;
    final RenderedPhoto out;
    try {
      out = await _render(p, await p.source.readBytes(), item);
    } finally {
      developer?.clearCache();
    }
    return ('${outputStem(p.name, settings.suffix)}.${out.ext}', out.bytes);
  }

  /// The viewer's "Save this photo". Returns the line to show (null when the
  /// person cancelled the save dialog).
  Future<String?> saveOne(PhotoItem p) async {
    final (name, bytes) = await _renderOne(p);
    try {
      await saver.saveImage(bytes, name);
    } on SaveCancelledException {
      return null;
    }
    return saver.savedOneLine(name);
  }

  /// The viewer's "Share" (phone) or "Show in folder" (Windows).
  Future<void> shareOne(PhotoItem p) async {
    final (name, bytes) = await _renderOne(p);
    if (!sharer.needsCopies) {
      try {
        final where = await saver.saveImage(bytes, name);
        if (where != null) await sharer.shareFiles([where]);
      } on SaveCancelledException {
        // The person backed out of the dialog.
      }
      return;
    }
    await temp.clear('single');
    final path = await temp.write('single', name, bytes);
    await sharer.shareFiles([path]);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final p in photos) {
      _release(p);
    }
    for (final l in layouts) {
      l.prep.dispose();
    }
    super.dispose();
  }
}

/// True for an allocation failure ("out of memory", "Array buffer allocation failed").
bool isMemoryFailure(Object e) {
  if (e is OutOfMemoryError) return true;
  final t = e.toString().toLowerCase();
  return t.contains('out of memory') ||
      t.contains('allocation failed') ||
      t.contains('invalid array length');
}

/// Bytes of a photo, for the viewer and single saves.
Future<Uint8List> photoBytes(PhotoItem p) => p.source.readBytes();
