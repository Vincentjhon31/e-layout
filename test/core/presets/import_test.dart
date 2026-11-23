import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/develop/settings.dart';
import 'package:pio_photo_layout/core/presets/preset.dart';
import 'package:pio_photo_layout/core/presets/preset_import.dart';

import 'fixtures.dart';

typedef F = (String, Uint8List);

F f(String name, String content) => (name, bytes(content));

const missing =
    ' "Soft Test" needs the profile "Test Look". Import that file too, and it '
    'will be picked up.';
const older =
    ' Made for an older Lightroom, so it may look a little different.';

void main() {
  test('xmp preset maps values, curves and the profile reference', () {
    final r = importPresetFiles([f('a.xmp', presetXmp())]);
    expect(r.presets, hasLength(1));
    final p = r.presets.single;
    expect(p.id, presetUuid);
    expect(p.name, 'Soft Test');
    expect(p.kind, PresetKind.imported);
    final v = p.patch.values;
    expect(v[Setting.exposure], 0.5);
    expect(v[Setting.contrast], 0);
    expect(v[Setting.highlights], -10);
    expect(v[Setting.shadows], 20);
    expect(v[Setting.saturation], -5);
    expect(v[Setting.curveShadowSplit], 5); // 2 clamped to the range
    expect(v[Setting.grainAmount], 45);
    expect(v[Setting.hueRed], 22);
    expect(p.patch.curves[CurveChannel.master], const [
      CurvePoint(3, 19),
      CurvePoint(34, 58),
      CurvePoint(115, 126),
      CurvePoint(255, 255),
    ]);
    expect(p.patch.curves[CurveChannel.red], const [
      CurvePoint(0, 0),
      CurvePoint(255, 255),
    ]);
    expect(p.patch.profile, const ProfileRef(lookUuid, 'Test Look', 0.5));
    expect(p.patch.grayscale, isNull);
    expect(p.patch.extras, {
      'Temperature': '5200',
      'Tint': '+3',
      'WhiteBalance': 'Custom',
    });
    expect(r.profiles, isEmpty);
    // The FilterList and all-minus-one PointColors are not reported.
    expect(r.line, 'Imported "Soft Test".$missing');
  });

  test('preset and its profile in one import link by UUID', () {
    for (final order in [
      [f('look.xmp', lookXmp()), f('a.xmp', presetXmp())],
      [f('a.xmp', presetXmp()), f('look.xmp', lookXmp())],
    ]) {
      final r = importPresetFiles(order);
      expect(r.presets, hasLength(1));
      expect(r.profiles, hasLength(1));
      final pr = r.profiles.single;
      expect(pr.id, lookUuid);
      expect(pr.name, 'Test Look');
      expect(pr.table.size, 5);
      expect(r.presets.single.patch.profile!.id, lookUuid);
      expect(r.line, isNot(contains('needs the profile')));
      expect(r.line, 'Imported "Soft Test". Imported the profile "Test Look".');
    }
  });

  test('profile imported later links to the waiting preset by UUID, '
      'then by name', () {
    final first = importPresetFiles([f('a.xmp', presetXmp())]);
    expect(first.line, contains('needs the profile'));
    expect(first.presets.single.patch.profile!.id, lookUuid);

    final prof = importPresetFiles([f('look.xmp', lookXmp())]);
    expect(prof.presets, isEmpty);
    expect(prof.line, 'Imported the profile "Test Look".');
    final known = {for (final p in prof.profiles) p.id: p};

    final byUuid = importPresetFiles([f('a.xmp', presetXmp())], known: known);
    expect(byUuid.line, 'Imported "Soft Test".');
    expect(byUuid.presets.single.patch.profile!.id, lookUuid);

    // Same name, different UUID: linked by name, and the id follows the
    // profile that was found.
    final other = Profile(
      id: 'OTHERID',
      name: 'test look',
      table: prof.profiles.single.table,
    );
    final byName = importPresetFiles(
      [f('a.xmp', presetXmp())],
      known: {'OTHERID': other},
    );
    expect(byName.line, 'Imported "Soft Test".');
    final ref = byName.presets.single.patch.profile!;
    expect(ref.id, 'OTHERID');
    expect(ref.amount, 0.5);
  });

  test('missing profile line', () {
    final r = importPresetFiles([f('a.xmp', presetXmp())]);
    expect(r.line, 'Imported "Soft Test".$missing');
    expect(r.presets.single.patch.profile!.name, 'Test Look');
  });

  test('lrtemplate maps the same fields', () {
    final r = importPresetFiles([
      f(
        'old.lrtemplate',
        lrtemplate(extra: 'ToneCurvePV2012Red = { 0, 0, 100, 120, 255, 255 },'),
      ),
    ]);
    final p = r.presets.single;
    expect(p.name, 'Old Style');
    expect(p.id, 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE');
    expect(p.patch.values[Setting.exposure], 0.25);
    expect(p.patch.values[Setting.shadows], 41);
    expect(p.patch.values[Setting.highlights], -64);
    expect(p.patch.values[Setting.saturation], 4);
    expect(p.patch.values[Setting.sharpenRadius], 1);
    expect(p.patch.values[Setting.blacks], -16);
    expect(p.patch.grayscale, isTrue);
    expect(p.patch.curves[CurveChannel.master], const [
      CurvePoint(0, 10),
      CurvePoint(128, 140),
      CurvePoint(255, 255),
    ]);
    expect(p.patch.curves[CurveChannel.red], const [
      CurvePoint(0, 0),
      CurvePoint(100, 120),
      CurvePoint(255, 255),
    ]);
    expect(p.patch.curves[CurveChannel.blue], const [
      CurvePoint(0, 0),
      CurvePoint(255, 255),
    ]);
    expect(p.patch.curves.containsKey(CurveChannel.green), isFalse);
    expect(p.patch.profile, isNull);
    expect(r.line, 'Imported "Old Style".');
  });

  test('dng: settings come from the embedded packet', () {
    final r = importPresetFiles([
      ('photo.dng', fakeDng(presetXmp(look: null))),
    ]);
    expect(r.presets, hasLength(1));
    expect(r.presets.single.name, 'Soft Test');
    expect(r.presets.single.patch.values[Setting.shadows], 20);
    expect(r.line, 'Imported "Soft Test".');

    // No settings in the packet, or no packet at all: nothing found.
    final none = importPresetFiles([
      (
        'nothing.dng',
        fakeDng('<x:xmpmeta xmlns:x="adobe:ns:meta/"></x:xmpmeta>'),
      ),
      ('plain.dng', Uint8List.fromList(List.filled(64, 7))),
    ]);
    expect(none.line, 'No Lightroom presets found in these files.');
  });

  test('zip: macOS leftovers ignored, one bad file does not stop the rest', () {
    final z = zipOf({
      '__MACOSX/pack/._a.xmp': [1, 2, 3, 4],
      'pack/.DS_Store': [0, 0, 0, 1],
      'pack/._b.xmp': presetXmp(name: 'Ghost', uuid: 'G').codeUnits,
      '__MACOSX/pack/c.xmp': presetXmp(name: 'Ghost2', uuid: 'H').codeUnits,
      'pack/bad.xmp': 'this is <not xml'.codeUnits,
      'pack/a.xmp': presetXmp(look: null).codeUnits,
      'pack/old.lrtemplate': lrtemplate().codeUnits,
      'pack/readme.txt': 'hello'.codeUnits,
    });
    final r = importPresetFiles([('pack.zip', z)]);
    expect(
      r.presets.map((p) => p.name),
      unorderedEquals(['Soft Test', 'Old Style']),
    );
    expect(r.line, 'Imported 2 presets.');
  });

  test('a corrupt zip is skipped', () {
    final r = importPresetFiles([
      ('x.zip', Uint8List.fromList(List.generate(200, (i) => i))),
      f('a.xmp', presetXmp(look: null)),
    ]);
    expect(r.presets, hasLength(1));
  });

  test('unknown crs fields ignored; "+1.0", "-0" and fractions parse', () {
    const lean =
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description '
        'xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" '
        'crs:HasSettings="True" crs:Exposure2012="1/2" crs:Dehaze="abc" '
        'crs:Clarity2012="500" crs:Vibrance="-0" crs:Texture="+1.0" '
        'crs:Unknown="1" crs:Defringe="0"/></rdf:RDF></x:xmpmeta>';
    final r = importPresetFiles([f('lean.xmp', lean)]);
    final p = r.presets.single;
    expect(p.name, 'lean');
    final v = p.patch.values;
    expect(v[Setting.exposure], 0.5);
    expect(v.containsKey(Setting.dehaze), isFalse);
    expect(v[Setting.clarity], 100);
    expect(v[Setting.vibrance], 0);
    expect(v[Setting.vibrance]!.isNegative, isFalse);
    expect(v[Setting.texture], 1.0);
    expect(v.length, 4);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(p.id), isTrue);
    expect(r.line, 'Imported "lean".');
  });

  test('the full preset also parses "+1.0" and "-0"', () {
    final v = importPresetFiles([
      f('a.xmp', presetXmp(look: null)),
    ]).presets.single.patch.values;
    expect(v[Setting.sharpenRadius], 1.0);
    expect(v[Setting.blacks], 0);
    expect(v[Setting.blacks]!.isNegative, isFalse);
  });

  test('amount is stored as is and clamped to 0..2', () {
    final r = importPresetFiles([
      f(
        'a.xmp',
        presetXmp(
          look:
              '<crs:Look><rdf:Description crs:Name="L" crs:Amount="3" '
              'crs:UUID="$lookUuid" crs:Stubbed="true"/></crs:Look>',
        ),
      ),
    ]);
    expect(r.presets.single.patch.profile!.amount, 2.0);
  });

  test('not carried over lists masks and lens corrections in order', () {
    // The attributes are written in reverse of the reported order.
    final r = importPresetFiles([
      f(
        'a.xmp',
        presetXmp(
          look: null,
          attrs:
              'crs:HasCrop="True" crs:CameraProfile="Camera Faithful" '
              'crs:RedHue="5" crs:PerspectiveVertical="-3" '
              'crs:LensProfileEnable="1"',
          pointColors: '-1.000000, 0.5, -1.000000',
          children:
              '<crs:GradientBasedCorrections><rdf:Seq><rdf:li crs:What="x"/>'
              '</rdf:Seq></crs:GradientBasedCorrections>',
        ),
      ),
    ]);
    expect(
      r.line,
      'Imported "Soft Test". Not carried over: masks, lens corrections, '
      'perspective, calibration, point colour, camera profile, crop.',
    );
  });

  test('neutral or ordinary values are not reported', () {
    final r = importPresetFiles([
      f(
        'a.xmp',
        presetXmp(
          look: null,
          attrs:
              'crs:HasCrop="False" crs:CameraProfile="Adobe Color" '
              'crs:RedHue="0" crs:PerspectiveVertical="0" '
              'crs:LensProfileEnable="0" crs:AutoLateralCA="0" '
              'crs:Defringe="0" crs:LensManualDistortionAmount="0" '
              'crs:VignetteAmount="0"',
          children:
              '<crs:MaskGroupBasedCorrections><rdf:Seq/>'
              '</crs:MaskGroupBasedCorrections>',
        ),
      ),
    ]);
    expect(r.line, 'Imported "Soft Test".');
  });

  test('lens corrections alone, from an lrtemplate', () {
    final r = importPresetFiles([
      f('t.lrtemplate', lrtemplate(extra: 'AutoLateralCA = 1,')),
    ]);
    expect(r.line, 'Imported "Old Style". Not carried over: lens corrections.');
  });

  test('process version 6.7 adds the older-Lightroom line', () {
    final r = importPresetFiles([
      f('a.xmp', presetXmp(look: null, processVersion: '6.7')),
    ]);
    expect(r.line, 'Imported "Soft Test".$older');
  });

  test('same UUID twice gives one preset', () {
    final r = importPresetFiles([
      f('a.xmp', presetXmp(name: 'First', look: null)),
      f('b.xmp', presetXmp(name: 'Second', look: null)),
      (
        'c.zip',
        zipOf({'d.xmp': presetXmp(name: 'Third', look: null).codeUnits}),
      ),
    ]);
    expect(r.presets, hasLength(1));
    expect(r.presets.single.name, 'First');
    expect(r.line, 'Imported "First".');
  });

  test('presets without a uuid get distinct random ids', () {
    final r = importPresetFiles([
      f('a.xmp', presetXmp(name: 'A', withUuid: false, look: null)),
      f('b.xmp', presetXmp(name: 'B', withUuid: false, look: null)),
    ]);
    expect(r.presets, hasLength(2));
    expect(r.presets[0].id, isNot(r.presets[1].id));
    expect(r.line, 'Imported 2 presets.');
  });

  test('a text file gives "No Lightroom presets found in these files."', () {
    final r = importPresetFiles([
      f('notes.txt', 'hello'),
      f('broken.xmp', 'hello'),
      f('broken.lrtemplate', 's = { oops'),
      f('empty.xmp', presetXmp(hasSettings: false, look: null)),
    ]);
    expect(r.presets, isEmpty);
    expect(r.profiles, isEmpty);
    expect(r.line, 'No Lightroom presets found in these files.');
  });

  test('a look whose table cannot be read is reported', () {
    final t = warmTableText();
    final bad = lookXmp(
      tableId: '00000000000000000000000000000000',
      tableText: t.text,
    );
    final r = importPresetFiles([f('look.xmp', bad)]);
    expect(r.profiles, isEmpty);
    expect(r.line, "The profile \"Test Look\" can't be read.");
    // The preset that points at it gets no missing-profile line.
    final both = importPresetFiles([
      f('look.xmp', bad),
      f('a.xmp', presetXmp()),
    ]);
    expect(
      both.line,
      "Imported \"Soft Test\". The profile \"Test Look\" can't be read.",
    );
    expect(both.presets.single.patch.profile!.id, lookUuid);
  });

  test('same preset in xmp and lrtemplate keeps the xmp one', () {
    final r = importPresetFiles([
      f('old.lrtemplate', lrtemplate(title: 'Soft Test')),
      f('a.xmp', presetXmp(look: null)),
    ]);
    expect(r.presets, hasLength(1));
    expect(r.presets.single.id, presetUuid);
    expect(r.line, 'Imported "Soft Test".');
    // A different name is kept.
    final two = importPresetFiles([
      f('old.lrtemplate', lrtemplate()),
      f('a.xmp', presetXmp(look: null)),
    ]);
    expect(two.presets, hasLength(2));
  });

  test('a non-stubbed look with its own table also yields a profile', () {
    final t = warmTableText();
    final r = importPresetFiles([
      f(
        'a.xmp',
        presetXmp(
          look:
              '<crs:Look><rdf:Description crs:Name="Own" crs:Amount="1" '
              'crs:UUID="$lookUuid" crs:RGBTable="${t.id}" '
              'crs:Table_${t.id}="${t.text}"/></crs:Look>',
        ),
      ),
    ]);
    expect(r.profiles.single.name, 'Own');
    expect(r.profiles.single.id, lookUuid);
    expect(r.presets.single.patch.profile!.id, lookUuid);
    expect(r.line, isNot(contains('needs the profile')));
  });

  test('crs:ConvertToGrayscale sets grayscale', () {
    final r = importPresetFiles([
      f('a.xmp', presetXmp(look: null, attrs: 'crs:ConvertToGrayscale="True"')),
    ]);
    expect(r.presets.single.patch.grayscale, isTrue);
  });

  group('size caps and hostile input', () {
    const tooBig = ' Some files were too big to read.';

    test('a zip with more than 500 entries stops reading at 500', () {
      final files = <String, List<int>>{
        'a.xmp': presetXmp(look: null).codeUnits,
        for (var i = 0; i < 600; i++) 'f$i.txt': [1],
      };
      final r = importPresetFiles([('many.zip', zipOf(files))]);
      expect(r.presets, hasLength(1));
      expect(r.line, 'Imported "Soft Test".$tooBig');
    });

    test('a zip over the total size cap skips the rest', () {
      // One 8 MB buffer shared by every entry: tiny once compressed.
      final block = Uint8List(8 * 1024 * 1024);
      final files = <String, List<int>>{
        'a.xmp': presetXmp(look: null).codeUnits,
        for (var i = 0; i < 34; i++) 'f$i.lrtemplate': block,
      };
      final r = importPresetFiles([('huge.zip', zipOf(files))]);
      expect(r.presets, hasLength(1));
      expect(r.line, 'Imported "Soft Test".$tooBig');
    });

    test('a zip entry over the entry cap is skipped, the rest read', () {
      final z = zipOf({
        'big.xmp': Uint8List(8 * 1024 * 1024 + 1),
        'a.xmp': presetXmp(look: null).codeUnits,
      });
      final r = importPresetFiles([('p.zip', z)]);
      expect(r.presets, hasLength(1));
      expect(r.line, 'Imported "Soft Test".$tooBig');
    });

    test('an oversized top-level file is skipped', () {
      final r = importPresetFiles([
        ('big.xmp', Uint8List(8 * 1024 * 1024 + 1)),
        ('big.lrtemplate', Uint8List(8 * 1024 * 1024 + 1)),
      ]);
      expect(r.presets, isEmpty);
      expect(r.line, 'No Lightroom presets found in these files.$tooBig');
    });

    test('a dng whose xmp packet is over 2 MB is skipped', () {
      final pad = '<!--${'x' * (2 * 1024 * 1024 + 10)}-->';
      final r = importPresetFiles([
        ('p.dng', fakeDng(presetXmp(look: null, children: pad))),
      ]);
      expect(r.presets, isEmpty);
      expect(r.line, endsWith(tooBig));
    });

    test('5000-deep nested XML does not throw', () {
      final deep = '<crs:Deep>${'<a>' * 5000}${'</a>' * 5000}</crs:Deep>';
      late ImportResult r;
      expect(
        () => r = importPresetFiles([
          f('deep.xmp', presetXmp(look: null, children: deep)),
        ]),
        returnsNormally,
      );
      expect(r.line, isNotEmpty);
    });

    test('an lrtemplate nested deeper than 40 is skipped', () {
      final open = 'A = ${'{' * 60}';
      final close = '}' * 60;
      final r = importPresetFiles([
        f('d.lrtemplate', lrtemplate(extra: '$open$close,')),
      ]);
      expect(r.presets, isEmpty);
      expect(r.line, 'No Lightroom presets found in these files.');
    });

    test('a DOCTYPE entity is not expanded', () {
      final xml =
          '<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e "EXPANDED">]>'
          '${presetXmp(name: 'A &e; B', look: null)}';
      late ImportResult r;
      expect(() => r = importPresetFiles([f('e.xmp', xml)]), returnsNormally);
      expect(r.presets.single.name, 'A &e; B');
    });

    test('curve points are sorted by x, last one wins for a repeated x', () {
      final r = importPresetFiles([
        f(
          'c.xmp',
          presetXmp(
            look: null,
            children:
                '<crs:ToneCurvePV2012Green><rdf:Seq>'
                '<rdf:li>255, 250</rdf:li><rdf:li>100, 90</rdf:li>'
                '<rdf:li>0, 0</rdf:li><rdf:li>100, 110</rdf:li>'
                '</rdf:Seq></crs:ToneCurvePV2012Green>',
          ),
        ),
      ]);
      expect(r.presets.single.patch.curves[CurveChannel.green], const [
        CurvePoint(0, 0),
        CurvePoint(100, 110),
        CurvePoint(255, 250),
      ]);
    });
  });
}
