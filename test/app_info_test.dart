import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/app_info.dart';

void main() {
  test('the version constants equal pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!;
    expect(m.group(1), '$kAppVersion+$kAppBuild');
  });

  test('the app is called e-Layout', () => expect(kAppName, 'e-Layout'));
}
