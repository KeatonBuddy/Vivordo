import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../src/utils/units.dart';

export '../src/utils/units.dart';

/// Semantic colors used by Vivordo surfaces.
///
/// Screens should use these roles (or [ThemeData.colorScheme]) instead of
/// fixed light-mode grays so the same UI can render in either brightness.
@immutable
class VivordoColors extends ThemeExtension<VivordoColors> {
  const VivordoColors({
    required this.page,
    required this.card,
    required this.cardMuted,
    required this.input,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.shadow,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color page;
  final Color card;
  final Color cardMuted;
  final Color input;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color shadow;

  /// Status colours for text: dark enough in light mode to read at 4.5:1,
  /// the bright system tones in dark mode. Fills and chart marks can keep
  /// the bright tones in both.
  final Color success;
  final Color warning;
  final Color danger;

  static const light = VivordoColors(
    page: Color(0xFFFBFAFF),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFF4F2FA),
    input: Color(0xFFF2F2F7),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF66667A),
    border: Color(0xFFE1E1E8),
    shadow: Color(0x1A000000),
    success: Color(0xFF15803D),
    warning: Color(0xFFA15C00),
    danger: Color(0xFFC0392B),
  );

  /// For Increase Contrast: darker secondary text and borders.
  static const lightHighContrast = VivordoColors(
    page: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFEDEBF5),
    input: Color(0xFFEBEBF0),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF3F3F4E),
    border: Color(0xFF8E8E9C),
    shadow: Color(0x26000000),
    success: Color(0xFF0F5F2E),
    warning: Color(0xFF7A4500),
    danger: Color(0xFF9B1C1C),
  );

  static const dark = VivordoColors(
    page: Color(0xFF101014),
    card: Color(0xFF1B1B21),
    cardMuted: Color(0xFF25242D),
    input: Color(0xFF292830),
    // Near-white like iOS's label colour; purple is kept for what can be
    // tapped, so plain text doesn't look like a link.
    textPrimary: Color(0xFFF2F2F7),
    textSecondary: Color(0xFFAAA7B5),
    border: Color(0xFF383640),
    shadow: Color(0x66000000),
    success: Color(0xFF30D158),
    warning: Color(0xFFFFB340),
    danger: Color(0xFFFF6961),
  );

  /// For Increase Contrast.
  static const darkHighContrast = VivordoColors(
    page: Color(0xFF000000),
    card: Color(0xFF16161B),
    cardMuted: Color(0xFF222128),
    input: Color(0xFF2A2931),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFD4D2DC),
    border: Color(0xFF6E6C78),
    shadow: Color(0x80000000),
    success: Color(0xFF5BE584),
    warning: Color(0xFFFFC870),
    danger: Color(0xFFFF8A80),
  );

  @override
  VivordoColors copyWith({
    Color? page,
    Color? card,
    Color? cardMuted,
    Color? input,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? shadow,
    Color? success,
    Color? warning,
    Color? danger,
  }) => VivordoColors(
    page: page ?? this.page,
    card: card ?? this.card,
    cardMuted: cardMuted ?? this.cardMuted,
    input: input ?? this.input,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
  );

  @override
  VivordoColors lerp(covariant VivordoColors? other, double t) {
    if (other == null) return this;
    return VivordoColors(
      page: Color.lerp(page, other.page, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardMuted: Color.lerp(cardMuted, other.cardMuted, t)!,
      input: Color.lerp(input, other.input, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension VivordoThemeContext on BuildContext {
  VivordoColors get vivordoColors =>
      Theme.of(this).extension<VivordoColors>() ?? VivordoColors.light;
}

abstract final class VivordoTheme {
  static const brand = Color(0xFF7B6EF6);

  static ThemeData get light => _build(Brightness.light, VivordoColors.light);
  static ThemeData get dark => _build(Brightness.dark, VivordoColors.dark);
  static ThemeData get lightHighContrast =>
      _build(Brightness.light, VivordoColors.lightHighContrast);
  static ThemeData get darkHighContrast =>
      _build(Brightness.dark, VivordoColors.darkHighContrast);

  static ThemeData _build(Brightness brightness, VivordoColors colors) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: brand,
          brightness: brightness,
          surface: colors.card,
        ).copyWith(
          primary: brand,
          secondary: brand,
          onSurface: colors.textPrimary,
          onSurfaceVariant: colors.textSecondary,
          outline: colors.border,
          surfaceContainerLowest: colors.page,
          surfaceContainerLow: colors.card,
          surfaceContainer: colors.cardMuted,
          surfaceContainerHigh: colors.input,
        );

    return ThemeData(
      brightness: brightness,
      fontFamily: 'DMSans',
      useMaterial3: true,
      colorScheme: scheme,
      primaryColor: brand,
      scaffoldBackgroundColor: colors.page,
      canvasColor: colors.page,
      cardColor: colors.card,
      dividerColor: colors.border,
      shadowColor: colors.shadow,
      // iOS has no ripple: a pressed row just shades until the finger lifts.
      splashFactory: NoSplash.splashFactory,
      highlightColor: brightness == Brightness.dark
          ? Colors.white.withValues(alpha: .08)
          : Colors.black.withValues(alpha: .06),
      extensions: <ThemeExtension<dynamic>>[colors],
      cardTheme: CardThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // iOS navigation bars: page colour, no scroll tint, centred bold title,
      // and the chevron back button everywhere.
      appBarTheme: AppBarTheme(
        backgroundColor: colors.page,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(CupertinoIcons.back),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        modalBackgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.input,
        hintStyle: TextStyle(color: colors.textSecondary),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(14),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFF3B30)),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFF3B30), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: brand, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
        fontFamily: 'DMSans',
      ),
      // Toasts: a floating capsule that clears the floating tab bar.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFFF0EDF8)
            : const Color(0xFF29272F),
        actionTextColor: brightness == Brightness.dark
            ? const Color(0xFF534AB7)
            : const Color(0xFFAFA9EC),
        contentTextStyle: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: brightness == Brightness.dark
              ? const Color(0xFF29272F)
              : Colors.white,
        ),
      ),
    );
  }
}

