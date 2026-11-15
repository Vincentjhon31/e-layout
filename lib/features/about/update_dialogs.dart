import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../online/releases.dart';
import '../../platform/app_updater.dart';
import '../../platform/device_noun.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/pressable.dart';
import 'update_controller.dart';
import 'whats_new.dart';

/// Opens [uri] in the browser. Tests replace it.
Future<void> Function(Uri uri) openExternal = (uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
};

/// "Update available": what's new, "Later" and "Update".
Future<void> showUpdateAvailable(BuildContext context, UpdateController controller, ReleaseInfo release) {
  final c = AppColors.of(context);
  final maxList = MediaQuery.of(context).size.height * 0.5;
  return showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => AppDialog(
      title: 'Update available',
      message: 'Version ${release.version} is ready. It installs over this one, and your layouts, fonts and settings stay.',
      field: release.whatsNew.isEmpty
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxList),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("What's new in ${release.version}", style: AppText.captionStrong.copyWith(color: c.text)),
                    const SizedBox(height: 6),
                    for (final item in release.whatsNew)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('•  $item', style: AppText.caption.copyWith(color: c.secondary)),
                      ),
                  ],
                ),
              ),
            ),
      cancelLabel: 'Later',
      confirmLabel: 'Update',
      onConfirm: () {
        Navigator.of(ctx).pop();
        final updater = controller.updater;
        if (updater != null) unawaited(showUpdateDownload(context, updater, release));
      },
    ),
  );
}

/// The download box. It cannot be closed by tapping outside; closing it
/// (Cancel) stops the download.
Future<void> showUpdateDownload(BuildContext context, AppUpdater updater, ReleaseInfo release) {
  return showCupertinoDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => UpdateDownloadDialog(updater: updater, release: release),
  );
}

String megabytes(num bytes) => (bytes / 1048576).toStringAsFixed(1);

class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({super.key, required this.updater, required this.release, this.debugProgress, this.debugFailed = false});

  final AppUpdater updater;
  final ReleaseInfo release;

  /// For goldens: show this progress without starting a download.
  final double? debugProgress;
  final bool debugFailed;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  StreamSubscription<double?>? _sub;
  double? _progress;
  bool _failed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (widget.debugProgress != null || widget.debugFailed) {
      _progress = widget.debugProgress;
      _failed = widget.debugFailed;
    } else {
      _start();
    }
  }

  void _start() {
    setState(() {
      _failed = false;
      _opening = false;
      _progress = null;
    });
    _sub?.cancel();
    _sub = widget.updater.downloadAndInstall(widget.release).listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _opening = p != null && p >= 1;
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _failed = true);
      },
      onDone: () {
        // The installer is open (Android) or the app is about to close (Windows).
        if (mounted && !_failed) Navigator.of(context).maybePop();
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _cancel() {
    _sub?.cancel();
    Navigator.of(context).pop();
  }

  String get _status {
    if (_opening) return 'Opening the installer…';
    final size = widget.release.size;
    if (_progress == null || size == null) return 'Downloading…';
    return 'Downloading… ${megabytes(size * _progress!)} of ${megabytes(size)} MB';
  }

  String get _hint => deviceNoun == 'phone'
      ? 'If your phone asks, allow installs from e-Layout, then tap Update. Your layouts, fonts and settings stay.'
      : 'e-Layout will close, update itself and open again. Your layouts, fonts and settings stay.';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final surface = c.isDark ? c.raised : c.card;
    Widget action(String label, VoidCallback onTap, {bool strong = false}) => Pressable(
          onPressed: onTap,
          semanticLabel: label,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            child: ExcludeSemantics(
              child: Text(label, style: (strong ? AppText.headline : AppText.body).copyWith(color: c.accent)),
            ),
          ),
        );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppMetrics.sheetRadius)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Updating to version ${widget.release.version}',
                          textAlign: TextAlign.center, style: AppText.headline.copyWith(color: c.text)),
                      const SizedBox(height: 14),
                      if (_failed)
                        Text(
                          "The update couldn't be downloaded. Check your internet connection and try again.",
                          textAlign: TextAlign.center,
                          style: AppText.subhead.copyWith(color: c.destructive),
                        )
                      else ...[
                        _Bar(value: _opening ? 1 : _progress),
                        const SizedBox(height: 10),
                        Text(_status,
                            textAlign: TextAlign.center,
                            style: AppText.subhead.copyWith(color: c.text, fontFeatures: AppText.tabular)),
                        const SizedBox(height: 8),
                        Text(_hint, textAlign: TextAlign.center, style: AppText.caption.copyWith(color: c.secondary)),
                      ],
                    ],
                  ),
                ),
                Container(height: 0.5, color: c.separator),
                if (_failed) ...[
                  action('Download in browser', () => unawaited(openExternal(Uri.parse(widget.release.downloadUrl)))),
                  Container(height: 0.5, color: c.separator),
                  action('Try again', _start, strong: true),
                  Container(height: 0.5, color: c.separator),
                  action('Cancel', _cancel),
                ] else
                  action('Cancel', _cancel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});
  final double? value;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: value == null
            ? const CupertinoActivityIndicator()
            : Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: c.separator)),
                  FractionallySizedBox(
                    widthFactor: value!.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: ColoredBox(color: c.accent),
                  ),
                ],
              ),
      ),
    );
  }
}

/// For [WhatsNewList] in the update box (kept here so both use the same words).
List<WhatsNewEntry> entriesFor(ReleaseInfo r) => [WhatsNewEntry(version: r.version, items: r.whatsNew)];

/// Used by About's "Update now": shows the download box.
Future<void> startUpdate(BuildContext context, UpdateController controller, ReleaseInfo release) async {
  final updater = controller.updater;
  if (updater == null) return;
  await showUpdateDownload(context, updater, release);
}
