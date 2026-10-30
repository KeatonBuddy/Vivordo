import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';
import 'apple_ui.dart';

/// A row that slides left to reveal Delete. Deleting asks first; [onDelete]
/// runs only once confirmed. A tap on the row calls [onTap]. For a gentler
/// action (Hide) pass [actionLabel], [actionIcon] and [actionColor], and no
/// [confirmTitle] to skip the question. With [onDeleteAll] (a repeating
/// priority) it asks "just this one or all repeats" instead.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    required this.confirmTitle,
    this.confirmMessage,
    this.onTap,
    this.onDeleteAll,
    this.actionLabel = 'Delete',
    this.actionIcon = CupertinoIcons.delete,
    this.actionColor = const Color(0xFFE5484D),
  });

  final Widget child;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onDeleteAll;
  final String? confirmTitle;
  final String actionLabel;
  final IconData actionIcon;
  final Color actionColor;
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
                color: widget.actionColor,
                child: InkWell(
                  onTap: _deleting ? null : _delete,
                  child: Center(
                    child: _deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 10,
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.actionIcon,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.actionLabel,
                                style: const TextStyle(
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
      final title = widget.confirmTitle;
      final all = widget.onDeleteAll;
      final Future<void> Function()? action;
      if (all != null) {
        final choice = await askRepeatingDelete(context);
        action = choice == null ? null : (choice ? all : widget.onDelete);
      } else {
        final confirmed =
            title == null ||
            await confirmAction(
              context,
              title: title,
              message: widget.confirmMessage,
              confirmLabel: widget.actionLabel,
            );
        action = confirmed ? widget.onDelete : null;
      }
      if (action != null && mounted) {
        setState(() => _deleting = true);
        await action();
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

/// Asks whether to delete one repeat of a priority or all of them: true for
/// all (it stops repeating; days already done are kept), false for just
/// this one, null when cancelled.
Future<bool?> askRepeatingDelete(BuildContext context) =>
    showAppleActionSheet<bool>(
      context,
      title: 'Delete repeating priority?',
      message: 'Days you already did are kept.',
      actions: const [
        AppleSheetAction('Just this one', false, destructive: true),
        AppleSheetAction('All repeats', true, destructive: true),
      ],
    );
