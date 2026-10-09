import 'dart:async';

import 'package:flutter/widgets.dart';

import '../src/utils/owned_stream_snapshot.dart';

/// Disconnects screen-only streams once their tab/route has been hidden for
/// [kHiddenStreamGrace]; a quick switch back keeps the live listener instead
/// of re-downloading its whole result. StreamBuilder retains its last data
/// when disconnected. Do not pause the subscription: that would queue every
/// hidden update for replay on return.
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
  bool? _active;
  bool _connected = false;
  Timer? _disconnect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active == _active) return;
    final first = _active == null;
    _active = active;
    _disconnect?.cancel();
    if (active || first) {
      // A tab preloaded while hidden never connects until first shown.
      _connected = active;
    } else {
      _disconnect = Timer(kHiddenStreamGrace, () {
        if (mounted) setState(() => _connected = false);
      });
    }
  }

  @override
  void dispose() {
    _disconnect?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active ?? true;
    return StreamBuilder<T>(
      stream: _connected ? widget.stream : null,
      initialData: widget.initialData,
      builder: (context, snapshot) {
        if (!active) return _lastChild ?? const SizedBox.shrink();
        return _lastChild = widget.builder(context, snapshot);
      },
    );
  }
}
