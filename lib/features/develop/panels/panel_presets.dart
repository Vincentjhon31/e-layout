import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../../core/presets/preset.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/toast.dart';
import '../../home/preset_picker.dart';
import '../photo_editor_controller.dart';

const double _kCardWidth = 80;
const double _kThumb = 72;

/// Presets: a row of cards, each this photo with the preset on it. A tap puts
/// the preset on this photo only. The Import card comes first, then your own
/// and imported presets, then the built-in looks.
class PresetsPanel extends StatefulWidget {
  const PresetsPanel({super.key, required this.controller});
  final PhotoEditorController controller;

  @override
  State<PresetsPanel> createState() => _PresetsPanelState();
}

class _PresetsPanelState extends State<PresetsPanel> {
  PresetThumbs? _thumbs;
  int? _thumbsFor;
  bool _importing = false;

  PhotoEditorController get c => widget.controller;

  @override
  void dispose() {
    _thumbs?.dispose();
    super.dispose();
  }

  /// The thumbnails of the open photo; made again when another photo opens.
  PresetThumbs _thumbsOf(int photoId) {
    if (_thumbs == null || _thumbsFor != photoId) {
      final old = _thumbs;
      if (old != null) {
        // After the cards that show them are gone.
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _thumbs = PresetThumbs(c.home, photoId: photoId);
      _thumbsFor = photoId;
    }
    return _thumbs!;
  }

  Future<void> _apply(Preset p) async {
    await c.applyPreset(p);
    if (mounted) {
      showToast(
        context,
        '"${p.name}" is on this photo.',
        icon: CupertinoIcons.checkmark_alt,
      );
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final files = await c.home.picker.pickFiles(extensions: kPresetFileTypes);
      if (files.isEmpty) return; // cancelled
      final line = await c.home.importPresets(files);
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
        final presets = c.home.presets;
        final builtin = c.home.builtinPresets;
        final mine = presets.where((p) => p.kind == PresetKind.user);
        final imported = presets.where((p) => p.kind == PresetKind.imported);
        final thumbs = _thumbsOf(c.photo.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              key: const ValueKey('preset-row'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Group(
                    title: ' ',
                    children: [
                      _Card(
                        key: const ValueKey('preset-import'),
                        label: 'Import',
                        onPressed: _importing ? null : _import,
                        thumb: Icon(
                          CupertinoIcons.square_arrow_down,
                          size: 26,
                          color: colors.accent,
                        ),
                      ),
                    ],
                  ),
                  if (presets.isNotEmpty)
                    _Group(
                      title: 'Your presets',
                      children: [
                        for (final p in [...mine, ...imported])
                          _Card(
                            key: ValueKey('preset-${p.id}'),
                            label: p.name,
                            onPressed: () => _apply(p),
                            thumb: _Thumb(future: thumbs.of(p)),
                          ),
                      ],
                    ),
                  if (builtin.isNotEmpty)
                    _Group(
                      title: 'Built-in',
                      children: [
                        for (final p in builtin)
                          _Card(
                            key: ValueKey('preset-${p.id}'),
                            label: p.name,
                            onPressed: () => _apply(p),
                            thumb: _Thumb(future: thumbs.of(p)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (presets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'No presets of your own yet.',
                  textAlign: TextAlign.start,
                  style: AppText.subhead.copyWith(color: colors.secondary),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A captioned run of cards.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: AppText.caption.copyWith(color: colors.secondary),
            ),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.label,
    required this.thumb,
    required this.onPressed,
  });

  final String label;
  final Widget thumb;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      child: SizedBox(
        width: _kCardWidth,
        child: Column(
          children: [
            Container(
              width: _kThumb,
              height: _kThumb,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.isDark ? colors.raised : colors.page,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumb,
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: colors.text),
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
  Widget build(BuildContext context) => FutureBuilder<ui.Image?>(
    future: future,
    builder: (context, snap) {
      final img = snap.data;
      if (img == null) return const SizedBox.shrink();
      return SizedBox.expand(
        child: RawImage(
          image: img,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      );
    },
  );
}
