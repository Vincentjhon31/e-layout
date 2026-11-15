import '../../platform/device_noun.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/analysis/frame_split.dart';
import '../../core/export/photo_exporter.dart';
import '../../core/fonts/font_registry.dart';
import '../../core/model/layout_codec.dart';
import '../../core/model/layout_doc.dart';
import '../../core/model/layout_ops.dart';
import '../../core/render/layout_prep.dart';
import '../../core/render/photo_geometry.dart';
import '../../core/store/bundled_layouts.dart';
import '../../core/store/font_store.dart';
import '../../core/store/layout_store.dart';
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
  PhotoItem(this.id, this.source) : name = source.name;
  final int id;
  final PickedPhoto source;
  final String name;
  PhotoStatus status = PhotoStatus.loading;
  int width = 0, height = 0;
  ui.Image? preview;
  String? error;
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
    (1.0, '1:1'), (4 / 5, '4:5'), (3 / 4, '3:4'), (2 / 3, '2:3'), (3 / 2, '3:2'), //
    (4 / 3, '4:3'), (16 / 9, '16:9'), (9 / 16, '9:16'), (math.sqrt2, 'A4, 1.41:1'),
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
  })  : exporter = exporter ?? PhotoExporter(),
        bundled = bundled ?? loadBundledLayouts,
        fontStore = fontStore ?? createFontStore();

  final LayoutStore layoutStore;
  final SettingsStore settingsStore;
  final PhotoPicker picker;
  final GallerySaver saver;
  final FileSharer sharer;
  final TempFiles temp;
  final PhotoExporter exporter;
  final Future<List<LayoutDoc>> Function() bundled;

  /// Fonts the person added, kept on this phone.
  final FontStore fontStore;

  /// Turns WOFF font bytes into TTF (null when it can't).
  final FontConverter? convertFont;

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
  bool _disposed = false;

  LayoutItem? get current {
    for (final l in layouts) {
      if (l.id == selectedId) return l;
    }
    return null;
  }

  List<PhotoItem> get readyPhotos => [for (final p in photos) if (p.status == PhotoStatus.ready) p];
  int get loadingCount => photos.where((p) => p.status == PhotoStatus.loading).length;
  int get errorCount => photos.where((p) => p.status == PhotoStatus.error).length;
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
    selectedId = remembered ? settings.layoutId : (list.isEmpty ? null : list.first.id);
    ready = true;
    _changed();
  }

  /// Registers every font kept on this phone (app.js loadStoredFonts).
  Future<void> loadStoredFonts() async {
    try {
      for (final f in await fontStore.loadAll()) {
        try {
          await FontRegistry.instance
              .register(f.family, f.weight, f.style, f.bytes, variable: f.variable, source: f.source);
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

  Future<void> addPhotos(List<PickedPhoto> picked) async {
    final known = {for (final p in photos) p.source.key};
    final fresh = <PickedPhoto>[];
    for (final f in picked) {
      if (known.add(f.key)) fresh.add(f);
    }
    fresh.sort((a, b) => naturalCompare(a.name, b.name));
    for (final f in fresh) {
      final item = PhotoItem(_nextId++, f);
      photos.add(item);
      _queue = (_queue ?? Future<void>.value()).then((_) => _loadPreview(item)).catchError((Object e) {
        debugPrint('Preview failed: $e');
      });
    }
    message = '';
    _changed();
  }

  /// Completes when every queued preview has loaded.
  Future<void> whenIdle() async {
    Future<void>? tail;
    do {
      tail = _queue;
      if (tail == null) return;
      await tail;
    } while (!identical(tail, _queue));
  }

  Future<void> _loadPreview(PhotoItem p) async {
    if (!photos.contains(p) || _disposed) return;
    try {
      final bytes = await p.source.readBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? desc;
      try {
        desc = await ui.ImageDescriptor.encoded(buffer);
        final w = desc.width, h = desc.height;
        final s = math.min(1.0, kPreviewEdge / math.max(w, h));
        final codec = await desc.instantiateCodec(
            targetWidth: math.max(1, (w * s).round()), targetHeight: math.max(1, (h * s).round()));
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
  }

  void removePhoto(int id) {
    final i = photos.indexWhere((p) => p.id == id);
    if (i < 0 || saving) return;
    photos[i].preview?.dispose();
    photos.removeAt(i);
    message = '';
    _changed();
  }

  void clearPhotos() {
    if (saving) return;
    for (final p in photos) {
      p.preview?.dispose();
    }
    photos = [];
    message = '';
    _changed();
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
          ? softPictures(item.doc, item.prep, widest, kSoftScale).where((s) => s.natural >= 60).toList()
          : <SoftPicture>[];
      if (soft.length == 1) {
        final s = soft.first;
        out.add(Notice(NoteKind.warning,
            '"${s.name}" is ${s.natural} px wide but gets stretched to ${s.shown} px on your largest photo, so it will look soft. Replace it with a bigger picture in the editor.'));
      } else if (soft.length > 1) {
        final list = soft.take(4).map((s) => '"${s.name}" (${s.natural} to ${s.shown} px)').join(', ');
        final more = soft.length > 4 ? ' and ${soft.length - 4} more' : '';
        out.add(Notice(NoteKind.warning,
            'Some pictures get stretched on your largest photo and will look soft: $list$more. Use a bigger original picture for a sharp result.'));
      }
      final missing = FontRegistry.instance.missing(item.doc);
      if (missing.isNotEmpty) {
        final names = missing.map((f) => '"$f"').join(', ');
        out.add(Notice(NoteKind.warning,
            "This phone doesn't have the font $names, so a stand-in is used. Add the font under Fonts to fix it."));
      }
      if (item.doc.fit == DocFit.crop && hasFramePicture(item.doc)) {
        out.add(Notice(
          NoteKind.warning,
          "Photos are cropped to this layout's shape (${ratioText(item.doc.ratio)}), so taller or wider photos lose their edges.",
          actionLabel: 'Fit every photo shape',
          action: () => fitEveryShape(item),
        ));
      }
    }
    if (!storageOk) {
      out.add(Notice(NoteKind.warning,
          "Saved layouts can't be read on this $deviceNoun, so layouts you make or import may be gone when the app closes."));
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
        Notice(NoteKind.error,
            "\"${result.failed!.name}\" has no see-through middle, so it can't be cut into edge parts. Photos stay cropped to its shape."),
      ];
      _changed();
      return;
    }
    doc.fit = DocFit.keep;
    cleanGroups(doc); // the cut parts keep their own edges, outside any group
    pruneAssets(doc);
    await layoutChanged(target);
    layoutNotes = [
      const Notice(NoteKind.info,
          "Done. The layout is now pinned to the photo's edges, so every photo keeps its full size and shape."),
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
  Future<void> importLayoutFile() async => importFiles(await picker.pickFiles(extensions: ['json']));

  /// "Use a picture": a PNG, JPG or WebP becomes a layout.
  Future<void> usePicture() async =>
      importFiles(await picker.pickFiles(extensions: ['png', 'jpg', 'jpeg', 'webp']));

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
          throw const ImportProblem('use a layout file (.json) or a PNG, JPG or WebP picture.');
        }
        last = await addLayout(doc);
      } catch (e) {
        final text = e is ImportProblem ? e.message : "this file couldn't be read.";
        notes.add(Notice(NoteKind.error, '${f.name}: $text'));
      }
    }
    if (last != null) {
      notes.insert(0, Notice(NoteKind.info, 'Added "${last.doc.name}". Use Edit layout to adjust it.'));
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
    final doc = item.doc.clone()..fonts = FontRegistry.instance.embedFor(item.doc);
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

  ExportSettings get exportSettings =>
      ExportSettings(format: settings.format, quality: settings.quality, suffix: settings.suffix);

  String get outputExt => settings.format == OutputFormat.png ? 'png' : 'jpg';

  /// What a photo is saved as: "IMG_1_PIO.jpg".
  String outputName(PhotoItem p) => '${outputStem(p.name, settings.suffix)}.$outputExt';

  Future<void> saveAll() async {
    final item = current;
    if (item == null || saving) return;
    await whenIdle();
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
      for (var i = 0; i < list.length && !j.cancelRequested && stopped == null; i++) {
        final p = list[i];
        j
          ..current = i + 1
          ..currentName = p.name;
        _changed();
        try {
          final bytes = await p.source.readBytes();
          final out = await exporter.render(bytes, item.doc, item.prep, exportSettings);
          final name = uniqueName(outputStem(p.name, settings.suffix), out.ext, used);
          if (sharer.needsCopies) paths.add(await temp.write('saved', name, out.bytes));
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
          result += ' $stopped ${plural(list.length - j.saved - j.failed.length, 'photo was', 'photos were')} not saved.';
        }
      }
      if (j.failed.isNotEmpty) result += " Couldn't process ${failedList(j.failed)}.";
    } catch (e) {
      result = 'Saving stopped: $e';
      if (started) {
        try {
          await saver.endBatch(keep: false);
        } catch (_) {}
      }
    }
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
    final out = await exporter.render(await p.source.readBytes(), item.doc, item.prep, exportSettings);
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
      p.preview?.dispose();
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
  return t.contains('out of memory') || t.contains('allocation failed') || t.contains('invalid array length');
}

/// Bytes of a photo, for the viewer and single saves.
Future<Uint8List> photoBytes(PhotoItem p) => p.source.readBytes();
