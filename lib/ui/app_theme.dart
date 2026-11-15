import 'package:flutter/cupertino.dart';

/// The colour tokens of the design table, for light and dark.
@immutable
class AppColors {
  const AppColors({
    required this.page,
    required this.card,
    required this.raised,
    required this.text,
    required this.secondary,
    required this.separator,
    required this.accent,
    required this.destructive,
    required this.warningBg,
    required this.warningText,
    required this.onAccent,
  });

  final Color page;
  final Color card;
  final Color raised;
  final Color text;
  final Color secondary;
  final Color separator;
  final Color accent;
  final Color destructive;
  final Color warningBg;
  final Color warningText;

  /// Text and icons drawn on the accent colour.
  final Color onAccent;

  static const light = AppColors(
    page: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFEFEFF4),
    text: Color(0xFF111418),
    secondary: Color(0xFF5F6670),
    separator: Color(0xFFD9DCE1),
    accent: Color(0xFF1A6FB3),
    destructive: Color(0xFFC4291C),
    warningBg: Color(0xFFFFF4D6),
    warningText: Color(0xFF6B4E00),
    onAccent: Color(0xFFFFFFFF),
  );

  static const dark = AppColors(
    page: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    raised: Color(0xFF2C2C2E),
    text: Color(0xFFFFFFFF),
    secondary: Color(0xFFA1A1AA),
    separator: Color(0xFF38383A),
    accent: Color(0xFF5CB8FF),
    destructive: Color(0xFFFF6B5E),
    warningBg: Color(0xFF3A2F0B),
    warningText: Color(0xFFFFD970),
    onAccent: Color(0xFF00203A),
  );

  bool get isDark => page == dark.page;

  /// Background of bottom sheets: grouped grey in light, graphite in dark.
  Color get sheet => isDark ? card : page;

  /// Cards and grouped rows: one step lighter than what they sit on.
  Color cardIn(BuildContext context) => isDark && InSheet.of(context) ? raised : card;

  static Brightness brightnessOf(BuildContext context) =>
      CupertinoTheme.maybeBrightnessOf(context) ??
      MediaQuery.maybePlatformBrightnessOf(context) ??
      Brightness.light;

  static AppColors of(BuildContext context) =>
      brightnessOf(context) == Brightness.dark ? dark : light;
}

/// Marks widgets inside a bottom sheet (cards there use a lighter surface in dark).
class InSheet extends InheritedWidget {
  const InSheet({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<InSheet>() != null;

  @override
  bool updateShouldNotify(InSheet oldWidget) => false;
}

/// UI type: Inter, sizes from the design section.
abstract final class AppText {
  static const String family = 'Inter';
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle largeTitle = TextStyle(
      fontFamily: family, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.15);
  static const TextStyle title = TextStyle(
      fontFamily: family, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, height: 1.25);
  static const TextStyle headline = TextStyle(
      fontFamily: family, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3);
  static const TextStyle body = TextStyle(
      fontFamily: family, fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.2, height: 1.3);
  static const TextStyle button = TextStyle(
      fontFamily: family, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.2);
  static const TextStyle subhead = TextStyle(
      fontFamily: family, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.1, height: 1.3);
  static const TextStyle caption = TextStyle(
      fontFamily: family, fontSize: 13, fontWeight: FontWeight.w400, height: 1.3);
  static const TextStyle captionStrong = TextStyle(
      fontFamily: family, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3);
  static const TextStyle label = TextStyle(
      fontFamily: family, fontSize: 11, fontWeight: FontWeight.w500, height: 1.2);
  static const TextStyle section = TextStyle(
      fontFamily: family, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2, height: 1.3);
}

/// Spacing and shapes shared by every screen.
abstract final class AppMetrics {
  static const double gutter = 16;
  static const double cardRadius = 12;
  static const double sheetRadius = 14;
  static const double buttonHeight = 50;
  static const double buttonRadius = 12;
  static const double minTouch = 44;
}

CupertinoThemeData appTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: c.accent,
    primaryContrastingColor: c.onAccent,
    scaffoldBackgroundColor: c.page,
    barBackgroundColor: c.page,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      primaryColor: c.accent,
      textStyle: AppText.body.copyWith(color: c.text),
      actionTextStyle: AppText.body.copyWith(color: c.accent),
      navTitleTextStyle: AppText.headline.copyWith(color: c.text),
      navLargeTitleTextStyle: AppText.largeTitle.copyWith(color: c.text),
      navActionTextStyle: AppText.body.copyWith(color: c.accent),
      tabLabelTextStyle: AppText.label.copyWith(color: c.secondary),
      pickerTextStyle: AppText.body.copyWith(color: c.text, fontSize: 21),
      dateTimePickerTextStyle: AppText.body.copyWith(color: c.text, fontSize: 21),
    ),
  );
}
