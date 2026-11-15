import 'dart:typed_data';

import 'temp_files_memory.dart' if (dart.library.io) 'temp_files_io.dart' as impl;

/// A scratch folder for files handed to the share sheet (saved photos,
/// exported layouts). Each [clear] starts a new batch.
abstract class TempFiles {
  /// Writes [bytes] as [name] in the folder [group] and returns its path.
  Future<String> write(String group, String name, Uint8List bytes);

  /// Deletes everything in [group].
  Future<void> clear(String group);
}

TempFiles createTempFiles() => impl.createTempFiles();
