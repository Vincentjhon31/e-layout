import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Offline first: the code that adds, edits and saves photos must not even be
/// able to reach the network. Only a few named files may.
void main() {
  String rel(File f) => f.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^.*?lib/'), 'lib/');

  final files = [
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) f,
  ];

  const mayUseNetwork = [
    'lib/online/',
    'lib/platform/app_updater_io.dart',
    'lib/platform/web_version_web.dart',
    'lib/features/fonts/font_library.dart',
  ];
  const coreFiles = [
    'lib/core/',
    'lib/core/develop/',
    'lib/core/presets/',
    'lib/core/store/preset_store',
    'lib/core/store/batch_store',
    'lib/features/develop/',
    'lib/features/home/home_controller.dart',
    'lib/features/home/export_job.dart',
    'lib/features/editor/',
    'lib/features/viewer/',
    'lib/features/layouts/',
    'lib/platform/photo_picker.dart',
    'lib/platform/gallery_saver.dart',
    'lib/platform/file_sharer.dart',
    'lib/platform/temp_files',
    'lib/platform/file_output',
  ];
  const forbiddenFromCore = ['lib/online/', 'lib/features/about/', 'lib/features/templates/', 'lib/platform/app_updater'];

  bool inList(String path, List<String> list) => list.any(path.startsWith);

  test('only the named files import package:http or use HttpClient', () {
    final bad = <String>[];
    for (final f in files) {
      final path = rel(f);
      if (inList(path, mayUseNetwork)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        if (l.contains("package:http/") || l.contains('HttpClient') || l.contains('dart:html')) {
          bad.add('$path:${i + 1}: $l');
        }
      }
    }
    expect(bad, isEmpty, reason: 'These files may not use the network:\n${bad.join('\n')}');
  });

  test('the photo, editor and layout code never imports the online or update code', () {
    final bad = <String>[];
    for (final f in files) {
      final path = rel(f);
      if (!inList(path, coreFiles)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!l.trimLeft().startsWith('import ') && !l.trimLeft().startsWith('export ')) continue;
        for (final bannedPath in forbiddenFromCore) {
          final tail = bannedPath.replaceFirst('lib/', '');
          if (l.contains(tail) || l.contains('package:pio_photo_layout/$tail')) {
            bad.add('$path:${i + 1}: $l');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: 'These files may not import online code:\n${bad.join('\n')}');
  });
}
