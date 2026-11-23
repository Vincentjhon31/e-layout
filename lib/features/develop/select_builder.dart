import 'package:flutter/widgets.dart';

/// Rebuilds [builder] when [listenable] fires and [select] gives a new value.
class SelectBuilder extends StatefulWidget {
  const SelectBuilder({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;
  final Object? Function() select;
  final WidgetBuilder builder;

  @override
  State<SelectBuilder> createState() => _SelectBuilderState();
}

class _SelectBuilderState extends State<SelectBuilder> {
  Object? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select();
    widget.listenable.addListener(_check);
  }

  @override
  void didUpdateWidget(SelectBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_check);
      widget.listenable.addListener(_check);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final next = widget.select();
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
