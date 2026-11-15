import '../../platform/device_noun.dart';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../core/fonts/font_registry.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/action_sheet.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/note_box.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/segmented.dart';
import 'font_library.dart';
import 'fonts_controller.dart';

enum FontsTab { library, file, mine }

/// "Fonts": the free library, font files, and the fonts added so far.
class FontsScreen extends StatefulWidget {
  const FontsScreen({super.key, required this.controller, this.initialTab = FontsTab.library});

  final FontsController controller;
  final FontsTab initialTab;

  @override
  State<FontsScreen> createState() => _FontsScreenState();
}

class _FontsScreenState extends State<FontsScreen> {
  late FontsTab _tab = widget.initialTab;
  final _search = TextEditingController();

  FontsController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.loadLibrary();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.page,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        const SizedBox(width: 88),
                        Expanded(
                          child: Text(
                            'Fonts',
                            textAlign: TextAlign.center,
                            style: AppText.headline.copyWith(color: colors.text),
                          ),
                        ),
                        SizedBox(
                          width: 88,
                          child: Pressable(
                            onPressed: () => Navigator.of(context).maybePop(),
                            semanticLabel: 'Done',
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.only(right: 16),
                              alignment: Alignment.centerRight,
                              child: Text('Done', style: AppText.button.copyWith(color: colors.accent)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: Segmented<FontsTab>(
                        compact: true,
                        segments: const {
                          FontsTab.library: 'Free library',
                          FontsTab.file: 'From a file',
                          FontsTab.mine: 'Your fonts',
                        },
                        value: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => switch (_tab) {
                FontsTab.library => _LibraryTab(controller: c, search: _search),
                FontsTab.file => _FileTab(controller: c),
                FontsTab.mine => _MineTab(controller: c),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- the free library ----------

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({required this.controller, required this.search});
  final FontsController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    if (c.libraryState == LibraryState.failed) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NoteBox(kind: NoteKind.error, text: c.libraryError, actionLabel: 'Try again', onAction: c.retryLibrary),
        ],
      );
    }
    if (c.libraryState != LibraryState.ready) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 12),
            const SizedBox(height: 12),
            Text('Loading the font library', style: AppText.subhead.copyWith(color: colors.secondary)),
          ],
        ),
      );
    }
    final list = c.visible;
    final left = c.found.length - list.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: CupertinoTextField(
            controller: search,
            placeholder: 'Search free fonts',
            prefix: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(CupertinoIcons.search, size: 18, color: colors.secondary),
            ),
            clearButtonMode: OverlayVisibilityMode.editing,
            autocorrect: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            style: AppText.body.copyWith(color: colors.text),
            placeholderStyle: AppText.body.copyWith(color: colors.secondary),
            decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(10)),
            onChanged: c.setQuery,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final e in {'': 'All', ...kFontCategories}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                  child: _Pill(label: e.value, on: c.category == e.key, onTap: () => c.setCategory(e.key)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(c.libraryCountLine, style: AppText.caption.copyWith(color: colors.secondary)),
          ),
        ),
        if (c.libraryMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: NoteBox(kind: c.libraryMessageBad ? NoteKind.error : NoteKind.info, text: c.libraryMessage),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: list.length + (left > 0 ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == list.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppButton.tinted(
                    label:
                        'Show more (${left.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} left)',
                    onPressed: c.showMore,
                  ),
                );
              }
              return _LibraryRow(key: ValueKey(list[i].id), controller: c, font: list[i]);
            },
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Pressable(
      onPressed: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: on ? colors.accent : colors.card, borderRadius: BorderRadius.circular(18)),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: AppText.subhead.copyWith(color: on ? colors.onAccent : colors.text)),
        ),
      ),
    );
  }
}

/// Faces loaded to draw a font's name in its own letters, one per visible row.
final Map<String, String> _previewFamilies = {};

class _LibraryRow extends StatefulWidget {
  const _LibraryRow({super.key, required this.controller, required this.font});
  final FontsController controller;
  final LibraryFont font;

  @override
  State<_LibraryRow> createState() => _LibraryRowState();
}

