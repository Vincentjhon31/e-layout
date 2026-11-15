import 'dart:typed_data';

import 'temp_files.dart';

/// Keeps files in memory (web and tests). Paths are made-up names.
class MemoryTempFiles implements TempFiles {
  final Map<String, Map<String, Uint8List>> groups = {};

  @override
  Future<String> write(String group, String name, Uint8List bytes) async {
    (groups[group] ??= {})[name] = bytes;
    return 'memory/$group/$name';
  }

  @override
  Future<void> clear(String group) async => groups.remove(group);
}

TempFiles createTempFiles() => MemoryTempFiles();
