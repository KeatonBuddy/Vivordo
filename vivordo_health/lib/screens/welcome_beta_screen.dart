import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'onboarding_flow_screen.dart' show onboardingLight;
import 'signup_screen.dart';

/// The first screen of a new account, from Login's "Create account".
class WelcomeBetaScreen extends StatelessWidget {
  const WelcomeBetaScreen({super.key});

  static const _purple = VivordoTheme.brand;

  @override
  Widget build(BuildContext context) => onboardingLight(
    Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The login screen's wordmark; the image has wide margins.
                    ClipRect(
                      child: SizedBox(
                        height: 90,
                        child: OverflowBox(
                          maxHeight: 270,
                          child: Image.asset(
                            'assets/vivordo_logo_long.png',
                            width: 340,
                            height: 270,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Know your energy before your day uses it',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Vivordo reads your sleep, body and calendar to show what '
                      "you have, what's ahead and how your health is trending.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEDFE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Beta · thanks for testing',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3C3489),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Get started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'I have an account',
                  style: TextStyle(color: _purple, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
