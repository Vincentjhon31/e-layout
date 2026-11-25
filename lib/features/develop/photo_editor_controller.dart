import 'package:flutter/foundation.dart';

import '../../core/develop/batch_look.dart';
import '../../core/develop/masks.dart';
import '../../core/develop/photo_developer.dart';
import '../../core/develop/settings.dart';
import '../../core/presets/preset.dart';
import '../home/home_controller.dart';

/// The photo editor's tools, in the order of the tool strip.
enum ToolPanel { presets, light, colour, effects, detail, masks }

/// Undo keeps at most this many looks.
const int kEditorHistory = 100;

/// A mask's name is at most this long.
const int kMaxMaskName = 40;

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
  String? _maskId;
  int _component = 0;
  bool _showOverlay = false;
  double _brushSize = 0.05;
  double _brushFeather = 50;
  double _brushFlow = 100;
  bool _brushErase = false;

  // The look before the drag, and the look with the dragged values.
  BatchLook? _dragBase;
  BatchLook? _draft;

  final List<BatchLook> _undo = [];
  final List<BatchLook> _redo = [];

  /// The photos the filmstrip shows.
  List<PhotoItem> get photos => home.readyPhotos;

  // The last photo shown, for the moment between Home losing every photo
  // and the editor closing.
  PhotoItem? _last;

  /// The open photo (the first one if it is gone).
  PhotoItem get photo {
    final list = home.photos;
    for (final p in list) {
      if (p.id == _openId) return _last = p;
    }
    final ready = photos;
    if (ready.isNotEmpty) return _last = ready.first;
    if (list.isNotEmpty) return _last = list.first;
    return _last!;
  }

  /// True when Home has no photos left: the editor closes.
  bool get empty => home.photos.isEmpty;

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

  /// Drops the change being dragged: the look goes back to what it was
  /// (a pinch that took over a handle drag on the photo).
  void cancelChange() {
    if (_dragBase == null && _draft == null) return;
    _dragBase = null;
    _draft = null;
    _changed();
  }

  // ---------- one-step changes ----------

  /// Keeps the look [next] makes as one undo step. A drag still going is
  /// kept first, as its own step, so [next] builds on it.
  Future<void> _commit(BatchLook Function() next) async {
    if (changing) await endChange();
    _remember(home.look);
    await home.setLook(next());
  }

  void _remember(BatchLook look) {
    _undo.add(look);
    if (_undo.length > kEditorHistory) _undo.removeAt(0);
    _redo.clear();
  }

  Future<void> _patch(SettingsPatch Function() p) =>
      _commit(() => home.look.withPhotoPatch(photo.id, p()));

  Future<void> setValue(Setting s, double v) async {
    if (!changing && settings[s] == s.clamp(v)) return;
    await _patch(() => SettingsPatch(values: {s: s.clamp(v)}));
  }

  Future<void> setCurve(CurveChannel c, List<CurvePoint> pts) =>
      _patch(() => SettingsPatch(curves: {c: pts}));

  Future<void> setGrayscale(bool on) =>
      _patch(() => SettingsPatch(grayscale: on));

  /// The colour profile's strength, 0 to 2 (1 is 100 %).
  Future<void> setProfileAmount(double a) => _patch(() {
    final p = settings.profile;
    return SettingsPatch(profile: ProfileRef(p.id, p.name, a.clamp(0.0, 2.0)));
  });

  /// Applies [p] to this photo only.
  Future<void> applyPreset(Preset p) => _patch(() => p.patch);

  /// Makes [groups] of this photo the shared look of every photo.
  Future<void> copyToAll(Set<ToolGroup> groups, {required bool keepSingle}) =>
      _commit(
        () => home.look.copyToAll(photo.id, groups, keepSingle: keepSingle),
      );

  /// This photo follows the shared preset again.
  Future<void> resetPhoto() => _commit(() => home.look.resetPhoto(photo.id));

  /// Keeps this photo's settings as a preset of the person's own.
  Future<Preset> saveAsPreset(String name) => home.savePreset(name, settings);

  // ---------- masks ----------

  /// This photo's masks, with the change being dragged.
  List<Mask> get masks => settings.masks;

  /// The mask the panel shows, or null for the list (also when undo took
  /// the selected mask away).
  String? get selectedMaskId => selectedMask?.id;

  Mask? get selectedMask => _maskId == null ? null : _find(masks, _maskId!);

  /// The component of the selected mask that the Mask tab (and the
  /// canvas's handles) work on.
  int get selectedComponent {
    final n = selectedMask?.components.length ?? 0;
    return n == 0 ? 0 : _component.clamp(0, n - 1);
  }

  void selectComponent(int i) {
    if (i == _component) return;
    _component = i;
    _changed();
  }

  /// True when the canvas shows the selected mask's area in red.
  bool get showOverlay => _showOverlay;

  /// The brush for new strokes: radius as a fraction of the long edge,
  /// feather and flow 0 to 100, and whether it erases.
  double get brushSize => _brushSize;
  double get brushFeather => _brushFeather;
  double get brushFlow => _brushFlow;
  bool get brushErase => _brushErase;

  void selectMask(String? id) {
    if (id == _maskId) return;
    _maskId = id;
    _component = 0;
    _changed();
  }

  void setShowOverlay(bool on) {
    if (on == _showOverlay) return;
    _showOverlay = on;
    _changed();
  }

  void setBrush({double? size, double? feather, double? flow, bool? erase}) {
    if (size != null) _brushSize = size.clamp(0.005, 0.5).toDouble();
    if (feather != null) _brushFeather = feather.clamp(0.0, 100.0).toDouble();
    if (flow != null) _brushFlow = flow.clamp(0.0, 100.0).toDouble();
    if (erase != null) _brushErase = erase;
    _changed();
  }

  /// [look] with this photo's masks replaced by what [edit] makes of them.
  /// A list equal to the shared one leaves no override behind.
  BatchLook _withMasks(BatchLook look, List<Mask> Function(List<Mask>) edit) {
    final id = photo.id;
    final next = edit(look.settingsFor(id).masks);
    final shared = look.shared.masks ?? const <Mask>[];
    if (_sameMasks(next, shared)) {
      final own = look.photos[id];
      if (own == null || own.masks == null) return look;
      final rest = own
          .without({ToolGroup.masks})
          .over(SettingsPatch(lensBlur: own.lensBlur));
      return look.withoutPhoto(id).withPhotoPatch(id, rest);
    }
    return look.withPhotoPatch(id, SettingsPatch(masks: next));
  }

  static bool _sameMasks(List<Mask> a, List<Mask> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Mask? _find(List<Mask> list, String id) {
    for (final m in list) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<Mask> _map(List<Mask> list, String id, Mask Function(Mask) f) => [
    for (final m in list) m.id == id ? f(m) : m,
  ];

  static Mask _copy(
    Mask m, {
    String? name,
    List<MaskComponent>? components,
    Map<Setting, double>? adjust,
    bool? visible,
  }) => Mask(
    id: m.id,
    name: name ?? m.name,
    components: components ?? m.components,
    adjust: adjust ?? m.adjust,
    visible: visible ?? m.visible,
  );

  /// One undo step that changes mask [id], if it is there and [f] changes
  /// it (a drag still going is kept first, as its own step).
  Future<void> _editMask(String id, Mask Function(Mask) f) async {
    final cur = _find(masks, id);
    if (cur == null) return;
    if (!changing && f(cur) == cur) return;
    await _commit(() => _withMasks(home.look, (l) => _map(l, id, f)));
  }

  static String _newId(List<Mask> list) {
    var n = DateTime.now().microsecondsSinceEpoch;
    String id;
    do {
      id = 'm${(n++).toRadixString(36)}';
    } while (list.any((m) => m.id == id));
    return id;
  }

  static String _newName(List<Mask> list) {
    var k = 1;
    while (list.any((m) => m.name == 'Mask $k')) {
      k++;
    }
    return 'Mask $k';
  }

  /// Adds a mask made of [first] and selects it, as one step. A photo has
  /// at most [kMaxMasks]; more are refused.
  Future<void> addMask(MaskShape first) async {
    if (changing) await endChange();
    final list = masks;
    if (list.length >= kMaxMasks) return;
    final m = Mask(
      id: _newId(list),
      name: _newName(list),
      components: [MaskComponent(first)],
    );
    _maskId = m.id;
    _component = 0;
    await _commit(() => _withMasks(home.look, (l) => [...l, m]));
  }

  Future<void> deleteMask(String id) async {
    if (_find(masks, id) == null) return;
    if (_maskId == id) _maskId = null;
    await _commit(
      () => _withMasks(home.look, (l) => [...l.where((m) => m.id != id)]),
    );
  }

  /// Renames mask [id] (at most [kMaxMaskName] characters); a blank name
  /// keeps the old one.
  Future<void> renameMask(String id, String name) async {
    var n = name.trim();
    if (n.isEmpty) return;
    if (n.length > kMaxMaskName) n = n.substring(0, kMaxMaskName).trimRight();
    await _editMask(id, (m) => _copy(m, name: n));
  }

  Future<void> setMaskVisible(String id, bool visible) =>
      _editMask(id, (m) => _copy(m, visible: visible));

  /// Combines [shape] into mask [id] with [op] and selects it; at most
  /// [kMaxComponents].
  Future<void> addComponent(String id, MaskShape shape, MaskOp op) async {
    final m = _find(masks, id);
    if (m == null || m.components.length >= kMaxComponents) return;
    if (id == _maskId) _component = m.components.length;
    await _editMask(
      id,
      (m) => _copy(
        m,
        components: [
          ...m.components,
          MaskComponent(shape, op: op),
        ],
      ),
    );
  }

  static Mask _withShape(Mask m, int index, MaskShape shape) {
    if (index < 0 || index >= m.components.length) return m;
    final comps = [...m.components];
    comps[index] = MaskComponent(shape, op: comps[index].op);
    return _copy(m, components: comps);
  }

  /// Shows [shape] as component [index] of mask [id] without keeping it yet
  /// (a handle or slider drag; [endChange] keeps it as one step).
  void previewShape(String id, int index, MaskShape shape) {
    beginChange();
    _draft = _withMasks(
      _look,
      (l) => _map(l, id, (m) => _withShape(m, index, shape)),
    );
    _changed();
  }

  /// Keeps [shape] as component [index] of mask [id], as one step.
  Future<void> updateShape(String id, int index, MaskShape shape) =>
      _editMask(id, (m) => _withShape(m, index, shape));

  /// Removes component [index]; the last one stays (a mask needs a shape).
  Future<void> removeComponent(String id, int index) async {
    final m = _find(masks, id);
    if (m == null || m.components.length < 2) return;
    if (index < 0 || index >= m.components.length) return;
    if (id == _maskId && _component >= index && _component > 0) _component--;
    await _editMask(
      id,
      (m) => _copy(m, components: [...m.components]..removeAt(index)),
    );
  }

  static Mask _withValue(Mask m, Setting s, double v) {
    if (!kLocalSettings.contains(s)) return m;
    final adjust = {...m.adjust};
    final c = s.clamp(v);
    if (c == s.neutral) {
      adjust.remove(s);
    } else {
      adjust[s] = c;
    }
    return _copy(m, adjust: adjust);
  }

  /// Shows [v] for mask [id]'s local setting [s] without keeping it yet.
  void previewMaskValue(String id, Setting s, double v) {
    beginChange();
    _draft = _withMasks(_look, (l) => _map(l, id, (m) => _withValue(m, s, v)));
    _changed();
  }

  /// Keeps [v] for mask [id]'s local setting [s] as one step.
  Future<void> setMaskValue(String id, Setting s, double v) =>
      _editMask(id, (m) => _withValue(m, s, v));

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
    _maskId = null;
    _component = 0;
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
