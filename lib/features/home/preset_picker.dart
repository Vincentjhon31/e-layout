import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../core/presets/preset.dart';
import '../../core/render/sample_scene.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import '../../ui/widgets/toast.dart';
import 'home_controller.dart';

const double kPresetThumb = 56;
const List<String> kPresetFileTypes = [
  'xmp',
  'dng',
  'lrtemplate',
  'zip',
  'json',
];
const String kNoPresetsText =
    'No presets yet. Import a Lightroom preset, or make one in the photo editor with Save as preset.';

/// Opens the preset picker as a bottom sheet.
Future<void> showPresetPicker(
  BuildContext context,
  HomeController controller,
) => showAppSheet<void>(context, (_) => PresetPicker(controller: controller));

/// Thumbnails for one picker: each preset applied to the first ready photo's
/// preview (or the sample scene), made one at a time when a row asks for it,
/// kept until the picker closes. With [photoId] they use that photo's preview
/// when it is ready.
class PresetThumbs {
  PresetThumbs(this.controller, {this.photoId});

  final HomeController controller;
  final int? photoId;
  ui.Image? _source;
  int _sourceWidth = 0;
  bool _ownSource = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  final Map<String, Future<ui.Image?>> _made = {};
  final List<ui.Image> _images = [];

  Future<void> _ensureSource() async {
    if (_source != null) return;
    final all = controller.photos;
    final first = [
      for (final p in all)
        if (p.id == photoId) p,
      ...all,
    ];
    for (final p in first) {
      final img = p.preview;
      if (p.status == PhotoStatus.ready && img != null && p.width > 0) {
        _source = img;
        _sourceWidth = p.width;
        return;
      }
    }
    _source = await sampleSceneImage(480, 480);
    _sourceWidth = 480;
    _ownSource = true;
    if (_disposed) _freeSource();
  }

  void _freeSource() {
    if (_ownSource) _source?.dispose();
    _source = null;
  }

  Future<ui.Image?> _run(Future<ui.Image?> Function() job) {
    final f = _queue.then((_) => _disposed ? null : job());
    _queue = f.then<void>((_) {}, onError: (_) {});
    return f;
  }

  /// The picture without a preset (the "None" row). Owned by this object.
  Future<ui.Image?> original() => _original ??= _run(() async {
    await _ensureSource();
    return _disposed ? null : _source;
  });
  Future<ui.Image?>? _original;

  /// [preset] applied. Made once, then reused. Null if it could not be made.
  Future<ui.Image?> of(Preset preset) => _made.putIfAbsent(
    preset.id,
    () => _run(() async {
      try {
        await _ensureSource();
        final src = _source;
        if (src == null || _disposed) return null;
        final out = await controller.developPreview(src, _sourceWidth, preset);
        if (out == null) return null;
        if (_disposed) {
          out.dispose();
          return null;
        }
        _images.add(out);
        return out;
      } catch (e) {
        debugPrint('Could not draw the ${preset.name} thumbnail: $e');
        return null;
      }
    }),
  );

  void dispose() {
    _disposed = true;
    for (final i in _images) {
      i.dispose();
    }
    _images.clear();
    _freeSource();
  }
}

/// "Presets": None, the person's own, the imported ones, and an import button.
class PresetPicker extends StatefulWidget {
  const PresetPicker({super.key, required this.controller});
  final HomeController controller;

  @override
  State<PresetPicker> createState() => _PresetPickerState();
}

sealed class _Item {
  const _Item();
}

class _Header extends _Item {
  const _Header(this.title);
  final String title;
}

class _Row extends _Item {
  const _Row(this.preset, {required this.first, required this.last});
  final Preset? preset; // null is the None row
  final bool first, last;
}

class _Note extends _Item {
  const _Note();
}

class _ImportButton extends _Item {
  const _ImportButton();
}

class _PresetPickerState extends State<PresetPicker> {
  late final PresetThumbs _thumbs = PresetThumbs(widget.controller);
  bool _importing = false;

  @override
  void dispose() {
    _thumbs.dispose();
    super.dispose();
  }

  HomeController get c => widget.controller;

  List<_Item> _items() {
    final mine = c.presets.where((p) => p.kind == PresetKind.user).toList();
    final imported = c.presets
        .where((p) => p.kind == PresetKind.imported)
        .toList();
    final out = <_Item>[const _Row(null, first: true, last: true)];
    void section(String title, List<Preset> list) {
      if (list.isEmpty) return;
      out.add(_Header(title));
      for (var i = 0; i < list.length; i++) {
        out.add(_Row(list[i], first: i == 0, last: i == list.length - 1));
      }
    }

    section('Your presets', mine);
    section('Imported', imported);
    if (c.presets.isEmpty) out.add(const _Note());
    out.add(const _ImportButton());
    return out;
  }

