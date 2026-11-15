import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app_info.dart';
import '../../core/store/settings_store.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/sheet_scaffold.dart';

class WhatsNewEntry {
  const WhatsNewEntry({required this.version, required this.items});
  final String version;
  final List<String> items;
}

final _comment = RegExp(r'<!--[\s\S]*?-->');
final _heading = RegExp(r'^##\s+v?(\d+\.\d+\.\d+)');

/// Turns a bullet into plain text: no markup, links and images keep their words.
String plainText(String text) {
  var t = text;
  t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  t = t.replaceAll(RegExp(r'<[^>]*>'), '');
  t = t.replaceAll(RegExp(r'[*_`]'), '');
  return t.trim();
}

/// The sections of `assets/whats_new.md`, newest first (file order).
List<WhatsNewEntry> parseWhatsNew(String markdown) {
  final out = <WhatsNewEntry>[];
  String? version;
  var items = <String>[];
  void close() {
    if (version != null && items.isNotEmpty) out.add(WhatsNewEntry(version: version, items: items));
  }

  for (final line in markdown.replaceAll(_comment, '').split('\n')) {
    final h = _heading.firstMatch(line.trim());
    if (h != null) {
      close();
      version = h.group(1);
      items = [];
    } else if (version != null && line.trimLeft().startsWith('- ')) {
      final t = plainText(line.trimLeft().substring(2));
      if (t.isNotEmpty) items.add(t);
    }
  }
  close();
  return out;
}

Future<String> defaultLoadWhatsNew() => rootBundle.loadString('assets/whats_new.md');

/// Tests replace this: a real asset read never finishes under the fake clock.
Future<String> Function() loadWhatsNewMarkdown = defaultLoadWhatsNew;

bool _newer(String a, String b) {
  List<int> p(String v) => v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c > 0;
  }
  return false;
}

/// After an update: shows what is new once. Nothing on a fresh install.
Future<void> showWhatsNewIfUpdated(BuildContext context, SettingsStore settings, {String version = kAppVersion}) async {
  try {
    final seen = await settings.readValue('whats_new_seen');
    if (seen == version) return;
    await settings.writeValue('whats_new_seen', version);
    if (seen == null) return;
    final all = parseWhatsNew(await loadWhatsNewMarkdown());
    final missed = all.where((e) => _newer(e.version, seen) && !_newer(e.version, version)).toList();
    if (missed.isEmpty || !context.mounted) return;
    await showWhatsNewSheet(context, missed);
  } catch (_) {
    // The notes are a courtesy; never get in the way.
  }
}

/// The sheet: one heading per version, a tick before each bullet, "Got it".
Future<void> showWhatsNewSheet(BuildContext context, List<WhatsNewEntry> entries) {
  return showAppSheet<void>(context, (ctx) => WhatsNewSheet(entries: entries));
}

class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.entries});
  final List<WhatsNewEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mq = MediaQuery.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: mq.size.height * 0.8),
        child: Container(
          decoration: BoxDecoration(
            color: c.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppMetrics.sheetRadius)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(color: c.separator, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: WhatsNewList(entries: entries),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: AppButton(label: 'Got it', onPressed: () => Navigator.of(context).maybePop()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "What's new in X" headings with ticked bullets (also used by About).
class WhatsNewList extends StatelessWidget {
  const WhatsNewList({super.key, required this.entries, this.headings = true});
  final List<WhatsNewEntry> entries;
  final bool headings;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (headings)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 20, bottom: 10),
              child: Text("What's new in ${entries[i].version}", style: AppText.title.copyWith(color: c.text)),
            ),
          for (final item in entries[i].items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(CupertinoIcons.checkmark_circle_fill, size: 20, color: c.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item, style: AppText.body.copyWith(color: c.text))),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
