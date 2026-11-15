import 'dart:typed_data';

import 'package:gal/gal.dart';

abstract class GallerySaver {
  /// Saves one picture under [fileName] (with its extension). Returns where it
  /// went when that is a file on this computer (so it can be shown in its
  /// folder), otherwise null. Throws [SaveCancelledException] when the person
  /// backs out of a dialog and [SaveStoppedException] when a batch cannot go on.
  Future<String?> saveImage(Uint8List bytes, String fileName);

  /// Where saved pictures end up, for messages ("Photos, album e-Layout").
  String get destinationLabel;

  /// Called once before a batch of [count] photos. A computer asks for a
  /// folder here; false means the person cancelled and nothing starts.
  Future<bool> beginBatch(int count) async => true;

  /// Called once after the batch. [keep] is false when it was cancelled.
  Future<void> endBatch({required bool keep}) async {}

  /// The line after a finished batch.
  String resultLine(int saved, String size) =>
      'Saved ${saved == 1 ? '1 photo' : '$saved photos'} to $destinationLabel ($size).';

  /// The line after a cancelled batch.
  String cancelledLine(int saved) => saved == 0
      ? 'Cancelled. Nothing was saved.'
      : 'Cancelled. ${saved == 1 ? '1 photo was' : '$saved photos were'} already saved to $destinationLabel.';

  /// The line after one photo from the viewer.
  String savedOneLine(String name) => 'Saved $name to $destinationLabel.';
}

/// The person closed a save dialog without choosing a place.
class SaveCancelledException implements Exception {
  const SaveCancelledException();
  @override
  String toString() => 'Cancelled.';
}

/// A batch cannot go on (a ZIP that is full, no room left). Photos saved so
/// far are kept and counted.
class SaveStoppedException implements Exception {
  const SaveStoppedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The phone's gallery, album "e-Layout". gal names the file
/// `<name>.<extension detected from the bytes>`; Android adds a number when a
/// file of that name is already in the album.
class PhoneGallerySaver extends GallerySaver {
  static const String album = 'e-Layout';

  @override
  String get destinationLabel => 'Photos, album $album';

  @override
  Future<String?> saveImage(Uint8List bytes, String fileName) async {
    if (!await Gal.hasPermission(toAlbum: true)) {
      if (!await Gal.requestPermission(toAlbum: true)) {
        throw const GalleryAccessException();
      }
    }
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;
    await Gal.putImageBytes(bytes, album: album, name: name);
    return null;
  }
}

class GalleryAccessException implements Exception {
  const GalleryAccessException();
  @override
  String toString() => "e-Layout isn't allowed to add pictures to Photos. Allow it in the phone settings.";
}

/// Records what would be saved, for tests.
class FakeGallerySaver extends GallerySaver {
  final List<String> names = [];
  final List<Uint8List> files = [];

  /// Called before each save; throw from it to simulate a failure.
  void Function(String name)? before;

  @override
  String get destinationLabel => 'Photos, album e-Layout';

  @override
  Future<String?> saveImage(Uint8List bytes, String fileName) async {
    before?.call(fileName);
    names.add(fileName);
    files.add(bytes);
    return null;
  }
}
