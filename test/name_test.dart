import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/platform/gallery_saver.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Android label', () => expect(read('android/app/src/main/AndroidManifest.xml'), contains('android:label="e-Layout"')));

  test('website title and manifest', () {
    final html = read('web/index.html');
    expect(html, contains('<title>e-Layout</title>'));
    expect(html, contains('name="apple-mobile-web-app-title" content="e-Layout"'));
    final m = read('web/manifest.json');
    expect(m, contains('"name": "e-Layout"'));
    expect(m, contains('"short_name": "e-Layout"'));
    expect(m, contains('"theme_color": "#1A6FB3"'));
    expect(m, contains('"background_color": "#F2F2F7"'));
  });

  test('Windows window title and file properties', () {
    expect(read('windows/runner/main.cpp'), contains('window.Create(L"e-Layout"'));
    final rc = read('windows/runner/Runner.rc');
    expect(rc, contains('VALUE "ProductName", "e-Layout"'));
    expect(rc, contains('VALUE "FileDescription", "e-Layout"'));
    expect(rc, contains('VALUE "CompanyName", "Municipality of Bongabong"'));
    expect(rc, contains('VALUE "LegalCopyright", "Copyright (C) 2026 Municipality of Bongabong'));
  });

  test('installer script', () {
    final iss = read('windows/installer/e-layout.iss');
    expect(iss, contains('#define MyAppName "e-Layout"'));
    expect(iss, contains('#define MyAppExeName "pio_photo_layout.exe"'));
    expect(iss, contains('OutputBaseFilename=e-layout-{#MyAppVersion}-setup'));
  });

  test('the gallery album and its messages say e-Layout', () {
    expect(PhoneGallerySaver.album, 'e-Layout');
    expect(PhoneGallerySaver().destinationLabel, 'Photos, album e-Layout');
    expect(const GalleryAccessException().toString(),
        "e-Layout isn't allowed to add pictures to Photos. Allow it in the phone settings.");
  });

  test('no Dart file under lib says "Photo Layout"', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('Photo Layout')) bad.add('${f.path}:${i + 1}');
      }
    }
    expect(bad, isEmpty);
  });
}
