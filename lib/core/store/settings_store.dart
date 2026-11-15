import 'package:shared_preferences/shared_preferences.dart';

import '../export/photo_exporter.dart';

class AppSettings {
  AppSettings({
    this.layoutId,
    this.format = OutputFormat.jpeg,
    this.quality = 92,
    this.suffix = '_PIO',
  });
  String? layoutId;
  OutputFormat format;
  int quality;
  String suffix;
}

/// Options that last between visits, in shared_preferences.
class SettingsStore {
  static const _kLayout = 'pio-photo-layout:layoutId';
  static const _kFormat = 'pio-photo-layout:format';
  static const _kQuality = 'pio-photo-layout:quality';
  static const _kSuffix = 'pio-photo-layout:suffix';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      layoutId: p.getString(_kLayout),
      format: p.getString(_kFormat) == 'png' ? OutputFormat.png : OutputFormat.jpeg,
      quality: (p.getInt(_kQuality) ?? 92).clamp(1, 100),
      suffix: p.getString(_kSuffix) ?? '_PIO',
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    if (s.layoutId == null) {
      await p.remove(_kLayout);
    } else {
      await p.setString(_kLayout, s.layoutId!);
    }
    await p.setString(_kFormat, s.format.name);
    await p.setInt(_kQuality, s.quality);
    await p.setString(_kSuffix, s.suffix);
  }

  /// A small string kept between visits ('whats_new_seen', 'update_prompted').
  Future<String?> readValue(String key) async => (await SharedPreferences.getInstance()).getString('e-layout:$key');

  /// Saves [value] under [key]; null removes it.
  Future<void> writeValue(String key, String? value) async {
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove('e-layout:$key');
    } else {
      await p.setString('e-layout:$key', value);
    }
  }
}
