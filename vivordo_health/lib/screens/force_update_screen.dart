import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Full-screen, non-dismissible block shown when VersionGateService
/// determines the installed app version is below the Remote Config minimum.
/// There's deliberately no way out of this screen except updating —
/// PopScope(canPop: false) blocks the Android back gesture/button.
class ForceUpdateScreen extends StatelessWidget {
  final String updateUrl;

  const ForceUpdateScreen({super.key, required this.updateUrl});

  static const Color accentPurple = VivordoTheme.brand;

  Future<void> _openUpdateLink() async {
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.page,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: accentPurple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: accentPurple,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Update required',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "You're on a version of Vivordo Health that's no longer "
                  'supported. Update to keep using the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: updateUrl.isEmpty ? null : _openUpdateLink,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: accentPurple.withValues(
                        alpha: 0.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Update now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
