import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../core/render/photo_geometry.dart';
import '../../ui/app_theme.dart';
import '../../ui/previews.dart';
import '../../ui/widgets/pressable.dart';
import 'home_controller.dart';

/// Columns for a grid [width] points wide: three on a phone, more as cells of
/// about 180 points fit on a wide window.
int gridColumns(double width) => math.max(3, (width + 8) ~/ 188);

/// Three columns of live previews. The first cell always adds photos.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({
    super.key,
    required this.photos,
    required this.layout,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
    this.enabled = true,
    this.hasOwnChanges,
  });

  final List<PhotoItem> photos;
  final LayoutItem? layout;
  final VoidCallback onAdd;
  final ValueChanged<PhotoItem> onOpen;
  final ValueChanged<PhotoItem> onRemove;
  final bool enabled;

  /// True for a photo with changes of its own (it gets a dot).
  final bool Function(PhotoItem photo)? hasOwnChanges;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.gutter),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) => SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridColumns(constraints.crossAxisExtent),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            if (i == 0) return _AddCell(onTap: enabled ? onAdd : null);
            final p = photos[i - 1];
            return _PhotoCell(
              key: ValueKey(p.id),
              photo: p,
              layout: layout,
              ownChanges: hasOwnChanges?.call(p) ?? false,
              onTap: enabled && p.status == PhotoStatus.ready
                  ? () => onOpen(p)
                  : null,
              onRemove: enabled ? () => onRemove(p) : null,
            );
          }, childCount: photos.length + 1),
        ),
      ),
    );
  }
}

class _AddCell extends StatelessWidget {
  const _AddCell({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Pressable(
      onPressed: onTap,
      semanticLabel: 'Add photos',
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.add, size: 26, color: c.accent),
              const SizedBox(height: 4),
              Text(
                'Add',
                style: AppText.captionStrong.copyWith(color: c.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    super.key,
    required this.photo,
    required this.layout,
    this.ownChanges = false,
    this.onTap,
    this.onRemove,
  });

  final PhotoItem photo;
  final LayoutItem? layout;
  final bool ownChanges;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget body;
    switch (photo.status) {
      case PhotoStatus.loading:
        body = const Center(child: CupertinoActivityIndicator());
      case PhotoStatus.error:
        body = Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 22,
                color: c.destructive,
              ),
              const SizedBox(height: 4),
              Text(
                photo.error ?? "Can't open this file.",
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(
                  color: c.secondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      case PhotoStatus.ready:
        body = CustomPaint(
          size: Size.infinite,
          painter: CompositePainter(
            image: photo.developed ?? photo.preview!,
            photoWidth: photo.width,
            photoHeight: photo.height,
            doc: layout?.doc,
            prep: layout?.prep,
            revision: layout?.revision ?? 0,
          ),
        );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Pressable(
          onPressed: onTap,
          pressedOpacity: 0.7,
          semanticLabel: 'Preview ${photo.name}',
          child: Container(
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: body,
          ),
        ),
        if (ownChanges && photo.status == PhotoStatus.ready)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Where the picture is drawn (fitted inside the cell, as
                  // CompositePainter does), so the dot sits on the photo.
                  final g = photoGeometry(
                    photo.width,
                    photo.height,
                    layout?.doc,
                  );
                  final k = math.min(box.maxWidth / g.w, box.maxHeight / g.h);
                  final left = (box.maxWidth - g.w * k) / 2;
                  final top = (box.maxHeight - g.h * k) / 2;
                  return Stack(
                    children: [
                      Positioned(
                        left: left + 6,
                        top: top + 6,
                        child: Semantics(
                          label: 'Edited',
                          child: Container(
                            key: const Key('own-changes-dot'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xCCFFFFFF),
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        if (onRemove != null)
          Positioned(
            top: -4,
            right: -4,
            child: Pressable(
              onPressed: onRemove,
              semanticLabel: 'Remove ${photo.name}',
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xB31F2328),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xE6FFFFFF),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.xmark,
                      size: 12,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shown instead of the grid when there are no photos.
class EmptyPhotos extends StatelessWidget {
  const EmptyPhotos({super.key, required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // A mouse on Windows and the website, and photos can be dropped there.
    final computer = kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
    return Pressable(
      onPressed: onTap,
      pressedOpacity: 0.7,
      semanticLabel: computer ? 'Click to add photos' : 'Tap to add photos',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.photo_on_rectangle,
                size: 30,
                color: c.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              computer ? 'Click to add photos' : 'Tap to add photos',
              style: AppText.title.copyWith(color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              computer
                  ? 'Every photo keeps its full resolution. You can also drop photos or a folder here.'
                  : 'Every photo keeps its full resolution.',
              textAlign: TextAlign.center,
              style: AppText.subhead.copyWith(color: c.secondary),
            ),
          ],
        ),
      ),
    );
  }
}
