import 'dart:math' as math;
import 'dart:ui' as ui;

import '../fonts/font_registry.dart';
import '../model/layout_doc.dart';

/// Lines, widths and the box size of a text piece, in design units.
class TextBlock {
  const TextBlock(this.lines, this.widths, this.lh, this.asc, this.desc, this.w, this.h);
  final List<String> lines;
  final List<double> widths;
  final double lh, asc, desc, w, h;
}

/// Flutter adds the letter spacing after the last glyph too, so one spacing is
/// taken off a line's advance width. Pinned by a test in text_layout_test.dart.
const bool kTrailingSpacing = true;

/// Lines of a text piece: split only on newlines, upper-cased first when asked.
List<String> textLines(LayoutElement el) =>
    (el.upper ? el.text.toUpperCase() : el.text).split('\n');

ui.FontWeight weightOf(int weight) =>
    ui.FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)];

/// A one-line paragraph, laid out without wrapping. Paint with either
/// [color] or [foreground] (not both).
ui.Paragraph buildLine(LayoutElement el, String line,
    {ui.Color? color, ui.Paint? foreground}) {
  final variable = FontRegistry.instance.isVariable(el.font);
  final style = ui.TextStyle(
    color: foreground == null ? (color ?? const ui.Color(0xFF000000)) : null,
    foreground: foreground,
    fontFamily: el.font,
    fontSize: el.size,
    fontWeight: weightOf(el.weight),
    fontStyle: el.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
    letterSpacing: el.letterSpacing,
    fontVariations: variable ? [ui.FontVariation('wght', el.weight.toDouble())] : null,
  );
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: ui.TextDirection.ltr))
    ..pushStyle(style)
    ..addText(line);
  return b.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
}

TextBlock layoutText(LayoutElement el) {
  final lines = textLines(el);
  final widths = <double>[];
  for (final l in lines) {
    if (l.isEmpty) {
      widths.add(0);
      continue;
    }
    final p = buildLine(el, l);
    widths.add(p.maxIntrinsicWidth - (kTrailingSpacing ? el.letterSpacing : 0));
    p.dispose();
  }
  final hg = buildLine(el, 'Hg');
  final m = hg.computeLineMetrics();
  final asc = m.isNotEmpty && m.first.unscaledAscent > 0 ? m.first.unscaledAscent : el.size * 0.9;
  final desc = m.isNotEmpty && m.first.descent > 0 ? m.first.descent : el.size * 0.25;
  hg.dispose();
  final lh = el.size * el.lineHeight;
  final w = math.max(1.0, widths.reduce(math.max));
  final h = math.max(1.0, lh * lines.length);
  return TextBlock(lines, widths, lh, asc, desc, w, h);
}
