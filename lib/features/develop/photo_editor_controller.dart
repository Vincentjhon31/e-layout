import 'package:flutter/foundation.dart';

import '../../core/develop/batch_look.dart';
import '../../core/develop/photo_developer.dart';
import '../../core/develop/settings.dart';
import '../../core/presets/preset.dart';
import '../home/home_controller.dart';

/// The photo editor's tools, in the order of the tool strip.
enum ToolPanel { presets, light, colour, effects, detail }

/// Undo keeps at most this many looks.
const int kEditorHistory = 100;

/// The photo editor: which photo is open, the change being dragged, and the
/// undo history. Every change goes to [HomeController.setLook], so Home's
/// grid and the saved photos follow at once.
class PhotoEditorController extends ChangeNotifier {
  PhotoEditorController({
    required this.home,
    required int photoId,
    required this.developer,
  }) : _openId = photoId {
    home.addListener(_homeChanged);
  }

  final HomeController home;
  final PhotoDeveloper developer;
  int _openId;
  bool _disposed = false;

  ToolPanel? _panel;
  bool _comparing = false;
  bool _showLayout = true;

  // The look before the drag, and the look with the dragged values.
  BatchLook? _dragBase;
  BatchLook? _draft;

  final List<BatchLook> _undo = [];
  final List<BatchLook> _redo = [];

  /// The photos the filmstrip shows.
  List<PhotoItem> get photos => home.readyPhotos;

  /// The open photo (the first one if it is gone).
  PhotoItem get photo {
    final list = home.photos;
    for (final p in list) {
      if (p.id == _openId) return p;
    }
    final ready = photos;
    return ready.isNotEmpty ? ready.first : list.first;
  }

  /// Where [photo] is in [photos] (0 when it is not ready).
  int get index {
    final i = photos.indexWhere((p) => p.id == _openId);
    return i < 0 ? 0 : i;
  }

  BatchLook get _look => _draft ?? home.look;

  /// This photo's settings, with the value being dragged.
  EditSettings get settings => _look.settingsFor(photo.id);

  /// True between [beginChange] and [endChange].
  bool get changing => _dragBase != null;

  ToolPanel? get panel => _panel;
  bool get comparing => _comparing;
  bool get showLayout => _showLayout;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// True when this photo has changes of its own.
  bool get hasOwnChanges => _look.hasOwnChanges(photo.id);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _homeChanged() => _changed();

  // ---------- slider gestures ----------

  void beginChange() {
    _dragBase ??= home.look;
  }

  /// Shows [v] for [s] without keeping it yet.
  void preview(Setting s, double v) {
    beginChange();
    _draft = _look.withPhotoPatch(
      photo.id,
      SettingsPatch(values: {s: s.clamp(v)}),
    );
    _changed();
  }

  /// Keeps the dragged values as one undo step.
  Future<void> endChange() async {
    final base = _dragBase, draft = _draft;
    _dragBase = null;
    _draft = null;
    if (base == null || draft == null || identical(base, draft)) {
      _changed();
      return;
    }
    _remember(base);
    await home.setLook(draft);
  }

  // ---------- one-step changes ----------

  Future<void> _commit(BatchLook next) async {
    if (changing) await endChange();
    _remember(home.look);
    await home.setLook(next);
  }

  void _remember(BatchLook look) {
    _undo.add(look);
    if (_undo.length > kEditorHistory) _undo.removeAt(0);
    _redo.clear();
  }

  Future<void> _patch(SettingsPatch p) =>
      _commit(home.look.withPhotoPatch(photo.id, p));

  Future<void> setValue(Setting s, double v) =>
      _patch(SettingsPatch(values: {s: s.clamp(v)}));

  Future<void> setCurve(CurveChannel c, List<CurvePoint> pts) =>
      _patch(SettingsPatch(curves: {c: pts}));

  Future<void> setGrayscale(bool on) => _patch(SettingsPatch(grayscale: on));

  /// The colour profile's strength, 0 to 2 (1 is 100 %).
  Future<void> setProfileAmount(double a) {
    final p = settings.profile;
    return _patch(
      SettingsPatch(profile: ProfileRef(p.id, p.name, a.clamp(0.0, 2.0))),
    );
  }

  /// Applies [p] to this photo only.
  Future<void> applyPreset(Preset p) => _patch(p.patch);

  /// Makes [groups] of this photo the shared look of every photo.
  Future<void> copyToAll(Set<ToolGroup> groups, {required bool keepSingle}) =>
      _commit(home.look.copyToAll(photo.id, groups, keepSingle: keepSingle));

  /// This photo follows the shared preset again.
  Future<void> resetPhoto() => _commit(home.look.resetPhoto(photo.id));

  /// Keeps this photo's settings as a preset of the person's own.
  Future<Preset> saveAsPreset(String name) => home.savePreset(name, settings);

  // ---------- history ----------

  Future<void> undo() async {
    if (changing) await endChange();
    if (_undo.isEmpty) return;
    _redo.add(home.look);
    await home.setLook(_undo.removeLast());
  }

  Future<void> redo() async {
    if (changing) await endChange();
    if (_redo.isEmpty) return;
    _undo.add(home.look);
    await home.setLook(_redo.removeLast());
  }

  // ---------- view ----------

  /// Opens photo number [index] of [photos]; the open panel stays.
  Future<void> showPhoto(int index) async {
    final list = photos;
    if (index < 0 || index >= list.length || list[index].id == _openId) return;
    if (changing) await endChange();
    _openId = list[index].id;
    _comparing = false;
    developer.clearCache();
    _changed();
  }

  void setPanel(ToolPanel? p) {
    if (p == _panel) return;
    _panel = p;
    _changed();
  }

  /// Shows the photo without its edits while [on].
  void setComparing(bool on) {
    if (on == _comparing) return;
    _comparing = on;
    _changed();
  }

  /// Shows or hides the layout over the photo.
  void toggleLayout() {
    _showLayout = !_showLayout;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    home.removeListener(_homeChanged);
    super.dispose();
  }
}
