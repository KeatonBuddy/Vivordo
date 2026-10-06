import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';

class IosMenuAction<T> {
  const IosMenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.checked,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;

  /// Set on choice menus: true shows a leading checkmark. Leave null on
  /// plain action menus.
  final bool? checked;
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
    this.child,
  });

  final List<IosMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final IconData icon;

  /// A custom trigger (e.g. a form row value) used instead of [icon].
  final Widget? child;

  static const _destructive = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasChecks = actions.any((action) => action.checked != null);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: child == null ? Icon(icon) : null,
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
                  if (hasChecks)
                    SizedBox(
                      width: 26,
                      child: actions[i].checked == true
                          ? Icon(
                              CupertinoIcons.checkmark_alt,
                              size: 18,
                              color: colors.textPrimary,
                            )
                          : null,
                    ),
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
                  if (actions[i].icon != null)
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
      child: child,
    );
  }
}
