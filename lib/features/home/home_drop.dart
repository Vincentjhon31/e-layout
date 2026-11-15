import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../platform/photo_picker.dart';
import '../../ui/app_theme.dart';
import '../layouts/import_layout.dart' show isLayoutFileName;
import 'export_job.dart' show naturalCompare;
import 'home_controller.dart';

final RegExp _photoName = RegExp(
  r'\.(jpe?g|png|webp|bmp|gif)$',
  caseSensitive: false,
);

bool isPhotoName(String name) => _photoName.hasMatch(name);

/// Dropped files and folders as picked files: folders are opened, and only
/// photos and layout files are kept, in name order.
Future<List<PickedPhoto>> pickedFromDrop(List<DropItem> items) async {
  final out = <PickedPhoto>[];
  Future<void> walk(DropItem item) async {
    if (item is DropItemDirectory) {
      for (final child in item.children) {
        await walk(child);
      }
      return;
    }
    final name = item.name.split(RegExp(r'[\\/]')).last;
    if (!isPhotoName(name) && !isLayoutFileName(name)) return;
    int? size;
    DateTime? modified;
    try {
      size = await item.length();
      modified = await item.lastModified();
    } catch (_) {}
    out.add(
      PickedPhoto(
        name: name,
        path: item.path,
        readBytes: item.readAsBytes,
        size: size,
        modified: modified,
      ),
    );
  }

  for (final item in items) {
    await walk(item);
  }
  out.sort((a, b) => naturalCompare(a.name, b.name));
  return out;
}

/// Drag and drop on Windows and the website: photos or a folder anywhere on
/// Home add photos; anything dropped on the layout row ([layoutRowRect]) is
/// imported as a layout. Layout files dropped elsewhere are imported too.
class HomeDropTarget extends StatefulWidget {
  const HomeDropTarget({
    super.key,
    required this.controller,
    required this.layoutRowRect,
    required this.child,
  });

  final HomeController controller;
  final Rect? Function() layoutRowRect;
  final Widget child;

  /// Where dropping is available.
  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

  @override
  State<HomeDropTarget> createState() => _HomeDropTargetState();
}

class _HomeDropTargetState extends State<HomeDropTarget> {
  bool _over = false;

  Future<void> _done(DropDoneDetails d) async {
    setState(() => _over = false);
    if (widget.controller.saving) return;
    final files = await pickedFromDrop(d.files);
    final row = widget.layoutRowRect();
    await widget.controller.handleDrop(
      files,
      onLayouts: row != null && row.contains(d.globalPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!HomeDropTarget.supported) return widget.child;
    final c = AppColors.of(context);
    return DropTarget(
      enable: ModalRoute.of(context)?.isCurrent ?? true,
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: _done,
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.08),
                    border: Border.all(color: c.accent, width: 2),
                    borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Drop photos here to add them',
                    style: AppText.headline.copyWith(color: c.accent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
