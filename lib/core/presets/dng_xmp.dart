import 'dart:convert';
import 'dart:typed_data';

final _open = ascii.encode('<x:xmpmeta');
final _close = ascii.encode('</x:xmpmeta>');

int _find(Uint8List data, List<int> needle, int from) {
  final first = needle[0];
  final last = data.length - needle.length;
  for (var i = from; i <= last; i++) {
    if (data[i] != first) continue;
    var k = 1;
    while (k < needle.length && data[i + k] == needle[k]) {
      k++;
    }
    if (k == needle.length) return i;
  }
  return -1;
}

/// The packet is bigger than the allowed size.
class XmpTooBig implements Exception {
  const XmpTooBig();
}

/// The first `<x:xmpmeta` to `</x:xmpmeta>` packet in a DNG (or any file),
/// as text, or null if there is none.
String? extractXmpPacket(Uint8List data, {int? maxBytes}) {
  final start = _find(data, _open, 0);
  if (start < 0) return null;
  final end = _find(data, _close, start);
  if (end < 0) return null;
  if (maxBytes != null && end + _close.length - start > maxBytes) {
    throw const XmpTooBig();
  }
  return utf8.decode(
    Uint8List.sublistView(data, start, end + _close.length),
    allowMalformed: true,
  );
}