/// Keeps the selected appearance, whether scores show as numbers or words,
/// and the units measurements show in, in the signed-in user's Firestore
/// profile.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  bool _showScoreNumbers = true;
  Units _units = _deviceUnits;
  String? _boundUid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  ThemeMode get mode => _mode;

  /// False in words mode (`preferences.showScoreNumbers`, on unless
  /// switched off): scores show as sentences and state chips. Measurements
  /// (sleep, heart rate, steps) always show.
  bool get showScoreNumbers => _showScoreNumbers;

  /// Settings → Units (`preferences.units`), each measure defaulting to the
  /// device region's (Units.forCountry) until chosen.
  Units get units => _units;

  /// The signed-in user's units for code without a BuildContext (the AI
  /// requests); the latest any controller has seen.
  static Units current = _deviceUnits;

  static Units get _deviceUnits => Units.forCountry(
    WidgetsBinding.instance.platformDispatcher.locale.countryCode,
  );

  String get modeLabel => switch (_mode) {
    ThemeMode.system => 'System Default',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  void bindUser(User? user) {
    if (_boundUid == user?.uid) return;
    _boundUid = user?.uid;
    _subscription?.cancel();
    _subscription = null;

    if (user == null) {
      _setMode(ThemeMode.system);
      _setShowScoreNumbers(true);
      _setUnits(_deviceUnits);
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          final preferences = snapshot.data()?['preferences'] as Map?;
          final savedMode = preferences?['themeMode'] as String?;
          final nextMode = switch (savedMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            'system' => ThemeMode.system,
            // Preserve the explicit choice made by users of older versions.
            // A profile without either preference is a new/default profile and
            // follows the device appearance.
            _ when preferences?.containsKey('darkModeEnabled') == true =>
              preferences?['darkModeEnabled'] == true
                  ? ThemeMode.dark
                  : ThemeMode.light,
            _ => ThemeMode.system,
          };
          _setMode(nextMode);
          _setShowScoreNumbers(preferences?['showScoreNumbers'] != false);
          _setUnits(Units.fromPreferences(preferences?['units'], _deviceUnits));
        });
  }

  Future<void> setShowScoreNumbers(bool show) async {
    _setShowScoreNumbers(show);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'preferences.showScoreNumbers': show,
    });
  }

  void _setShowScoreNumbers(bool show) {
    if (_showScoreNumbers == show) return;
    _showScoreNumbers = show;
    notifyListeners();
  }

  Future<void> setUnits(Units units) async {
    _setUnits(units);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'preferences.units': units.toMap(),
    });
  }

  void _setUnits(Units units) {
    current = units;
    if (_units == units) return;
    _units = units;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _setMode(mode);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'preferences.themeMode': mode.name,
      // Keep older app versions functional while users transition to the new
      // three-option setting. Older clients interpret System as Light.
      'preferences.darkModeEnabled': mode == ThemeMode.dark,
    });
  }

  void _setMode(ThemeMode next) {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
