import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';
import 'apple_ui.dart';

/// A row that slides left to reveal Delete. Deleting asks first; [onDelete]
/// runs only once confirmed. A tap on the row calls [onTap].
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    required this.confirmTitle,
    this.confirmMessage,
    this.onTap,
  });

  final Widget child;
  final Future<void> Function() onDelete;
  final String confirmTitle;
  final String? confirmMessage;
  final VoidCallback? onTap;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  static const _actionWidth = 88.0;
  double _dragOffset = 0;
  bool _dragging = false;
  bool _deleting = false;
  bool _confirming = false;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: _actionWidth,
              child: Material(
                color: const Color(0xFFE5484D),
                child: InkWell(
                  onTap: _deleting ? null : _delete,
                  child: Center(
                    child: _deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          // Let taps in the revealed action area reach the Delete button.
          behavior: HitTestBehavior.deferToChild,
          onTap: widget.onTap,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) => setState(() {
            _dragOffset = (_dragOffset + details.delta.dx).clamp(
              -_actionWidth,
              0,
            );
          }),
          onHorizontalDragEnd: (_) => setState(() {
            _dragging = false;
            _dragOffset = _dragOffset <= -_actionWidth * .35
                ? -_actionWidth
                : 0;
          }),
          onHorizontalDragCancel: () => setState(() {
            _dragging = false;
            _dragOffset = 0;
          }),
          child: AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            color: context.vivordoColors.card,
            child: widget.child,
          ),
        ),
      ],
    ),
  );

  Future<void> _delete() async {
    if (_deleting || _confirming) return;
    _confirming = true;
    try {
      final confirmed = await confirmAction(
        context,
        title: widget.confirmTitle,
        message: widget.confirmMessage,
        confirmLabel: 'Delete',
      );
      if (confirmed && mounted) {
        setState(() => _deleting = true);
        await widget.onDelete();
      }
    } finally {
      _confirming = false;
      if (mounted) {
        setState(() {
          _deleting = false;
          _dragOffset = 0;
        });
      }
    }
  }
}

/// The confirmation text for deleting a priority.
String priorityDeleteMessage(String title, {required bool manual}) =>
    'Remove “$title” from your priorities?'
    '${manual ? '' : "\n\nThis won't delete the original calendar event or recurring schedule."}';
