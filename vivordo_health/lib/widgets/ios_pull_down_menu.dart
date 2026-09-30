import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';

class IosMenuAction<T> {
  const IosMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// A ⋯ button whose menu follows the iOS pull-down style: a rounded panel
/// under the button, full-width rows with the label on the left and its
/// symbol on the right, hairline separators, and destructive actions in red.
class IosPullDownMenu<T> extends StatelessWidget {
  const IosPullDownMenu({
    super.key,
    required this.actions,
    required this.onSelected,
    this.tooltip = 'More actions',
    this.icon = CupertinoIcons.ellipsis_circle,
  });

  final List<IosMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final IconData icon;

  static const _destructive = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: Icon(icon),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: dark ? const Color(0xFF2A2A31) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: dark ? .5 : .22),
      menuPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<T>(
            value: actions[i].value,
            padding: EdgeInsets.zero,
            height: 46,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: i < actions.length - 1
                    ? Border(
                        bottom: BorderSide(
                          color: colors.border.withValues(alpha: .7),
                          width: .5,
                        ),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      actions[i].label,
                      style: TextStyle(
                        fontSize: 16,
                        color: actions[i].destructive
                            ? _destructive
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    actions[i].icon,
                    size: 20,
                    color: actions[i].destructive
                        ? _destructive
                        : colors.textPrimary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
