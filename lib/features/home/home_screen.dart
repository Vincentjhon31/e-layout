import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../app_info.dart';
import '../../platform/device_noun.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/note_box.dart';
import '../../ui/widgets/sheet_scaffold.dart';
import '../about/update_controller.dart';
import '../about/whats_new.dart';
import 'export_job.dart';
import 'home_controller.dart';
import 'home_drop.dart';
import 'layout_strip.dart';
import 'options_sheet.dart';
import 'photo_grid.dart';
import 'preset_picker.dart';
import 'preset_row.dart';
import 'save_bar.dart';

/// Things the home screen hands to other screens (filled in by the app).
class HomeActions {
  const HomeActions({
    this.openPhoto,
    this.layoutActions,
    this.addLayout,
    this.moreMenu,
  });

  final void Function(BuildContext context, PhotoItem photo)? openPhoto;
  final void Function(BuildContext context, LayoutItem item)? layoutActions;
  final void Function(BuildContext context)? addLayout;
  final void Function(BuildContext context)? moreMenu;
}

class HomeScreen extends StatefulWidget {
  /// [updates] is null in tests, so no start-up checks run there.
  const HomeScreen({super.key, required this.controller, this.actions = const HomeActions(), this.updates});

  final HomeController controller;
  final HomeActions actions;
  final UpdateController? updates;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _updateTimer;
  final GlobalKey _layoutRowKey = GlobalKey();

  Rect? _layoutRowRect() {
    final box = _layoutRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    super.initState();
    final updates = widget.updates;
    if (updates != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showWhatsNewIfUpdated(context, updates.settings);
        if (!mounted) return;
        _updateTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) unawaited(updates.checkAtStart(context));
        });
      });
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return CupertinoPageScaffold(
      child: HomeDropTarget(
        controller: controller,
        layoutRowRect: _layoutRowRect,
        child: ListenableBuilder(
        listenable: Listenable.merge([controller, ?widget.updates]),
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppMetrics.contentMaxWidth),
                  child: _Body(controller: controller, actions: widget.actions, updates: widget.updates, layoutRowKey: _layoutRowKey),
                ),
              ),
            ),
            SaveBar(
              controller: controller,
              onOptions: () => showAppSheet<void>(context, (_) => OptionsSheet(controller: controller)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// "Add photos". Windows also offers a whole folder.
Future<void> addPhotosFlow(BuildContext context, HomeController controller) {
  if (!controller.picker.canPickFolder) return controller.pickPhotos();
  return showActionSheet(
    context,
    actions: [
      SheetAction('Add photos', controller.pickPhotos),
      SheetAction('Add a folder', controller.addFolder),
    ],
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.actions, this.updates, this.layoutRowKey});
  final Key? layoutRowKey;
  final HomeController controller;
  final HomeActions actions;
  final UpdateController? updates;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final saving = controller.saving;
    final photos = controller.photos;
    final notices = controller.notices;
    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppMetrics.gutter, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(kAppName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.largeTitle.copyWith(color: c.text)),
                  ),
                  AppIconButton(
                    icon: CupertinoIcons.ellipsis_circle,
                    label: 'More',
                    iconSize: 26,
                    onPressed: actions.moreMenu == null || saving ? null : () => actions.moreMenu!(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (updates?.state case WebReloadReady())
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppMetrics.gutter, 4, AppMetrics.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: NoteBox(
                kind: NoteKind.info,
                text: 'A new version of e-Layout is ready.'
                    '${photos.isEmpty ? ' Reload to use it.' : ' Reload to use it. Photos you added will need adding again.'}',
                actionLabel: 'Reload',
                onAction: updates!.reload,
              ),
            ),
          ),
        SliverToBoxAdapter(child: _SectionTitle(title: 'Layout')),
        SliverToBoxAdapter(
          key: layoutRowKey,
          child: controller.ready
              ? IgnorePointer(
                  ignoring: saving,
                  child: LayoutStrip(
                    layouts: controller.layouts,
                    selectedId: controller.selectedId,
                    onSelect: (item) => controller.selectLayout(item.id),
                    onActions: (item) => actions.layoutActions?.call(context, item),
                    onAdd: () => actions.addLayout?.call(context),
                  ),
                )
              : const SizedBox(height: 146, child: Center(child: CupertinoActivityIndicator())),
        ),
        if (notices.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppMetrics.gutter, 4, AppMetrics.gutter, 0),
            sliver: SliverList.separated(
              itemCount: notices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = notices[i];
                return _NoticeView(notice: n, enabled: !saving);
              },
            ),
          ),
        if (controller.editingAvailable)
          SliverToBoxAdapter(
            child: IgnorePointer(
              ignoring: saving,
              child: PresetRow(look: controller.look, onTap: () => showPresetPicker(context, controller)),
            ),
          ),
        SliverToBoxAdapter(
          child: _SectionTitle(
            title: 'Photos',
            count: photos.isEmpty ? null : photos.length,
            caption: photos.isEmpty ? null : 'Kept on this $deviceNoun: ${formatBytes(controller.keptBytes)}',
            trailing: photos.isEmpty
                ? null
                : AppButton.plain(label: 'Clear', onPressed: saving ? null : () => _confirmClear(context, controller)),
          ),
        ),
        if (photos.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppMetrics.gutter),
            sliver: SliverToBoxAdapter(child: EmptyPhotos(onTap: saving ? null : () => addPhotosFlow(context, controller))),
          )
        else
          PhotoGrid(
            photos: photos,
            layout: controller.current,
            enabled: !saving,
            hasOwnChanges: controller.hasOwnChanges,
            onAdd: () => addPhotosFlow(context, controller),
            onOpen: (p) => actions.openPhoto?.call(context, p),
            onRemove: (p) => controller.removePhoto(p.id),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

Future<void> _confirmClear(BuildContext context, HomeController controller) async {
  final ok = await showConfirm(
    context,
    title: 'Clear all photos?',
    message: 'The photos and their edits are removed from e-Layout. Your original photos are not touched.',
    confirmLabel: 'Clear',
    destructive: true,
  );
  if (ok) await controller.clearPhotos();
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.count, this.caption, this.trailing});
  final String title;
  final int? count;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppMetrics.gutter, 18, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: caption == null ? 44 : 36,
            child: Row(
              children: [
                Text(title, style: AppText.title.copyWith(color: c.text)),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text('$count', style: AppText.title.copyWith(color: c.secondary, fontWeight: FontWeight.w400, fontFeatures: AppText.tabular)),
                ],
                const Spacer(),
                if (trailing != null) OverflowBox(maxHeight: 44, fit: OverflowBoxFit.deferToChild, child: trailing),
              ],
            ),
          ),
          if (caption != null) Text(caption!, style: AppText.caption.copyWith(color: c.secondary)),
        ],
      ),
    );
  }
}

class _NoticeView extends StatefulWidget {
  const _NoticeView({required this.notice, required this.enabled});
  final Notice notice;
  final bool enabled;

  @override
  State<_NoticeView> createState() => _NoticeViewState();
}

class _NoticeViewState extends State<_NoticeView> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.notice;
    return NoteBox(
      kind: n.kind,
      text: n.text,
      actionLabel: n.actionLabel,
      busy: _busy,
      onAction: n.action == null || !widget.enabled
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await n.action!();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}
