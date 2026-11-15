import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/render/sample_scene.dart';
import 'package:pio_photo_layout/ui/app_theme.dart';
import 'package:pio_photo_layout/ui/widgets/app_button.dart';
import 'package:pio_photo_layout/ui/widgets/app_card.dart';
import 'package:pio_photo_layout/ui/widgets/icon_tile.dart';
import 'package:pio_photo_layout/ui/widgets/labeled_slider.dart';
import 'package:pio_photo_layout/ui/widgets/note_box.dart';
import 'package:pio_photo_layout/ui/widgets/segmented.dart';
import 'package:pio_photo_layout/ui/widgets/sheet_scaffold.dart';
import 'package:pio_photo_layout/ui/widgets/toast.dart';

import 'golden_helpers.dart';

class _ScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintSampleScene(canvas, size);
  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => false;
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CupertinoPageScaffold(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Shared pieces', style: AppText.largeTitle.copyWith(color: c.text)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AppButton(label: 'Save 12 photos', onPressed: () {})),
              const SizedBox(width: 8),
              AppIconButton(
                  icon: CupertinoIcons.slider_horizontal_3,
                  label: 'Options',
                  onPressed: () {},
                  background: c.raised,
                  size: 50),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AppButton.tinted(label: 'Share', icon: CupertinoIcons.share, onPressed: () {})),
              const SizedBox(width: 8),
              Expanded(child: AppButton.destructive(label: 'Remove', onPressed: () {})),
            ]),
            Row(children: [
              AppButton.plain(label: 'Clear', onPressed: () {}),
              const AppButton.plain(label: 'Disabled'),
            ]),
            const SizedBox(height: 8),
            const NoteBox(kind: NoteKind.info, text: 'Added "PIO footer". Use Edit layout to adjust it.'),
            const SizedBox(height: 8),
            NoteBox(
              kind: NoteKind.warning,
              text: "Photos are cropped to this layout's shape (3:2), so taller or wider photos lose their edges.",
              actionLabel: 'Fit every photo shape',
              onAction: () {},
            ),
            const SizedBox(height: 8),
            const NoteBox(kind: NoteKind.error, text: "logo.gif: this file isn't a layout from this tool."),
            const SizedBox(height: 12),
            AppGroup(header: 'Saving', footer: 'Every photo keeps its full resolution.', children: [
              AppRow(
                label: 'Format',
                trailing: Segmented<String>(
                    segments: const {'jpg': 'JPG', 'png': 'PNG'}, value: 'jpg', onChanged: (_) {}),
              ),
              const AppRow(label: 'Add to file names', detail: '_PIO'),
            ]),
            const SizedBox(height: 12),
            AppCard(
              child: LabeledSlider(
                  label: 'Quality', value: 92, min: 70, max: 100, onChanged: (_) {}, format: (v) => '${v.round()}%'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: Row(children: [
                IconTile(icon: CupertinoIcons.textformat, label: 'Text', onPressed: () {}),
                IconTile(icon: CupertinoIcons.square_on_circle, label: 'Shape', onPressed: () {}, selected: true),
                IconTile(icon: CupertinoIcons.star, label: 'Icon', onPressed: () {}),
                IconTile(icon: CupertinoIcons.photo, label: 'Picture', onPressed: () {}),
                IconTile(icon: CupertinoIcons.trash, label: 'Delete', onPressed: () {}, destructive: true),
              ]),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
              child: SizedBox(height: 90, child: CustomPaint(painter: _ScenePainter())),
            ),
            const SizedBox(height: 12),
            const Center(child: ToastView(message: 'Layout saved', icon: CupertinoIcons.checkmark_alt)),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: SheetScaffold(
                title: 'Options',
                onDone: () {},
                child: Text('Sheet body', style: AppText.body.copyWith(color: c.text)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  for (final b in Brightness.values) {
    final name = b == Brightness.dark ? 'dark' : 'light';
    testWidgets('gallery $name', (tester) async {
      await tester.runAsync(loadAppFonts);
      setPhone(tester, size: const Size(390, 1100));
      await tester.pumpWidget(themed(const _Gallery(), b));
      await tester.pumpAndSettle();
      await expectLater(find.byType(_Gallery), matchesGoldenFile('goldens/gallery_$name.png'));
    });
  }
}
