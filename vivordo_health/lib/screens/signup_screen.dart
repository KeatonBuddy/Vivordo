import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vivordo_health/src/services/auth_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import 'onboarding_flow_screen.dart' show onboardingTheme;
import '../widgets/privacy_support_links.dart';

/// Creating an account: email first, then Apple or Google. Everything after
/// sign-in (email verification, then onboarding) is AuthGate's, so this
/// screen only returns to it.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _PasswordRequirement {
  final String label;
  final bool Function(String) isMet;
  const _PasswordRequirement(this.label, this.isMet);
}

final List<_PasswordRequirement> _passwordRequirements = [
  _PasswordRequirement('At least 6 characters', (p) => p.length >= 6),
  _PasswordRequirement(
    'One uppercase letter',
    (p) => RegExp(r'[A-Z]').hasMatch(p),
  ),
  _PasswordRequirement(
    'One lowercase letter',
    (p) => RegExp(r'[a-z]').hasMatch(p),
  ),
  _PasswordRequirement('One number', (p) => RegExp(r'[0-9]').hasMatch(p)),
  _PasswordRequirement(
    'One special character',
    (p) => RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\/~`]').hasMatch(p),
  ),
];

const _purple = VivordoTheme.brand;

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  String? _passwordError;
  // Guards against a double tap creating the account twice (the second call
  // would fail with email-already-in-use).
  bool _emailLoading = false;
  bool _appleLoading = false;
  bool _googleLoading = false;

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  bool get _busy => _emailLoading || _appleLoading || _googleLoading;
  bool get _showApple => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() => _passwordError = null));
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Back to AuthGate, which shows email verification or onboarding next.
  void _toAuthGate() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);

  Future<void> _createWithEmail() async {
    if (_busy) return;
    if (!_passwordRequirements.every((r) => r.isMet(_password.text))) {
      setState(
        () => _passwordError = 'Password does not meet all requirements',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _emailLoading = true);
    final success = await AuthService.emailSignup(
      emailAddress: _email.text.trim(),
      password: _password.text,
      displayName: _name.text.trim(),
      context: context,
      onPasswordError: (message) => setState(() => _passwordError = message),
    );
    if (!mounted) return;
    setState(() => _emailLoading = false);
    if (!success) return;
    TextInput.finishAutofillContext();
    _toAuthGate();
  }

  Future<void> _social(
    Future<bool> Function({required BuildContext context}) signIn,
    void Function(bool) loading,
  ) async {
    if (_busy) return;
    setState(() => loading(true));
    final success = await signIn(context: context);
    if (!mounted) return;
    setState(() => loading(false));
    if (success) _toAuthGate();
  }

  @override
  Widget build(BuildContext context) => onboardingTheme(
    Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: context.vivordoColors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        // Cancelled on dispose so backing out never offers to save a
        // password for an account that wasn't created.
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                const Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _purple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: context.vivordoColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 22),
                _field(
                  controller: _name,
                  hint: 'First name',
                  icon: CupertinoIcons.person,
                  capitalization: TextCapitalization.words,
                  autofill: AutofillHints.givenName,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter your first name' : null,
                ),
                _field(
                  controller: _email,
                  hint: 'you@email.com',
                  icon: CupertinoIcons.envelope,
                  keyboard: TextInputType.emailAddress,
                  autofill: AutofillHints.email,
                  validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(v ?? '')
                      ? null
                      : 'Enter a valid email',
                ),
                _field(
                  controller: _password,
                  hint: 'Password',
                  icon: CupertinoIcons.lock,
                  obscure: !_showPassword,
                  autofill: AutofillHints.newPassword,
                  action: TextInputAction.done,
                  suffix: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPassword
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                      color: context.vivordoColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                if (_password.text.isNotEmpty || _passwordError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final r in _passwordRequirements)
                          _Requirement(r.label, r.isMet(_password.text)),
                      ],
                    ),
                  ),
                if (_passwordError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      _passwordError!,
                      style: const TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                _button(
                  label: 'Create account',
                  loading: _emailLoading,
                  color: _purple,
                  onPressed: _createWithEmail,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(color: context.vivordoColors.border),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(
                            color: context.vivordoColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: context.vivordoColors.border),
                      ),
                    ],
                  ),
                ),
                if (_showApple) ...[
                  _button(
                    label: 'Continue with Apple',
                    loading: _appleLoading,
                    // Apple's button is white on a dark page.
                    color: _dark ? Colors.white : Colors.black,
                    foreground: _dark ? Colors.black : Colors.white,
                    leading: const Icon(Icons.apple, size: 25),
                    onPressed: () => _social(
                      AuthService.signInWithApple,
                      (v) => _appleLoading = v,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _button(
                  label: 'Continue with Google',
                  loading: _googleLoading,
                  color: const Color(0xFF4285F4),
                  leading: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SvgPicture.asset(
                      'assets/google_g_logo.svg',
                      width: 20,
                      height: 20,
                    ),
                  ),
                  onPressed: () => _social(
                    AuthService.signInWithGoogle,
                    (v) => _googleLoading = v,
                  ),
                ),
                const SizedBox(height: 20),
                const TermsAgreement(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    bool obscure = false,
    String? autofill,
    TextInputAction action = TextInputAction.next,
    Widget? suffix,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      obscureText: obscure,
      autofillHints: autofill == null ? null : [autofill],
      textInputAction: action,
      autocorrect: false,
      validator: validator,
      style: TextStyle(color: context.vivordoColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: context.vivordoColors.textSecondary.withValues(alpha: .6),
        ),
        prefixIcon: Icon(
          icon,
          color: context.vivordoColors.textSecondary.withValues(alpha: .6),
          size: 20,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.vivordoColors.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.vivordoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF3B30)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF3B30), width: 1.5),
        ),
      ),
    ),
  );

  Widget _button({
    required String label,
    required bool loading,
    required Color color,
    required VoidCallback onPressed,
    Color foreground = Colors.white,
    Widget? leading,
  }) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: _busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: .62),
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CupertinoActivityIndicator(color: foreground, radius: 11),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 10)],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    ),
  );
}

class _Requirement extends StatelessWidget {
  const _Requirement(this.label, this.met);

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met
        ? context.vivordoColors.success
        : context.vivordoColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
