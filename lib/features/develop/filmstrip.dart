import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../ui/app_theme.dart';
import '../../ui/previews.dart';
import '../../ui/widgets/pressable.dart';
import 'photo_editor_controller.dart';

/// Thumbnail size and gap in the filmstrip.
const double kFilmThumb = 56;
const double _gap = 6;
const double _side = 12;

/// The batch as a row of thumbnails with their edits; the open photo is
/// ringed and a tap opens another.
class Filmstrip extends StatefulWidget {
  const Filmstrip({super.key, required this.controller});

  final PhotoEditorController controller;

  @override
  State<Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<Filmstrip> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  /// Starts with the open photo in the middle.
  ScrollController _scrollFor(double width, int count, int index) {
    final have = _scroll;
    if (have != null) return have;
    final content =
        _side * 2 + count * kFilmThumb + math.max(0, count - 1) * _gap;
    final max = math.max(0.0, content - width);
    final at = _side + index * (kFilmThumb + _gap) + kFilmThumb / 2 - width / 2;
    return _scroll = ScrollController(initialScrollOffset: at.clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = widget.controller;
    final photos = c.photos;
    final current = c.photo.id;
    return Container(
      height: kFilmThumb + 16,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => ListView.separated(
          key: const ValueKey('filmstrip'),
          controller: _scrollFor(box.maxWidth, photos.length, c.index),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _side, vertical: 8),
          itemCount: photos.length,
          separatorBuilder: (_, _) => const SizedBox(width: _gap),
          itemBuilder: (context, i) {
            final p = photos[i];
            final img = p.developed ?? p.preview;
            final on = p.id == current;
            return Pressable(
              key: ValueKey('film-${p.id}'),
              onPressed: () => c.showPhoto(i),
              semanticLabel: 'Photo ${i + 1} of ${photos.length}',
              child: Container(
                width: kFilmThumb,
                height: kFilmThumb,
                foregroundDecoration: on
                    ? BoxDecoration(
                        border: Border.all(color: colors.accent, width: 3),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: img == null
                      ? ColoredBox(color: colors.raised)
                      : CustomPaint(
                          painter: CompositePainter(
                            image: img,
                            photoWidth: p.width,
                            photoHeight: p.height,
                            doc: null,
                            prep: null,
                            cover: true,
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
