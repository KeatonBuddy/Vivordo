import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';

/// Apple-style building blocks shared across the app: alerts, action sheets,
/// toasts, form and info sheets, and small controls. Use these instead of
/// Material's AlertDialog, ListTile sheets, raw SnackBars and checkboxes.

const appleRed = Color(0xFFFF3B30);
const _purple = Color(0xFF534AB7);

Color _tint(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFAFA9EC)
    : _purple;

// ── Alerts ───────────────────────────────────────────────────────────────────

class AppleAlertButton {
  const AppleAlertButton(
    this.label, {
    required this.onPressed,
    this.destructive = false,
    this.bold = false,
  });

  final String label;

  /// Null shows the button disabled.
  final VoidCallback? onPressed;
  final bool destructive;
  final bool bold;
}

/// An iOS alert: centred title and message, optional [content] (a field or a
/// short list), and buttons side by side when there are two, stacked
/// otherwise. Use [showAppleAlert] or [confirmAction] unless the alert needs
/// its own state (wrap this in a StatefulBuilder then).
class AppleAlert extends StatelessWidget {
  const AppleAlert({
    super.key,
    required this.title,
    this.message,
    this.content,
    required this.buttons,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<AppleAlertButton> buttons;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final divider = colors.textSecondary.withValues(alpha: .28);
    Widget button(AppleAlertButton b) => InkWell(
      onTap: b.onPressed,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          b.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            fontSize: 17,
            fontWeight: b.bold ? FontWeight.w600 : FontWeight.w400,
            color: b.onPressed == null
                ? colors.textSecondary.withValues(alpha: .5)
                : b.destructive
                ? appleRed
                : _tint(context),
          ),
        ),
      ),
    );

    return Dialog(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (content != null) ...[
                    const SizedBox(height: 12),
                    content!,
                  ],
                ],
              ),
            ),
            Divider(height: .5, thickness: .5, color: divider),
            if (buttons.length == 2)
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: button(buttons[0])),
                    VerticalDivider(width: .5, thickness: .5, color: divider),
                    Expanded(child: button(buttons[1])),
                  ],
                ),
              )
            else
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) Divider(height: .5, thickness: .5, color: divider),
                button(buttons[i]),
              ],
          ],
        ),
      ),
    );
  }
}

class AppleAlertAction<T> {
  const AppleAlertAction(
    this.label,
    this.value, {
    this.destructive = false,
    this.bold = false,
  });

  final String label;
  final T value;
  final bool destructive;
  final bool bold;
}

/// Shows an [AppleAlert] whose buttons close it with their value.
Future<T?> showAppleAlert<T>(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  required List<AppleAlertAction<T>> actions,
}) => showDialog<T>(
  context: context,
  builder: (dialogContext) => AppleAlert(
    title: title,
    message: message,
    content: content,
    buttons: [
      for (final action in actions)
        AppleAlertButton(
          action.label,
          destructive: action.destructive,
          bold: action.bold,
          onPressed: () => Navigator.pop(dialogContext, action.value),
        ),
    ],
  ),
);

/// Cancel / [confirmLabel] alert; true only when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async =>
    await showAppleAlert<bool>(
      context,
      title: title,
      message: message,
      actions: [
        AppleAlertAction(cancelLabel, false, bold: !destructive),
        AppleAlertAction(
          confirmLabel,
          true,
          destructive: destructive,
          bold: !destructive,
        ),
      ],
    ) ??
    false;

/// A plain text field sized for an [AppleAlert].
class AppleAlertField extends StatelessWidget {
  const AppleAlertField({
    super.key,
    required this.controller,
    this.placeholder,
    this.obscureText = false,
    this.autofocus = true,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: placeholder,
        filled: true,
        fillColor: colors.input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: _fieldBorder(colors.border),
        enabledBorder: _fieldBorder(colors.border),
        disabledBorder: _fieldBorder(colors.border),
        focusedBorder: _fieldBorder(_tint(context)),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color, width: .5),
  );
}

// ── Action sheets ────────────────────────────────────────────────────────────

class AppleSheetAction<T> {
  const AppleSheetAction(
    this.label,
    this.value, {
    this.destructive = false,
    this.selected = false,
  });

  final String label;
  final T value;
  final bool destructive;

  /// Shown bold, the way iOS marks the current choice.
  final bool selected;
}

