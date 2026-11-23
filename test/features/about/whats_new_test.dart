import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/app_info.dart';
import 'package:pio_photo_layout/core/store/settings_store.dart';
import 'package:pio_photo_layout/features/about/whats_new.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/golden_helpers.dart';

const sample = '''
# What's new

<!-- a comment
## 9.9.9
- hidden
-->

## 1.1.0

- First **bold** idea with a [link](https://example.com) and `code`.
- Second idea with <b>markup</b>.

## 1.0.0

- The start, with ![an image](x.png) in it.

## 0.9.5

No bullets here.
''';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  tearDown(() => loadWhatsNewMarkdown = defaultLoadWhatsNew);

  test('parseWhatsNew gives plain items, newest first, and drops a version without bullets', () {
    final e = parseWhatsNew(sample);
    expect(e.map((x) => x.version), ['1.1.0', '1.0.0']);
    expect(e[0].items, ['First bold idea with a link and code.', 'Second idea with markup.']);
    expect(e[1].items, ['The start, with an image in it.']);
  });

  test('the real file starts with the current version, and keeps the 1.0.0 notes', () async {
    final text = await rootBundle.loadString('assets/whats_new.md');
    final e = parseWhatsNew(text);
    expect(e.first.version, kAppVersion);
    expect(e.first.items, isNotEmpty);
    final first = e.firstWhere((x) => x.version == '1.0.0');
    expect(first.items.length, greaterThanOrEqualTo(3));
  });

  Future<(SettingsStore, BuildContext)> setup(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await tester.pumpWidget(themed(const Center(child: Text('home')), Brightness.light));
    return (SettingsStore(), tester.element(find.text('home')));
  }

  testWidgets('a fresh install shows nothing and remembers the version', (tester) async {
    await tester.runAsync(loadAppFonts);
    loadWhatsNewMarkdown = () async => sample;
    final (s, ctx) = await setup(tester, {});
    await tester.runAsync(() => showWhatsNewIfUpdated(ctx, s, version: '1.1.0'));
    await tester.pump();
    expect(find.textContaining("What's new in"), findsNothing);
    expect(await tester.runAsync(() => s.readValue('whats_new_seen')), '1.1.0');
  });

  testWidgets('after an update the sheet shows that version', (tester) async {
    await tester.runAsync(loadAppFonts);
    loadWhatsNewMarkdown = () async => sample;
    final (s, ctx) = await setup(tester, {'e-layout:whats_new_seen': '1.0.0'});
    unawaited(showWhatsNewIfUpdated(ctx, s, version: '1.1.0'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("What's new in 1.1.0"), findsOneWidget);
    expect(find.text("What's new in 1.0.0"), findsNothing);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('several missed versions show newest first', (tester) async {
    await tester.runAsync(loadAppFonts);
    loadWhatsNewMarkdown = () async => '## 1.1.0\n- A\n\n## 1.0.0\n- B\n\n## 0.9.0\n- C\n\n## 0.8.0\n- D\n';
    final (s, ctx) = await setup(tester, {'e-layout:whats_new_seen': '0.8.0'});
    unawaited(showWhatsNewIfUpdated(ctx, s, version: '1.1.0'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 1));
    final first = tester.getTopLeft(find.text("What's new in 1.1.0")).dy;
    final second = tester.getTopLeft(find.text("What's new in 1.0.0")).dy;
    final third = tester.getTopLeft(find.text("What's new in 0.9.0")).dy;
    expect(first < second && second < third, isTrue);
    expect(find.text("What's new in 0.8.0"), findsNothing);
  });

  testWidgets('same version shows nothing', (tester) async {
    loadWhatsNewMarkdown = () async => sample;
    final (s, ctx) = await setup(tester, {'e-layout:whats_new_seen': '1.1.0'});
    await tester.runAsync(() => showWhatsNewIfUpdated(ctx, s, version: '1.1.0'));
    await tester.pump();
    expect(find.textContaining("What's new in"), findsNothing);
  });

  testWidgets('a loader that throws shows nothing and does not crash', (tester) async {
    loadWhatsNewMarkdown = () async => throw Exception('no asset');
    final (s, ctx) = await setup(tester, {'e-layout:whats_new_seen': '1.0.0'});
    await tester.runAsync(() => showWhatsNewIfUpdated(ctx, s, version: '1.1.0'));
    await tester.pump();
    expect(find.textContaining("What's new in"), findsNothing);
  });
}
