import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// A ZIP bigger than this needs the ZIP64 extension, which this writer (and
/// the web app's) doesn't do. app.js: "ZIP limit 4 GB".
const int kZipLimit = 0xFFFFFFFF - 1024 * 1024;

class ZipTooLargeException implements Exception {
  const ZipTooLargeException();
  @override
  String toString() => zipTooLargeMessage;
}

/// The web app's wording.
const String zipTooLargeMessage =
    'This batch is too big for one ZIP (over 4 GB). Save the photos in smaller groups.';

/// Writes a ZIP whose entries are stored, not compressed (JPEGs do not shrink),
/// and keeps the entries' bytes where they are instead of copying them, so a
/// big batch takes about its own size in memory once.
class ZipWriter {
  ZipWriter({this.limit = kZipLimit});

  /// The archive may not grow past this many bytes.
  final int limit;

  final List<Uint8List> _parts = [];
  final List<_Entry> _entries = [];
  int _size = 0;

  int get length => _size;
  int get count => _entries.length;

  /// Bytes the central directory would add for what is in the archive now.
  int get _tail => 22 + _entries.fold<int>(0, (n, e) => n + 46 + e.name.length);

  void add(String name, Uint8List bytes, DateTime modified) {
    final nameBytes = Uint8List.fromList(utf8.encode(name));
    final header = 30 + nameBytes.length;
    final tail = _tail + 46 + nameBytes.length;
    if (_size + header + bytes.length + tail > limit) throw const ZipTooLargeException();
    final crc = getCrc32(bytes);
    final (time, date) = _dosTime(modified);
    final h = ByteData(30);
    h.setUint32(0, 0x04034b50, Endian.little);
    h.setUint16(4, 20, Endian.little); // version needed
    h.setUint16(6, 0x0800, Endian.little); // names are UTF-8
    h.setUint16(8, 0, Endian.little); // stored
    h.setUint16(10, time, Endian.little);
    h.setUint16(12, date, Endian.little);
    h.setUint32(14, crc, Endian.little);
    h.setUint32(18, bytes.length, Endian.little);
    h.setUint32(22, bytes.length, Endian.little);
    h.setUint16(26, nameBytes.length, Endian.little);
    h.setUint16(28, 0, Endian.little);
    _entries.add(_Entry(name, nameBytes, crc, bytes.length, time, date, _size));
    _parts
      ..add(h.buffer.asUint8List())
      ..add(nameBytes)
      ..add(bytes);
    _size += header + bytes.length;
  }

  /// The finished archive as pieces, to be joined by whoever consumes it
  /// (a browser Blob does that without copying).
  List<Uint8List> finishParts() {
    final centralStart = _size;
    var centralSize = 0;
    final out = [..._parts];
    for (final e in _entries) {
      final c = ByteData(46);
      c.setUint32(0, 0x02014b50, Endian.little);
      c.setUint16(4, 20, Endian.little); // made by
      c.setUint16(6, 20, Endian.little); // needed
      c.setUint16(8, 0x0800, Endian.little);
      c.setUint16(10, 0, Endian.little);
      c.setUint16(12, e.time, Endian.little);
      c.setUint16(14, e.date, Endian.little);
      c.setUint32(16, e.crc, Endian.little);
      c.setUint32(20, e.size, Endian.little);
      c.setUint32(24, e.size, Endian.little);
      c.setUint16(28, e.nameBytes.length, Endian.little);
      c.setUint32(42, e.offset, Endian.little);
      out
        ..add(c.buffer.asUint8List())
        ..add(e.nameBytes);
      centralSize += 46 + e.nameBytes.length;
    }
    final end = ByteData(22);
    end.setUint32(0, 0x06054b50, Endian.little);
    end.setUint16(8, _entries.length, Endian.little);
    end.setUint16(10, _entries.length, Endian.little);
    end.setUint32(12, centralSize, Endian.little);
    end.setUint32(16, centralStart, Endian.little);
    out.add(end.buffer.asUint8List());
    return out;
  }

  /// The finished archive in one piece.
  Uint8List finish() {
    final parts = finishParts();
    final total = parts.fold<int>(0, (n, e) => n + e.length);
    final out = Uint8List(total);
    var at = 0;
    for (final part in parts) {
      out.setRange(at, at + part.length, part);
      at += part.length;
    }
    return out;
  }

  static (int time, int date) _dosTime(DateTime d) {
    final year = (d.year - 1980).clamp(0, 127);
    return ((d.hour << 11) | (d.minute << 5) | (d.second ~/ 2), (year << 9) | (d.month << 5) | d.day);
  }
}

class _Entry {
  _Entry(this.name, this.nameBytes, this.crc, this.size, this.time, this.date, this.offset);
  final String name;
  final Uint8List nameBytes;
  final int crc, size, time, date, offset;
}
