import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/labeled_slider.dart';
import '../../ui/widgets/pressable.dart';

/// The office palette of the web editor.
const List<String> kOfficePalette = [
  '#2481C3',
  '#165A8C',
  '#F2C230',
  '#B42B25',
  '#FFFFFF',
  '#000000',
  '#14212E',
  '#4A5B6B',
  '#D3DCE1',
];

Color colorOfHex(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 3 ? h.split('').map((c) => '$c$c').join() : h, radix: 16) ?? 0;
  return Color(0xFF000000 | v);
}

String hexOfColor(Color c) {
  String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

/// "#abc" or "abcdef" typed by a person, as "#RRGGBB"; null when it is not a colour.
String? normalizeHex(String text) {
  var t = text.trim().replaceFirst('#', '');
  if (t.length == 3) t = t.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
  return '#${t.toUpperCase()}';
}

/// Palette, a saturation/brightness square with a hue slider, a hex field and opacity.
/// [onChanged] runs for every move; the caller joins a drag into one undo step.
class ColorEditor extends StatefulWidget {
  const ColorEditor({
    super.key,
    required this.color,
    required this.alpha,
    required this.onChanged,
    this.used = const [],
    this.showAlpha = true,
  });

  final String color;
  final double alpha;
  final void Function(String hex, double alpha) onChanged;

  /// Colours already used in the layout.
  final List<String> used;
  final bool showAlpha;

  @override
  State<ColorEditor> createState() => _ColorEditorState();
}

class _ColorEditorState extends State<ColorEditor> {
  late HSVColor _hsv;
  late double _alpha;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(colorOfHex(widget.color));
    _alpha = widget.alpha;
    _hex = TextEditingController(text: widget.color.toUpperCase());
  }

  @override
  void didUpdateWidget(ColorEditor old) {
    super.didUpdateWidget(old);
    if (widget.color.toUpperCase() != hexOfColor(_hsv.toColor())) {
      // Changed from outside (undo, a swatch): follow it. Grey keeps its hue.
      final next = HSVColor.fromColor(colorOfHex(widget.color));
      _hsv = next.saturation == 0 || next.value == 0 ? next.withHue(_hsv.hue) : next;
      _hex.text = widget.color.toUpperCase();
    }
    _alpha = widget.alpha;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _emit() {
    final hex = hexOfColor(_hsv.toColor());
    _hex.text = hex;
    widget.onChanged(hex, _alpha);
  }

  void _pick(String hex) {
    _hsv = HSVColor.fromColor(colorOfHex(hex));
    _emit();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final swatches = [
      ...kOfficePalette,
      for (final u in widget.used)
        if (!kOfficePalette.contains(u.toUpperCase())) u.toUpperCase(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: swatches.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final hex = swatches[i];
              final on = hex == widget.color.toUpperCase();
              return Pressable(
                onPressed: () => _pick(hex),
                semanticLabel: 'Colour $hex',
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorOfHex(hex),
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? c.accent : c.separator, width: on ? 3 : 1),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _SatValSquare(
          hsv: _hsv,
          onChanged: (v) {
            setState(() => _hsv = v);
            _emit();
          },
        ),
        const SizedBox(height: 10),
        _HueBar(
          hue: _hsv.hue,
          onChanged: (h) {
            setState(() => _hsv = _hsv.withHue(h));
            _emit();
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Hex', style: AppText.subhead.copyWith(color: c.text)),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: CupertinoTextField(
                controller: _hex,
                maxLength: 7,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]'))],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                style: AppText.body.copyWith(color: c.text, fontFeatures: AppText.tabular),
                decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(10)),
                onChanged: (t) {
                  final hex = normalizeHex(t);
                  if (hex == null) return;
                  setState(() => _hsv = HSVColor.fromColor(colorOfHex(hex)));
                  widget.onChanged(hex, _alpha);
                },
              ),
            ),
          ],
        ),
        if (widget.showAlpha)
          LabeledSlider(
            label: 'Opacity',
            value: _alpha * 100,
            min: 0,
            max: 100,
            format: (v) => '${v.round()}%',
            onChanged: (v) {
              setState(() => _alpha = v / 100);
              widget.onChanged(hexOfColor(_hsv.toColor()), _alpha);
            },
          ),
      ],
    );
  }
}

class _SatValSquare extends StatelessWidget {
  const _SatValSquare({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const h = 150.0;
        final w = box.maxWidth;
        void at(Offset p) =>
            onChanged(hsv.withSaturation((p.dx / w).clamp(0.0, 1.0)).withValue((1 - p.dy / h).clamp(0.0, 1.0)));
        return GestureDetector(
          onPanStart: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          onTapDown: (d) => at(d.localPosition),
          child: SizedBox(
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [const Color(0xFFFFFFFF), HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
                      ),
                    ),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xFF000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.saturation * w - 11,
                  top: (1 - hsv.value) * h - 11,
                  child: IgnorePointer(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hsv.toColor(),
                        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void at(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0) * 359.99);
        return GestureDetector(
          onPanStart: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          onTapDown: (d) => at(d.localPosition),
          child: SizedBox(
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: [for (var i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor()],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hue / 359.99 * w - 12,
                  top: 2,
                  child: IgnorePointer(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
