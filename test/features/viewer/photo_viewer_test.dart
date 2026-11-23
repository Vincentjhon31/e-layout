import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/photo_developer.dart';
import 'package:pio_photo_layout/features/viewer/photo_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';
import '../home/home_controller_test.dart' show picked, png;
import '../home/home_develop_test.dart' show Rig, Stores, exposure;
import '../home/home_golden_test.dart' show ready;

/// The sum of every RGB value on screen under [key].
Future<double> shownLevel(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    var sum = 0.0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      sum += data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2);
    }
    return sum;
  }))!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'opening on the second of three photos shows "2 of 3" and its Saves as line',
    (tester) async {
      final c = await ready(tester, withPhotos: true);
      // Keep three photos.
      for (final p in c.photos.sublist(3).toList()) {
        c.removePhoto(p.id);
      }
      setPhone(tester);
      await tester.pumpWidget(
        themed(PhotoViewer(controller: c, initialIndex: 1), Brightness.dark),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('IMG_2042.jpg'), findsOneWidget);
      expect(
        find.text('Saves as IMG_2042_PIO.jpg, 400 x 600 px'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(PhotoViewer),
        matchesGoldenFile('goldens/viewer.png'),
      );
    },
  );

  testWidgets('the viewer shows a photo with its edits, a neutral one plain', (
    tester,
  ) async {
    final c = Rig(Stores(), developer: CpuDeveloper()).controller;
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await c.init();
      await c.addPhotos([picked('a.jpg', png(40, 30))]);
      await c.whenIdle();
    });
    final key = GlobalKey();
    setPhone(tester);
    await tester.pumpWidget(
      themed(
        RepaintBoundary(
          key: key,
          child: PhotoViewer(controller: c, initialIndex: 0),
        ),
        Brightness.dark,
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
    }

    await settle();
    final plain = await shownLevel(tester, key);

    await tester.runAsync(
      () => c.setLook(c.look.withPhotoPatch(c.photos.first.id, exposure(1))),
    );
    await settle();
    final edited = await shownLevel(tester, key);
    expect(edited, greaterThan(plain), reason: 'exposure brightens the viewer');

    await tester.runAsync(
      () => c.setLook(c.look.withPhotoPatch(c.photos.first.id, exposure(0))),
    );
    await settle();
    expect(await shownLevel(tester, key), plain, reason: 'neutral is plain');
  });
}
