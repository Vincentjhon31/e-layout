import 'file_sharer.dart';
import 'gallery_saver.dart';
import 'photo_picker.dart';
import 'platform_services_web.dart' if (dart.library.io) 'platform_services_io.dart' as impl;

/// Which kind of device the app is running on.
enum DeviceKind { phone, windows, web }

/// The pieces that differ between the phone app, the Windows app and the website.
class PlatformServices {
  const PlatformServices({required this.kind, required this.picker, required this.saver, required this.sharer});

  final DeviceKind kind;
  final PhotoPicker picker;
  final GallerySaver saver;
  final FileSharer sharer;

  /// Drag and drop of photos and layout files works on Windows and the website.
  bool get canDrop => kind != DeviceKind.phone;

  /// Keyboard shortcuts and mouse wheel in the editor.
  bool get isDesktopLike => kind != DeviceKind.phone;

  /// "phone" or "computer", for messages.
  String get deviceNoun => kind == DeviceKind.phone ? 'phone' : 'computer';
}

PlatformServices createPlatformServices() => impl.createServices();
