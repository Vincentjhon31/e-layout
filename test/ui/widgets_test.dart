import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/ui/app_theme.dart';
import 'package:pio_photo_layout/ui/widgets/app_button.dart';
import 'package:pio_photo_layout/ui/widgets/note_box.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) => CupertinoApp(
      theme: appTheme(brightness),
      home: CupertinoPageScaffold(child: Center(child: child)),
    );

void main() {
  testWidgets('AppColors.of follows the theme brightness', (tester) async {
    late AppColors light, dark;
    await tester.pumpWidget(_host(Builder(builder: (c) {
      light = AppColors.of(c);
      return const SizedBox();
    })));
    await tester.pumpWidget(_host(Builder(builder: (c) {
      dark = AppColors.of(c);
      return const SizedBox();
    }), brightness: Brightness.dark));
    expect(light.page, const Color(0xFFF2F2F7));
    expect(light.card, const Color(0xFFFFFFFF));
    expect(light.raised, const Color(0xFFEFEFF4));
    expect(light.text, const Color(0xFF111418));
    expect(light.secondary, const Color(0xFF5F6670));
    expect(light.separator, const Color(0xFFD9DCE1));
    expect(light.accent, const Color(0xFF1A6FB3));
    expect(light.destructive, const Color(0xFFC4291C));
    expect(light.warningBg, const Color(0xFFFFF4D6));
    expect(light.warningText, const Color(0xFF6B4E00));
    expect(dark.page, const Color(0xFF000000));
    expect(dark.card, const Color(0xFF1C1C1E));
    expect(dark.raised, const Color(0xFF2C2C2E));
    expect(dark.text, const Color(0xFFFFFFFF));
    expect(dark.secondary, const Color(0xFFA1A1AA));
    expect(dark.separator, const Color(0xFF38383A));
    expect(dark.accent, const Color(0xFF5CB8FF));
    expect(dark.destructive, const Color(0xFFFF6B5E));
    expect(dark.warningBg, const Color(0xFF3A2F0B));
    expect(dark.warningText, const Color(0xFFFFD970));
  });

  testWidgets('a filled AppButton is at least 50 tall and calls onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(SizedBox(
        width: 300, child: AppButton(label: 'Save 12 photos', onPressed: () => taps++))));
    expect(tester.getSize(find.byType(AppButton)).height, greaterThanOrEqualTo(50));
    await tester.tap(find.text('Save 12 photos'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('NoteBox with an action shows its label and runs it', (tester) async {
    var runs = 0;
    await tester.pumpWidget(_host(Padding(
      padding: const EdgeInsets.all(16),
      child: NoteBox(
        kind: NoteKind.warning,
        text: 'Photos are cropped to this layout\'s shape (3:2).',
        actionLabel: 'Fit every photo shape',
        onAction: () => runs++,
      ),
    )));
    expect(find.text('Fit every photo shape'), findsOneWidget);
    await tester.tap(find.text('Fit every photo shape'));
    await tester.pumpAndSettle();
    expect(runs, 1);
  });
}
