import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'temp_files.dart';

class IoTempFiles implements TempFiles {
  IoTempFiles([this._root]);

  /// For tests; otherwise the app's temporary folder.
  final Directory? _root;

  Future<Directory> _dir(String group) async {
    final base = _root ?? await getTemporaryDirectory();
    return Directory(p.join(base.path, 'pio', group));
  }

  @override
  Future<String> write(String group, String name, Uint8List bytes) async {
    final dir = await _dir(group);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> clear(String group) async {
    final dir = await _dir(group);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

TempFiles createTempFiles() => IoTempFiles();
