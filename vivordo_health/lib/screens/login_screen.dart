import 'package:flutter/material.dart';
import 'main_navigation.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryPurple = const Color(0xFF857DEA);
    final Color bgPurple = const Color(0xFFFBFaff);
    final Color textGrey = const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgPurple,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // --- Logo Section ---
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: primaryPurple,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: primaryPurple.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Vivordo',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: primaryPurple,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'See your Stress. Find your balance.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 40),

                // --- Login Card ---
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Email'),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: _inputDecoration(
                          hintText: 'you@example.com',
                          icon: Icons.mail_outline,
                          primaryColor: primaryPurple,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('Password'),
                      const SizedBox(height: 8),
                      TextField(
                        obscureText: true,
                        decoration: _inputDecoration(
                          hintText: '••••••••',
                          icon: Icons.lock_outline,
                          primaryColor: primaryPurple,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Reset Password Link
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () {},
                          child: Text(
                            'Reset Password',
                            style: TextStyle(
                              color: primaryPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationScreen()));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                            shadowColor: primaryPurple.withOpacity(0.4),
                          ),
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // OR Divider
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Biometric Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.fingerprint, color: Colors.black87),
                          label: const Text(
                            'Use Biometric Login',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Footer ---
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock, size: 14, color: Colors.amber[700]),
                    const SizedBox(width: 6),
                    Text(
                      'All data is encrypted and securely stored.',
                      style: TextStyle(color: textGrey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(color: textGrey),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/signup');
                      },
                      child: Text(
                        "Create Account",
                        style: TextStyle(
                          color: primaryPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    required Color primaryColor,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
    );
  }
}