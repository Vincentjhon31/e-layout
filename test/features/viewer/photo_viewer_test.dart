import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/features/viewer/photo_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';
import '../home/home_golden_test.dart' show ready;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opening on the second of three photos shows "2 of 3" and its Saves as line', (tester) async {
    final c = await ready(tester, withPhotos: true);
    // Keep three photos.
    for (final p in c.photos.sublist(3).toList()) {
      c.removePhoto(p.id);
    }
    setPhone(tester);
    await tester.pumpWidget(themed(PhotoViewer(controller: c, initialIndex: 1), Brightness.dark));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('IMG_2042.jpg'), findsOneWidget);
    expect(find.text('Saves as IMG_2042_PIO.jpg, 400 x 600 px'), findsOneWidget);
    await expectLater(find.byType(PhotoViewer), matchesGoldenFile('goldens/viewer.png'));
  });
}
