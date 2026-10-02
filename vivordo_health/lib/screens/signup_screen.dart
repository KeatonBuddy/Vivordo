import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vivordo_health/src/services/auth_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import 'onboarding_flow_screen.dart' show onboardingLight;

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
const _ink = Color(0xFF1C1C1E);
const _grey = Color(0xFF8E8E93);
const _line = Color(0xFFE5E5EA);

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
    if (success) _toAuthGate();
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
  Widget build(BuildContext context) => onboardingLight(
    Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              const Text(
                'ACCOUNT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .9,
                  color: _purple,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create your account',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 22),
              _field(
                controller: _name,
                hint: 'First name',
                icon: Icons.person_outline_rounded,
                capitalization: TextCapitalization.words,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter your first name' : null,
              ),
              _field(
                controller: _email,
                hint: 'you@email.com',
                icon: Icons.mail_outline_rounded,
                keyboard: TextInputType.emailAddress,
                validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(v ?? '')
                    ? null
                    : 'Enter a valid email',
              ),
              _field(
                controller: _password,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: !_showPassword,
                suffix: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _grey,
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFFD1D1D6))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(color: _grey)),
                    ),
                    Expanded(child: Divider(color: Color(0xFFD1D1D6))),
                  ],
                ),
              ),
              if (_showApple) ...[
                _button(
                  label: 'Continue with Apple',
                  loading: _appleLoading,
                  color: Colors.black,
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
            ],
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
    Widget? suffix,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      obscureText: obscure,
      autocorrect: false,
      validator: validator,
      style: const TextStyle(color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
        prefixIcon: Icon(icon, color: const Color(0xFFC7C7CC), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
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
    Widget? leading,
  }) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: _busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: .62),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
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
    final color = met ? const Color(0xFF34C759) : _grey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
