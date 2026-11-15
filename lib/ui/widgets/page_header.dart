import 'package:flutter/cupertino.dart';

import '../app_theme.dart';
import 'pressable.dart';

/// The top bar of a pushed page: a centred title and "Done" at the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 88),
              Expanded(
                child: Text(title, textAlign: TextAlign.center, style: AppText.headline.copyWith(color: colors.text)),
              ),
              SizedBox(
                width: 88,
                child: Pressable(
                  onPressed: () => Navigator.of(context).maybePop(),
                  semanticLabel: 'Done',
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.only(right: 16),
                    alignment: Alignment.centerRight,
                    child: Text('Done', style: AppText.button.copyWith(color: colors.accent)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
