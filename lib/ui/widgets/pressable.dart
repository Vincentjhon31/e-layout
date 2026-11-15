import 'package:flutter/cupertino.dart';

/// A tappable area that dims while pressed, like iOS controls. Disabled when
/// [onPressed] and [onLongPress] are both null.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onDoubleTap,
    this.semanticLabel,
    this.pressedOpacity = 0.55,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final String? semanticLabel;
  final double pressedOpacity;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                widget.onLongPress!();
              },
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedOpacity(
          opacity: _down ? widget.pressedOpacity : 1,
          duration: Duration(milliseconds: _down ? 10 : 150),
          child: widget.child,
        ),
      ),
    );
  }
}
