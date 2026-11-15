import 'package:flutter/cupertino.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/page_header.dart';
import 'whats_new.dart';

/// Every version and what changed in it, newest first.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key, required this.entries});
  final List<WhatsNewEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.page,
      child: Column(
        children: [
          const PageHeader(title: 'Changelog'),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < entries.length; i++) ...[
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 24, bottom: 10),
                            child: Text('Version ${entries[i].version}', style: AppText.title.copyWith(color: c.text)),
                          ),
                          WhatsNewList(entries: [entries[i]], headings: false),
                        ],
                      ],
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
}