  bool _isCurrent(Preset? p) {
    final look = c.look;
    if (p == null) return look.sharedId == null && look.shared.isEmpty;
    return look.sharedId == p.id;
  }

  Future<void> _choose(Preset? p) async {
    Navigator.of(context).pop();
    await c.choosePresetForAll(p);
  }

  void _actions(Preset p) {
    showActionSheet(
      context,
      title: p.name,
      actions: [
        SheetAction('Share', () => unawaited(c.sharePreset(p))),
        SheetAction(
          'Delete',
          () => unawaited(c.removePreset(p)),
          destructive: true,
        ),
      ],
    );
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final files = await c.picker.pickFiles(extensions: kPresetFileTypes);
      if (files.isEmpty) return; // cancelled
      final line = await c.importPresets(files);
      if (mounted) showToast(context, line);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final items = _items();
        return SheetScaffold(
          title: 'Presets',
          scrollable: false,
          child: SizedBox(
            height: math.min(
              _height(items),
              MediaQuery.sizeOf(context).height * 0.9 - 80,
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                switch (item) {
                  case _Header(:final title):
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                      child: Text(
                        title.toUpperCase(),
                        style: AppText.section.copyWith(
                          color: colors.secondary,
                        ),
                      ),
                    );
                  case _Row(:final preset, :final first, :final last):
                    final row = _PresetRowTile(
                      key: ValueKey(preset?.id ?? 'none'),
                      preset: preset,
                      thumbs: _thumbs,
                      current: _isCurrent(preset),
                      first: first,
                      last: last,
                      onTap: () => _choose(preset),
                      onActions: preset == null ? null : () => _actions(preset),
                    );
                    return preset == null
                        ? row
                        : Dismissible(
                            key: ValueKey('swipe-${preset.id}'),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              _actions(preset);
                              return false;
                            },
                            background: const SizedBox.shrink(),
                            secondaryBackground: Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 20),
                                child: Icon(
                                  CupertinoIcons.ellipsis,
                                  color: colors.secondary,
                                ),
                              ),
                            ),
                            child: row,
                          );
                  case _Note():
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Text(
                        kNoPresetsText,
                        textAlign: TextAlign.center,
                        style: AppText.subhead.copyWith(
                          color: colors.secondary,
                        ),
                      ),
                    );
                  case _ImportButton():
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: AppButton.tinted(
                        label: 'Import a Lightroom preset',
                        icon: CupertinoIcons.square_arrow_down,
                        onPressed: _importing ? null : _import,
                      ),
                    );
                }
              },
            ),
          ),
        );
      },
    );
  }

  // The height the rows need, so the sheet is only as tall as its content.
  double _height(List<_Item> items) {
    var h = 0.0;
    for (final i in items) {
      h += switch (i) {
        _Header() => 46,
        _Row() => kPresetThumb + 16,
        _Note() => 86,
        _ImportButton() => 20 + AppMetrics.buttonHeight,
      };
    }
    return h;
  }
}

class _PresetRowTile extends StatelessWidget {
  const _PresetRowTile({
    super.key,
    required this.preset,
    required this.thumbs,
    required this.current,
    required this.first,
    required this.last,
    required this.onTap,
    required this.onActions,
  });

  final Preset? preset;
  final PresetThumbs thumbs;
  final bool current, first, last;
  final VoidCallback onTap;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final r = Radius.circular(AppMetrics.cardRadius);
    return Pressable(
      onPressed: onTap,
      onLongPress: onActions,
      pressedOpacity: 0.7,
      semanticLabel: preset?.name ?? 'None',
      child: Container(
        decoration: BoxDecoration(
          color: c.cardIn(context),
          borderRadius: BorderRadius.vertical(
            top: first ? r : Radius.zero,
            bottom: last ? r : Radius.zero,
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _Thumb(
                future: preset == null ? thumbs.original() : thumbs.of(preset!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: kPresetThumb + 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(
                          bottom: BorderSide(color: c.separator, width: 0.5),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          preset?.name ?? 'None',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body.copyWith(color: c.text),
                        ),
                      ),
                    ),
                    if (current)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 16),
                        child: Icon(
                          CupertinoIcons.checkmark,
                          key: Key('preset-check-${preset?.id ?? 'none'}'),
                          size: 20,
                          color: c.accent,
                        ),
                      )
                    else
                      const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.future});
  final Future<ui.Image?> future;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: kPresetThumb,
      height: kPresetThumb,
      decoration: BoxDecoration(
        color: c.isDark ? c.card : c.raised,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<ui.Image?>(
        future: future,
        builder: (context, snap) {
          final img = snap.data;
          if (img == null) return const SizedBox.shrink();
          return RawImage(
            image: img,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          );
        },
      ),
    );
  }
}
