import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../core/render/photo_geometry.dart';
import '../../ui/app_theme.dart';
import '../../ui/previews.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/toast.dart';
import '../develop/open_photo_editor.dart';
import '../home/home_controller.dart';

/// Long edge of the copy decoded for the viewer.
const int kViewerEdge = 2048;

/// Decodes [bytes] with its long edge at most [edge] pixels (upright).
Future<ui.Image> decodeScaled(Uint8List bytes, int edge) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final desc = await ui.ImageDescriptor.encoded(buffer);
    try {
      final s = math.min(1.0, edge / math.max(desc.width, desc.height));
      final codec = await desc.instantiateCodec(
          targetWidth: math.max(1, (desc.width * s).round()),
          targetHeight: math.max(1, (desc.height * s).round()));
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } finally {
      desc.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

/// Full-screen photo with its layout; swipe between photos, pinch to zoom.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.controller, required this.initialIndex});

  final HomeController controller;
  final int initialIndex;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final List<PhotoItem> _photos = widget.controller.readyPhotos;
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _bars = true;
  bool _zoomed = false;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await job();
      if (msg != null && mounted) showToast(context, msg, icon: CupertinoIcons.checkmark_alt);
    } catch (e) {
      if (mounted) showToast(context, "Couldn't save this photo: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final photo = _photos[_index];
    final layout = c.current;
    final g = photoGeometry(photo.width, photo.height, layout?.doc);
    const white = Color(0xFFFFFFFF);
    const dim = Color(0xB3FFFFFF);
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pages,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (context, i) => _ViewerPage(
                key: ValueKey(_photos[i].id),
                photo: _photos[i],
                layout: layout,
                onTap: () => setState(() => _bars = !_bars),
                onZoom: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
          ),
          if (_bars)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: const Color(0x99000000),
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        AppIconButton(
                          icon: CupertinoIcons.xmark,
                          label: 'Close',
                          color: white,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(photo.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.headline.copyWith(color: white)),
                              Text('${_index + 1} of ${_photos.length}',
                                  style: AppText.caption.copyWith(color: dim, fontFeatures: AppText.tabular)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_bars)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: const Color(0x99000000),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Saves as ${c.outputName(photo)}, ${g.w} x ${g.h} px',
                            textAlign: TextAlign.center,
                            style: AppText.subhead.copyWith(color: dim, fontFeatures: AppText.tabular)),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          // With Edit on a phone, Edit and Share stack their words under the icon
                          // so "Save this photo" keeps its whole label.
                          builder: (context, box) {
                            final compact = c.editingAvailable && box.maxWidth < 480;
                            final gap = SizedBox(width: compact ? 8 : 10);
                            return Row(
                              children: [
                                Expanded(
                                  child: AppButton(
                                    label: _busy ? 'Working' : 'Save this photo',
                                    onPressed: _busy || layout == null ? null : () => _run(() => c.saveOne(photo)),
                                  ),
                                ),
                                if (c.editingAvailable) ...[
                                  gap,
                                  _ShareButton(
                                    label: 'Edit',
                                    icon: CupertinoIcons.slider_horizontal_3,
                                    compact: compact,
                                    onPressed: _busy ? null : () => openPhotoEditor(context, c, photo, replace: true),
                                  ),
                                ],
                                if (c.sharer.buttonLabel != null) ...[
                                  gap,
                                  _ShareButton(
                                    label: c.sharer.buttonLabel!,
                                    icon: c.sharer.needsCopies ? CupertinoIcons.share : CupertinoIcons.folder,
                                    compact: compact,
                                    onPressed: _busy || layout == null
                                        ? null
                                        : () => _run(() async {
                                              await c.shareOne(photo);
                                              return null;
                                            }),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.label, required this.icon, this.onPressed, this.compact = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// The label under the icon, in a 60 pt wide button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFFFFFFF);
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        child: Container(
          height: AppMetrics.buttonHeight,
          width: compact ? 60 : null,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 18),
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(AppMetrics.buttonRadius),
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20, color: white),
                    const SizedBox(height: 2),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.captionStrong.copyWith(color: white, height: 1.1)),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: white),
                    const SizedBox(width: 8),
                    Text(label, style: AppText.button.copyWith(color: white)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({super.key, required this.photo, required this.layout, required this.onTap, required this.onZoom});

  final PhotoItem photo;
  final LayoutItem? layout;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final TransformationController _t = TransformationController();
  ui.Image? _image;
  bool _failed = false;
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    _t.addListener(() => widget.onZoom(_t.value.getMaxScaleOnAxis() > 1.01));
    _load();
  }

  Future<void> _load() async {
    try {
      final img = await decodeScaled(await photoBytes(widget.photo), kViewerEdge);
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() => _image = img);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_t.value.getMaxScaleOnAxis() > 1.01) {
      _t.value = Matrix4.identity();
    } else {
      final p = _doubleTap?.localPosition ?? Offset.zero;
      const s = 2.5;
      _t.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image ?? widget.photo.preview;
    if (_failed && img == null) {
      return Center(
        child: Text("Can't open this photo.",
            style: AppText.body.copyWith(color: const Color(0xFFFFFFFF))),
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _t,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: img == null
              ? const Center(child: CupertinoActivityIndicator(color: Color(0xFFFFFFFF)))
              : CustomPaint(
                  painter: CompositePainter(
                    image: img,
                    photoWidth: widget.photo.width,
                    photoHeight: widget.photo.height,
                    doc: widget.layout?.doc,
                    prep: widget.layout?.prep,
                    revision: widget.layout?.revision ?? 0,
                  ),
                ),
        ),
      ),
    );
  }
}
