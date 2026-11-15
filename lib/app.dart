import 'package:flutter/cupertino.dart';

import 'app_info.dart';
import 'ui/app_theme.dart';

/// The app shell: Cupertino, light or dark following the phone.
class PioApp extends StatefulWidget {
  const PioApp({super.key, required this.home, this.brightness});

  final Widget home;

  /// Forces light or dark (tests); null follows the phone.
  final Brightness? brightness;

  @override
  State<PioApp> createState() => _PioAppState();
}

class _PioAppState extends State<PioApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness ?? WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return CupertinoApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: appTheme(b),
      home: widget.home,
    );
  }
}