class _LibraryRowState extends State<_LibraryRow> {
  String? _family;

  @override
  void initState() {
    super.initState();
    _family = _previewFamilies[widget.font.id];
    if (_family == null) _load();
  }

  Future<void> _load() async {
    final f = widget.font;
    try {
      final w = f.weights.contains(400) ? 400 : f.weights.first;
      final bytes = await widget.controller.source.face(f, w, 'normal');
      final family = 'PIO preview ${f.id}';
      await ui.loadFontFromList(bytes, fontFamily: family);
      _previewFamilies[f.id] = family;
      if (mounted) setState(() => _family = family);
    } catch (_) {
      // The name stays in the app's own font.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final f = widget.font;
    final colors = AppColors.of(context);
    final builtIn = c.isBuiltIn(f);
    final have = c.isAdded(f);
    final progress = c.adding[f.family];
    final weights = f.weights.length == 1 ? '1 weight' : '${f.weights.length} weights';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.family,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: _family, fontSize: 20, color: colors.text, height: 1.25),
                ),
                const SizedBox(height: 2),
                Text('${f.categoryLabel}, $weights', style: AppText.caption.copyWith(color: colors.secondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (progress != null)
            Text(
              'Adding $progress',
              style: AppText.caption.copyWith(color: colors.secondary, fontFeatures: AppText.tabular),
            )
          else
            SizedBox(
              width: 84,
              child: have
                  ? AppButton.plain(label: builtIn ? 'Built in' : 'Added', expand: true, onPressed: null)
                  : AppButton.tinted(label: 'Add', height: 40, onPressed: () => c.addFromLibrary(f)),
            ),
        ],
      ),
    );
  }
}

// ---------- font files ----------

class _FileTab extends StatelessWidget {
  const _FileTab({required this.controller});
  final FontsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
          child: Column(
            children: [
              Icon(CupertinoIcons.textformat, size: 40, color: colors.accent),
              const SizedBox(height: 10),
              Text('Add a font file', style: AppText.title.copyWith(color: colors.text)),
              const SizedBox(height: 6),
              Text(
                'TTF, OTF, WOFF, or the ZIP file a font site gives you. The font is kept on this $deviceNoun and travels inside the layout files you share.',
                textAlign: TextAlign.center,
                style: AppText.subhead.copyWith(color: colors.secondary),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: c.readingFiles ? 'Reading' : 'Choose font files',
                icon: CupertinoIcons.folder,
                onPressed: c.readingFiles ? null : c.chooseFiles,
              ),
            ],
          ),
        ),
        if (c.fileMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          NoteBox(kind: c.fileMessageBad ? NoteKind.error : NoteKind.info, text: c.fileMessage),
        ],
      ],
    );
  }
}

// ---------- your fonts ----------

class _MineTab extends StatelessWidget {
  const _MineTab({required this.controller});
  final FontsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final mine = c.mine;
    if (mine.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No fonts added yet. Add one from the free library or from a file.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: colors.secondary),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final f in mine) _MineRow(controller: c, font: f)],
    );
  }
}

class _MineRow extends StatelessWidget {
  const _MineRow({required this.controller, required this.font});
  final FontsController controller;
  final AddedFont font;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final from = font.source == 'library' ? 'From the free library' : 'From a file';
    final weights = font.weights.length == 1 ? '1 weight' : '${font.weights.length} weights';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppMetrics.cardRadius)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  font.family,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: font.family, fontSize: 20, color: colors.text, height: 1.25),
                ),
                const SizedBox(height: 2),
                Text('$from, $weights', style: AppText.caption.copyWith(color: colors.secondary)),
              ],
            ),
          ),
          Pressable(
            onPressed: () async {
              final ok = await showConfirm(
                context,
                title: 'Remove ${font.family}?',
                message: 'Layouts that use it will show a stand-in font until it is added again.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (ok) await controller.remove(font.family);
            },
            semanticLabel: 'Remove ${font.family}',
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text('Remove', style: AppText.button.copyWith(color: colors.destructive)),
            ),
          ),
        ],
      ),
    );
  }
}
