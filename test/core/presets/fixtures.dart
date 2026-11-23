// Builds preset files as strings and bytes. The structure mirrors what
// Lightroom writes; every name, id and value here is made up for tests.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pio_photo_layout/core/develop/profile_table.dart';

import 'adobe_table_encoder.dart';

const presetUuid = '11111111111111111111111111111111';
const lookUuid = '22222222222222222222222222222222';

/// A small made-up colour table that warms the image a little.
ProfileTable warmTable() {
  final t = ProfileTable.identity(5);
  for (var i = 0; i < t.rgb.length; i += 3) {
    t.rgb[i] = (t.rgb[i] * 1.1).clamp(0.0, 1.0);
  }
  return t;
}

({String text, String id}) warmTableText() => encodeAdobeTable(warmTable());

String _alt(String tag, String text) =>
    '<crs:$tag><rdf:Alt><rdf:li xml:lang="x-default">$text</rdf:li></rdf:Alt>'
    '</crs:$tag>';

String _seq(String tag, List<String> items) =>
    '<crs:$tag><rdf:Seq>${items.map((i) => '<rdf:li>$i</rdf:li>').join()}'
    '</rdf:Seq></crs:$tag>';

/// A "Normal" preset in the structure Lightroom writes: attributes for the
/// numbers, child elements for names, curves and the look reference.
String presetXmp({
  String name = 'Soft Test',
  String uuid = presetUuid,
  String processVersion = '15.4',
  String attrs = '',
  String children = '',
  String? look =
      '<crs:Look><rdf:Description crs:Name="Test Look" crs:Amount="0.5" '
      'crs:UUID="$lookUuid" crs:Stubbed="true"/></crs:Look>',
  bool withUuid = true,
  bool hasSettings = true,
  String pointColors = '-1.000000, -1.000000, -1.000000, -1.000000',
}) =>
    '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
   crs:PresetType="Normal"
   ${withUuid ? 'crs:UUID="$uuid"' : ''}
   crs:ProcessVersion="$processVersion"
   crs:Exposure2012="+0.50"
   crs:Contrast2012="0"
   crs:Highlights2012="-10"
   crs:Shadows2012="+20"
   crs:Saturation="-5"
   crs:ParametricShadowSplit="2"
   crs:SharpenRadius="+1.0"
   crs:Blacks2012="-0"
   crs:GrainAmount="45"
   crs:HueAdjustmentRed="+22"
   crs:Temperature="5200"
   crs:Tint="+3"
   crs:WhiteBalance="Custom"
   crs:SomethingNew2031="9"
   $attrs
   ${hasSettings ? 'crs:HasSettings="True"' : ''}>
   ${_alt('Name', name)}
   ${_seq('ToneCurvePV2012', ['3, 19', '34, 58', '115, 126', '255, 255'])}
   ${_seq('ToneCurvePV2012Red', ['0, 0', '255, 255'])}
   ${_seq('PointColors', [pointColors])}
   <crs:FilterList rdf:parseType="Resource"><crs:Filters><rdf:Seq>
    <rdf:li crs:FilterID="1" crs:CompressedSettings="ABCDEF"/>
   </rdf:Seq></crs:Filters></crs:FilterList>
   $children
   ${look ?? ''}
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';

/// A "Look" file: a colour profile with its table.
String lookXmp({
  String name = 'Test Look',
  String uuid = lookUuid,
  String? tableId,
  String? tableText,
}) {
  final t = tableText == null ? warmTableText() : null;
  final id = tableId ?? t!.id;
  final text = tableText ?? t!.text;
  return '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
   crs:PresetType="Look"
   crs:UUID="$uuid"
   crs:ProcessVersion="15.4"
   crs:RGBTable="$id"
   crs:Table_$id="$text"
   crs:HasSettings="True">
   ${_alt('Name', name)}
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';
}

/// The Lua-style table older Lightroom versions write.
String lrtemplate({
  String title = 'Old Style',
  String id = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
  String extra = '',
}) =>
    '''-- a comment
s = {
	id = "$id",
	internalName = "$title",
	title = "$title",
	type = "Develop",
	value = {
		settings = {
			Blacks2012 = -16,
			CameraProfile = "Adobe Standard",
			ConvertToGrayscale = true,
			Exposure2012 = 0.25,
			Highlights2012 = -64,
			ProcessVersion = "10.0",
			Saturation = 4,
			Shadows2012 = 41,
			SharpenRadius = 1,
			ToneCurveName2012 = "Custom",
			ToneCurvePV2012 = {
				0,
				10,
				128,
				140,
				255,
				255,
			},
			ToneCurvePV2012Blue = {
				0,
				0,
				255,
				255,
			},
			$extra
			orientation = "AB",
		},
		uuid = "C3498E38-D949-4F79-93A6-C18899D6BC36",
	},
	version = 0,
}
''';

/// A fake DNG: TIFF header bytes, an XMP packet, trailing bytes.
Uint8List fakeDng(String packet) {
  final b = BytesBuilder()
    ..add([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0])
    ..add(List<int>.generate(300, (i) => (i * 37) & 0xFF))
    ..add(utf8.encode('<?xpacket begin="" id="x"?>'))
    ..add(utf8.encode(packet))
    ..add(utf8.encode('<?xpacket end="w"?>'))
    ..add(List<int>.generate(300, (i) => 255 - (i & 0xFF)));
  return b.toBytes();
}

Uint8List zipOf(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((n, d) => a.addFile(ArchiveFile(n, d.length, d)));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
