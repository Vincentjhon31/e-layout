import 'package:flutter/cupertino.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/app_button.dart';
import 'export_job.dart';
import 'home_controller.dart';

/// The bar pinned to the bottom: "Save 12 photos" and Options; progress while
/// saving; the result line with Share afterwards.
class SaveBar extends StatelessWidget {
  const SaveBar({super.key, required this.controller, required this.onOptions});

  final HomeController controller;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final job = controller.job;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.gutter,
            12,
            AppMetrics.gutter,
            0,
          ),
          child: job != null
              ? _Progress(job: job, onCancel: controller.cancelSave)
              : _Idle(controller, onOptions),
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle(this.controller, this.onOptions);
  final HomeController controller;
  final VoidCallback onOptions;

  String? _status() {
    final total = controller.photos.length;
    final ready = controller.readyPhotos.length;
    final failed = controller.errorCount;
    final loading = controller.loadingCount;
    if (controller.current == null && controller.ready) {
      return 'Choose or make a layout first.';
    }
    if (loading > 0) return 'Reading photos: ${ready + failed} of $total';
    if (controller.message.isNotEmpty) return controller.message;
    if (total > 0 && ready == 0) return 'None of these photos can be opened.';
    if (failed > 0) {
      return "${plural(failed, 'file', 'files')} can't be opened and will be left out.";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ready = controller.readyPhotos.length;
    final status = _status();
    final shareLabel = controller.sharer.buttonLabel;
    final canShare = shareLabel != null &&
        controller.message.isNotEmpty &&
        controller.lastSaved.isNotEmpty;
    final canSave =
        ready > 0 && controller.current != null && controller.loadingCount == 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    style: AppText.subhead.copyWith(
                      color: c.secondary,
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                ),
                if (canShare) ...[
                  const SizedBox(width: 8),
                  AppButton.plain(
                    label: shareLabel,
                    icon: controller.sharer.needsCopies ? CupertinoIcons.share : CupertinoIcons.folder,
                    onPressed: controller.shareLast,
                  ),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: ready > 0
                    ? 'Save ${plural(ready, 'photo', 'photos')}'
                    : 'Save photos',
                onPressed: canSave ? controller.saveAll : null,
              ),
            ),
            const SizedBox(width: 10),
            AppIconButton(
              icon: CupertinoIcons.slider_horizontal_3,
              label: 'Options',
              onPressed: onOptions,
              background: c.raised,
              size: AppMetrics.buttonHeight,
            ),
          ],
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.job, required this.onCancel});
  final ExportJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.cancelRequested
                        ? 'Stopping after this photo'
                        : 'Saving ${job.current} of ${job.total}',
                    style: AppText.headline.copyWith(
                      color: c.text,
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    job.currentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: c.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppButton.plain(
              label: 'Cancel',
              onPressed: job.cancelRequested ? null : onCancel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 8,
            color: c.raised,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: job.fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: c.accent),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
