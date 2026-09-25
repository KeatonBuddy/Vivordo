import 'package:flutter/widgets.dart';

/// Disconnects screen-only streams while their tab/route is hidden.
/// StreamBuilder retains its last data when disconnected. Do not pause the
/// subscription: that would queue every hidden update for replay on return.
class VisibleStreamBuilder<T> extends StatefulWidget {
  const VisibleStreamBuilder({
    super.key,
    this.stream,
    this.initialData,
    required this.builder,
  });

  final Stream<T>? stream;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<VisibleStreamBuilder<T>> createState() =>
      _VisibleStreamBuilderState<T>();
}

class _VisibleStreamBuilderState<T> extends State<VisibleStreamBuilder<T>> {
  Widget? _lastChild;

  @override
  Widget build(BuildContext context) {
    final active = TickerMode.valuesOf(context).enabled;
    return StreamBuilder<T>(
      stream: active ? widget.stream : null,
      initialData: widget.initialData,
      builder: (context, snapshot) {
        if (!active) return _lastChild ?? const SizedBox.shrink();
        return _lastChild = widget.builder(context, snapshot);
      },
    );
  }
}
