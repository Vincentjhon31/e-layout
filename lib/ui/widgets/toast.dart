import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../app_theme.dart';

/// The pill a toast shows.
class ToastView extends StatelessWidget {
  const ToastView({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightnessOf(context) == Brightness.dark;
    final bg = dark ? const Color(0xFF3A3A3C) : const Color(0xFF1F2328);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: const Color(0xFFFFFFFF)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(message,
                textAlign: TextAlign.center,
                style: AppText.subhead.copyWith(color: const Color(0xFFFFFFFF))),
          ),
        ],
      ),
    );
  }
}

OverlayEntry? _current;
Timer? _timer;

/// Shows a short message above the bottom of the screen for a moment.
void showToast(BuildContext context, String message,
    {IconData? icon, Duration duration = const Duration(milliseconds: 2400)}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  hideToast();
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(ctx).bottom + 96,
      child: IgnorePointer(
        child: Center(child: ToastView(message: message, icon: icon)),
      ),
    ),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(duration, hideToast);
}

void hideToast() {
  _timer?.cancel();
  _timer = null;
  _current?.remove();
  _current = null;
}
