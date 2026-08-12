import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  });

  final Color page;
  final Color card;
  final Color cardMuted;
  final Color input;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color shadow;

  static const light = VivordoColors(
    page: Color(0xFFFBFAFF),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFF4F2FA),
    input: Color(0xFFF2F2F7),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF747486),
    border: Color(0xFFE1E1E8),
    shadow: Color(0x1A000000),
  );

  static const dark = VivordoColors(
    page: Color(0xFF101014),
    card: Color(0xFF1B1B21),
    cardMuted: Color(0xFF25242D),
    input: Color(0xFF292830),
    // A light Vivordo purple keeps primary copy legible without reverting to
    // stark white and clearly distinguishes the dark appearance.
    textPrimary: Color(0xFFB8AEFF),
    textSecondary: Color(0xFFAAA7B5),
    border: Color(0xFF383640),
    shadow: Color(0x66000000),
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
  }) => VivordoColors(
    page: page ?? this.page,
    card: card ?? this.card,
    cardMuted: cardMuted ?? this.cardMuted,
    input: input ?? this.input,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
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
      extensions: <ThemeExtension<dynamic>>[colors],
      cardTheme: CardThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
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
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border),
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFFF0EDF8)
            : const Color(0xFF29272F),
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark
              ? const Color(0xFF29272F)
              : Colors.white,
        ),
      ),
    );
  }
}

/// Keeps the selected appearance in the signed-in user's Firestore profile.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  String? _boundUid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void bindUser(User? user) {
    if (_boundUid == user?.uid) return;
    _boundUid = user?.uid;
    _subscription?.cancel();
    _subscription = null;

    if (user == null) {
      _setMode(ThemeMode.light);
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          final preferences = snapshot.data()?['preferences'] as Map?;
          _setMode(
            preferences?['darkModeEnabled'] == true
                ? ThemeMode.dark
                : ThemeMode.light,
          );
        });
  }

  Future<void> setDarkMode(bool enabled) async {
    _setMode(enabled ? ThemeMode.dark : ThemeMode.light);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'preferences.darkModeEnabled': enabled,
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
