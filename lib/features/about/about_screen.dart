import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../app_info.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/page_header.dart';
import 'changelog_screen.dart';
import 'licences_screen.dart';
import 'update_controller.dart';
import 'update_dialogs.dart';
import 'whats_new.dart';

/// "About": the version, updates, what's new, the changelog, privacy and contact.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.updates});
  final UpdateController updates;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  List<WhatsNewEntry> _entries = const [];

  UpdateController get u => widget.updates;

  @override
  void initState() {
    super.initState();
    unawaited(u.check());
    unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
    try {
      final e = parseWhatsNew(await loadWhatsNewMarkdown());
      if (mounted) setState(() => _entries = e);
    } catch (_) {
      // No notes: the What's new group just does not show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.page,
      child: Column(
        children: [
          const PageHeader(title: 'About'),
          Expanded(
            child: ListenableBuilder(
              listenable: u,
              builder: (context, _) => SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeaderCard(version: u.version, buildNumber: u.build),
                          const SizedBox(height: 24),
                          ..._updateGroups(context),
                          if (_current != null) ...[
                            AppGroup(
                              header: "What's new in ${_current!.version}",
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                                  child: WhatsNewList(entries: [_current!], headings: false),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                          AppGroup(children: [
                            AppRow(
                              label: 'Changelog',
                              trailing: Icon(CupertinoIcons.chevron_forward, size: 16, color: c.secondary),
                              onTap: _entries.isEmpty ? null : () => _openChangelog(context),
                            ),
                            AppRow(
                              label: 'Download page',
                              detail: kSiteUrl.host,
                              trailing: Icon(CupertinoIcons.arrow_up_right_square, size: 18, color: c.secondary),
                              onTap: () => unawaited(openExternal(kDownloadPageUrl)),
                            ),
                            AppRow(
                              label: 'Licences',
                              trailing: Icon(CupertinoIcons.chevron_forward, size: 16, color: c.secondary),
                              onTap: () => Navigator.of(context)
                                  .push(CupertinoPageRoute<void>(builder: (_) => const LicencesScreen())),
                            ),
                          ]),
                          const SizedBox(height: 24),
                          AppGroup(header: 'Privacy', children: [
                            _TextRow(
                              'Your photos stay on this device. e-Layout goes online only to check for updates and to add fonts from the free library.',
                            ),
                          ]),
                          const SizedBox(height: 24),
                          AppGroup(
                            header: 'Contact',
                            footer:
                                'Office of the Municipal Mayor, Bongabong, Oriental Mindoro. Message the office on its Facebook page, Bongabong Public Information Office.',
                            children: [_TextRow('Bongabong Public Information Office', strong: true)],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The notes of the version that is running (or the newest in the file).
  WhatsNewEntry? get _current {
    if (_entries.isEmpty) return null;
    for (final e in _entries) {
      if (e.version == u.version) return e;
    }
    return _entries.first;
  }

  void _openChangelog(BuildContext context) {
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => ChangelogScreen(entries: _entries)));
  }

  List<Widget> _updateGroups(BuildContext context) {
    final c = AppColors.of(context);
    final s = u.state;
    Widget row(String text, {Widget? trailing}) => AppRow(label: text, trailing: trailing);
    Widget small(String label, VoidCallback onTap, {bool filled = false}) => filled
        ? AppButton(label: label, onPressed: onTap, expand: false, height: 36)
        : AppButton.plain(label: label, onPressed: onTap);
    final Widget main;
    var extra = <Widget>[];
    switch (s) {
      case UpdateIdle() || UpdateChecking():
        main = row('Checking for updates…', trailing: const CupertinoActivityIndicator());
      case UpToDate():
        main = row(
          u.web != null ? 'The website version updates itself.' : "You're up to date.",
          trailing: small('Check for updates', () => unawaited(u.check())),
        );
      case UpdateAvailable(:final release):
        main = row('Version ${release.version} is available.',
            trailing: small('Update now', () => unawaited(startUpdate(context, u, release)), filled: true));
        if (release.whatsNew.isNotEmpty) {
          extra = [
            const SizedBox(height: 24),
            AppGroup(header: "What's new in ${release.version}", children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: WhatsNewList(entries: entriesFor(release), headings: false),
              ),
            ]),
          ];
        }
      case UpdateOffline():
        main = row("You're offline. Check for updates when you're connected.",
            trailing: small('Try again', () => unawaited(u.check())));
      case UpdateFailed():
        main = row("Can't check for updates right now. Try again later.",
            trailing: small('Try again', () => unawaited(u.check())));
      case WebReloadReady():
        main = row('A newer version is on the website.', trailing: small('Reload', u.reload, filled: true));
      case UpdatesNotOffered():
        main = row('New versions are on the download page.',
            trailing: small('Open the download page', () => unawaited(openExternal(kDownloadPageUrl))));
    }
    return [
      AppGroup(header: 'Updates', children: [main]),
      ...extra,
      SizedBox(height: 24, child: ColoredBox(color: c.page)),
    ];
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(text, style: (strong ? AppText.headline : AppText.body).copyWith(color: c.text)),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.version, required this.buildNumber});
  final String version;
  final int buildNumber;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/img/app_icon.png', width: 72, height: 72, filterQuality: FilterQuality.medium),
          ),
          const SizedBox(height: 14),
          Text(kAppName, style: AppText.title.copyWith(color: c.text)),
          const SizedBox(height: 2),
          Text('Version $version ($buildNumber)', style: AppText.subhead.copyWith(color: c.secondary)),
          const SizedBox(height: 2),
          Text('Public Information Office, Municipality of Bongabong',
              textAlign: TextAlign.center, style: AppText.caption.copyWith(color: c.secondary)),
        ],
      ),
    );
  }
}