/// An iOS action sheet in Vivordo purple, with a separate Cancel button.
Future<T?> showAppleActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<AppleSheetAction<T>> actions,
  String cancelLabel = 'Cancel',
}) => showCupertinoModalPopup<T>(
  context: context,
  builder: (sheetContext) => CupertinoTheme(
    data: CupertinoThemeData(
      brightness: Theme.of(context).brightness,
      primaryColor: _tint(context),
    ),
    child: CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final action in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: action.destructive,
            isDefaultAction: action.selected,
            onPressed: () => Navigator.pop(sheetContext, action.value),
            child: Text(action.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(sheetContext),
        child: Text(cancelLabel),
      ),
    ),
  ),
);

// ── Toasts ───────────────────────────────────────────────────────────────────

enum ToastKind { info, success, offline, error }

/// A short floating capsule message. Error toasts say what failed in plain
/// words; never pass raw exception text (log it with debugPrint instead).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  // The capsule is dark in light mode and light in dark mode.
  final onDark = Theme.of(context).brightness == Brightness.light;
  final (defaultIcon, iconColor) = switch (kind) {
    ToastKind.success => (
      CupertinoIcons.check_mark_circled,
      onDark ? const Color(0xFF5DCAA5) : const Color(0xFF0F6E56),
    ),
    ToastKind.offline => (
      CupertinoIcons.cloud,
      onDark ? const Color(0xFFAFA9EC) : _purple,
    ),
    ToastKind.error => (
      CupertinoIcons.exclamationmark_circle,
      onDark ? const Color(0xFFF09595) : const Color(0xFFA32D2D),
    ),
    ToastKind.info => (null, Colors.transparent),
  };
  final shownIcon = icon ?? defaultIcon;
  return messenger.showSnackBar(
    SnackBar(
      duration:
          duration ??
          Duration(
            seconds: kind == ToastKind.error || actionLabel != null ? 5 : 3,
          ),
      persist: false,
      content: Row(
        children: [
          if (shownIcon != null) ...[
            Icon(shownIcon, size: 19, color: iconColor),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(message)),
        ],
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

// ── Sheets ───────────────────────────────────────────────────────────────────

/// A modal sheet with a grabber and rounded top corners on the page colour.
Future<T?> showAppleSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  // Above the tab bar and the Vivordo AI bubble, like an iOS sheet.
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: isDismissible,
  enableDrag: isDismissible,
  backgroundColor: context.vivordoColors.page,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
  ),
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: builder(sheetContext),
  ),
);

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 5,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      decoration: BoxDecoration(
        color: context.vivordoColors.textSecondary.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

/// The body of a form sheet: Cancel · title · [doneLabel] across the top,
/// then [children] (usually [AppleFormGroup]s) on the page colour.
class AppleFormSheet extends StatelessWidget {
  const AppleFormSheet({
    super.key,
    required this.title,
    required this.children,
    this.doneLabel = 'Done',
    this.onDone,
    this.onCancel,
    this.busy = false,
  });

  final String title;
  final List<Widget> children;
  final String doneLabel;

  /// Null shows Done disabled.
  final VoidCallback? onDone;

  /// Defaults to closing the sheet.
  final VoidCallback? onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final tint = _tint(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Grabber(),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: busy
                      ? null
                      : onCancel ?? () => Navigator.maybePop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: 17, color: tint),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: busy ? null : onDone,
                  child: busy
                      ? const CupertinoActivityIndicator()
                      : Text(
                          doneLabel,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: onDone == null
                                ? colors.textSecondary.withValues(alpha: .5)
                                : tint,
                          ),
                        ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An inset grouped section: optional small caps [header], rounded rows with
/// hairlines between them, optional [footer] note.
class AppleFormGroup extends StatelessWidget {
  const AppleFormGroup({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: .3,
                  color: colors.textSecondary,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: .5,
                      thickness: .5,
                      indent: 16,
                      color: colors.border,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(
                footer!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row in an [AppleFormGroup]: [label] on the left, [trailing] (a value,
/// switch or checkmark) on the right; tappable when [onTap] is set.
class AppleFormRow extends StatelessWidget {
  const AppleFormRow({
    super.key,
    required this.label,
    this.trailing,
    this.value,
    this.onTap,
    this.chevron = false,
    this.destructive = false,
    this.leading,
  });

  final String label;
  final Widget? trailing;

  /// Shorthand for a secondary-text [trailing].
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: destructive ? appleRed : colors.textPrimary,
                  ),
                ),
              ),
              if (value != null)
                Flexible(
                  child: Text(
                    value!,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: colors.textSecondary),
                  ),
                ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (chevron) ...[
                const SizedBox(width: 6),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: colors.textSecondary.withValues(alpha: .6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A text entry row in an [AppleFormGroup]: [label] left, borderless field
/// right-aligned (or full width when [label] is null).
class AppleFormTextRow extends StatelessWidget {
  const AppleFormTextRow({
    super.key,
    this.label,
    required this.controller,
    this.placeholder,
    this.keyboardType,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final String? label;
  final TextEditingController controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autofocus;
  final int maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final field = TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: 1,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      textAlign: label == null ? TextAlign.start : TextAlign.end,
      style: TextStyle(fontSize: 16, color: colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        hintText: placeholder,
        hintStyle: TextStyle(color: colors.textSecondary.withValues(alpha: .7)),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: label == null
          ? field
          : Row(
              children: [
                Text(
                  label!,
                  style: TextStyle(fontSize: 16, color: colors.textPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(child: field),
              ],
            ),
    );
  }
}

/// A rounded value chip for a form row, like iOS date and time buttons.
class AppleValuePill extends StatelessWidget {
  const AppleValuePill(this.text, {super.key, this.active = false});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? _tint(context).withValues(alpha: .14) : colors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          color: active ? _tint(context) : colors.textPrimary,
        ),
      ),
    );
  }
}

class AppleInfoItem {
  const AppleInfoItem(this.title, this.detail, {this.icon});

  final String title;
  final String detail;
  final IconData? icon;
}

/// An explainer sheet: icon tile, title, one-line summary, inset rows, and a
/// single button. For longer copy pass [body] instead of [items].
Future<void> showInfoSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? summary,
  List<AppleInfoItem> items = const [],
  Widget? body,
  String buttonLabel = 'Got it',
}) => showAppleSheet<void>(
  context,
  builder: (sheetContext) {
    final colors = sheetContext.vivordoColors;
    final tint = _tint(sheetContext);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Grabber(),
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: tint, size: 26),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            if (summary != null) ...[
              const SizedBox(height: 6),
              Text(
                summary,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (items.isNotEmpty)
              AppleFormGroup(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.icon != null) ...[
                            Icon(item.icon, size: 20, color: tint),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.detail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ?body,
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

// ── Controls ─────────────────────────────────────────────────────────────────

/// The app's switch: iOS style on iPhone, Vivordo purple when on.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Switch.adaptive(
    value: value,
    onChanged: onChanged,
    activeTrackColor: VivordoTheme.brand,
  );
}

/// iOS segmented control with a card-coloured thumb.
class AppSegmented<T extends Object> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  /// Value → label, in display order.
  final Map<T, String> segments;

  /// Null shows nothing selected (e.g. a question not answered yet).
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: colors.input,
        // iOS keeps the thumb lighter than the track in dark mode too.
        thumbColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF4A4952)
            : colors.card,
        onValueChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
        children: {
          for (final entry in segments.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: entry.key == value
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: colors.textPrimary,
                ),
              ),
            ),
        },
      ),
    );
  }
}

/// A round completion check (replaces Material's square checkbox).
class AppCheckCircle extends StatelessWidget {
  const AppCheckCircle({super.key, required this.checked, this.size = 22});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: checked ? _purple : Colors.transparent,
      border: Border.all(
        color: checked
            ? _purple
            : context.vivordoColors.textSecondary.withValues(alpha: .6),
        width: 1.6,
      ),
    ),
    child: checked
        ? Icon(Icons.check_rounded, size: size * .68, color: Colors.white)
        : null,
  );
}

/// A choice row with a trailing purple checkmark when [selected]
/// (replaces radio buttons).
class AppleChoiceRow extends StatelessWidget {
  const AppleChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppleFormRow(
    label: label,
    onTap: onTap,
    value: detail,
    trailing: SizedBox(
      width: 20,
      child: selected
          ? Icon(CupertinoIcons.checkmark_alt, size: 20, color: _tint(context))
          : null,
    ),
  );
}
