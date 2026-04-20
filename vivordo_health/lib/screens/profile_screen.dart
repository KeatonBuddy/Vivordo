import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/models/user_model.dart';
import 'login_screen.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});


  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}


class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _appleHealthConnected = true;
  bool _pushNotifications = true;
  bool _autoSyncData = true;
  bool _seeding = false; // for the seed demo data button

  bool _isEmailVerificationSignOut = false;

  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    bool isFirstEmission = true;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (isFirstEmission) {
        isFirstEmission = false;
        return;
      }
      if (user == null && mounted) {
        final message = _isEmailVerificationSignOut
            ? 'Email verified! Please log in again with your new email.'
            : 'You have been signed out.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkEmailSync();
    }
  }

  Future<void> _checkEmailSync() async {
    final didLogout = await UserService.syncEmailWithAuth();
    if (didLogout) {
      _isEmailVerificationSignOut = true;
    }
  }

  void _showEditDialog(
    BuildContext context,
    String field,
    String currentValue,
  ) {
    final TextEditingController controller = TextEditingController(
      text: currentValue,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $field'),
          content: field == "Password"
              ? TextField(
                  controller: controller,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'New Password'),
                )
              : TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: field),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (field == "Name") {
                    await UserService.updateDisplayName(controller.text);
                  } else if (field == "Email") {
                    await UserService.updateEmail(controller.text);
                  } else if (field == "Password") {
                    await UserService.updatePassword(controller.text);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    final message = field == "Email"
                        ? 'Verification email sent to ${controller.text}. Tap the link to confirm your new email.'
                        : '$field updated successfully!';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                } on FirebaseAuthException catch (e) {
                  String errorMessage = 'Error: ${e.message}';
                  if (e.code == 'requires-recent-login') {
                    errorMessage = 'For security, please log out and log back in to change your $field.';
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMessage)),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<User?>();


    // Guard: show spinner while authStateChanges listener handles navigation
    if (authUser == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C69EF)),
        ),
      );
    }


    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF7C69EF)),
            ),
          );
        }


        // Show spinner not error — this state can be hit during sign-out transition
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF7C69EF)),
            ),
          );
        }


        final userData = UserModel.fromMap(
          snapshot.data!.data() as Map<String, dynamic>,
          snapshot.data!.id,
        );


        final String? pendingEmail =
            (snapshot.data!.data() as Map<String, dynamic>)['pendingEmail'];


        return Scaffold(
          backgroundColor: const Color(0xFFF9F7FF),
          body: SingleChildScrollView(
            child: Column(
              children: [
                // --- Profile Header ---
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 250,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C69EF),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(40),
                          bottomRight: Radius.circular(40),
                        ),
                      ),
                      child: SafeArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 60,
                      child: Column(
                        children: [
                          const Text(
                            "Profile",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white24,
                            backgroundImage: userData.photoUrl != null
                                ? NetworkImage(userData.photoUrl!)
                                : null,
                            child: userData.photoUrl == null
                                ? const Icon(
                                    Icons.person_outline,
                                    size: 50,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),


                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [


                      // --- Pending Email Verification Banner ---
                      if (pendingEmail != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.mail_outline,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Verify your new email: $pendingEmail\nCheck your inbox and tap the link.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],


                      // --- Section: Account Information ---
                      _buildSectionCard(
                        icon: Icons.person_outline,
                        title: "Account Information",
                        children: [
                          _buildInfoTile(
                            "Name",
                            userData.displayName ?? "Set your name",
                            onEdit: () => _showEditDialog(
                              context,
                              "Name",
                              userData.displayName ?? "",
                            ),
                          ),
                          const Divider(),
                          _buildInfoTile(
                            "Email",
                            userData.email ?? "Set your email",
                            onEdit: () => _showEditDialog(
                              context,
                              "Email",
                              userData.email ?? "",
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              "Password",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: const Text(
                              "••••••••",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                _showEditDialog(context, "Password", ""),
                          ),
                        ],
                      ),


                      const SizedBox(height: 24),


                      // --- Section: Health Data Permissions ---
                      _buildSectionHeader(
                        Icons.health_and_safety_outlined,
                        "Health Data Permissions",
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Choose which Apple Health metrics Vivordo can read. "
                        "Turning off a metric immediately removes its data from our servers.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<Map<String, bool>>(
                        stream: HealthService().consentStream(),
                        builder: (context, snap) {
                          final consent = snap.data ?? {};
                          return Container(
                            decoration: _cardDecoration(),
                            child: Column(
                              children: [
                                for (int i = 0; i < kHealthMetrics.length; i++) ...[
                                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                                  _buildHealthConsentTile(
                                    kHealthMetrics[i],
                                    consent[kHealthMetrics[i].key] == true,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),


                      const SizedBox(height: 24),


                      // --- Section: App Settings ---
                      _buildSectionHeader(
                        Icons.settings_outlined,
                        "App Settings",
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: _cardDecoration(),
                        child: Column(
                          children: [
                            _buildSettingsToggle(
                              "Push Notifications",
                              "Daily reminders & insights",
                              Icons.notifications_none,
                              _pushNotifications,
                              (val) =>
                                  setState(() => _pushNotifications = val),
                            ),
                            _buildSettingsToggle(
                              "Auto Sync Health Data",
                              "Sync every hour",
                              Icons.favorite_border,
                              _autoSyncData,
                              (val) => setState(() => _autoSyncData = val),
                            ),
                          ],
                        ),
                      ),


                      const SizedBox(height: 24),

                      // --- Seed Demo Data Button ---
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _seeding
                              ? null
                              : () async {
                                  setState(() => _seeding = true);
                                  try {
                                    await MetricsService.seedDemoData();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('✓ 30 days of demo data seeded!'),
                                          backgroundColor: Color(0xFF4ADE80),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Seed failed: $e'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => _seeding = false);
                                  }
                                },
                          icon: _seeding
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.science_outlined, color: Color(0xFF7C69EF)),
                          label: Text(
                            _seeding ? 'Seeding...' : 'Seed Demo Data (30 days)',
                            style: const TextStyle(color: Color(0xFF7C69EF), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEDE9FE),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // --- Logout Button ---
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            _isEmailVerificationSignOut = false;
                            await FirebaseAuth.instance.signOut();
                          },
                          icon: const Icon(Icons.logout, color: Colors.redAccent),
                          label: const Text(
                            'Log Out',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFEEEE),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Health consent tile ──────────────────────────────────────────────────

  Widget _buildHealthConsentTile(HealthMetricDef metric, bool isEnabled) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isEnabled
              ? const Color(0xFFEDE9FE)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          _metricIcon(metric.key),
          color: isEnabled ? const Color(0xFF7C69EF) : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        metric.label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isEnabled ? const Color(0xFF2D3142) : Colors.grey,
        ),
      ),
      subtitle: Text(
        metric.description,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Switch(
        value: isEnabled,
        activeColor: const Color(0xFF7C69EF),
        onChanged: (val) async {
          if (val) {
            final granted = await HealthService().enableMetric(metric.key);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(granted
                    ? '✓ ${metric.label} connected — syncing 30 days'
                    : '${metric.label} permission was not granted'),
                backgroundColor: granted ? const Color(0xFF4ADE80) : Colors.orange,
              ));
            }
          } else {
            await HealthService().disableMetric(metric.key);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${metric.label} data removed from Vivordo'),
              ));
            }
          }
        },
      ),
    );
  }

  IconData _metricIcon(String key) {
    switch (key) {
      case 'steps':          return Icons.directions_walk;
      case 'heart_rate':     return Icons.favorite_border;
      case 'sleep':          return Icons.bedtime_outlined;
      case 'hrv':            return Icons.monitor_heart_outlined;
      case 'blood_oxygen':   return Icons.water_drop_outlined;
      case 'active_calories':return Icons.local_fire_department_outlined;
      default:               return Icons.health_and_safety_outlined;
    }
  }

  // ─── Helper Widgets ────────────────────────────────────────────────────────

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(icon, title),
        const SizedBox(height: 12),
        Container(
          decoration: _cardDecoration(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoTile(
    String label,
    String value, {
    VoidCallback? onEdit,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(color: Colors.grey, fontSize: 14),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      trailing: onEdit != null
          ? IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              onPressed: onEdit,
            )
          : null,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF7C69EF)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3142),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildDeviceTile(
    String name,
    String status,
    IconData icon,
    Color iconColor, {
    Color? statusColor,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          color: statusColor ?? Colors.grey,
        ),
      ),
      trailing: trailing,
    );
  }

  Widget _buildSettingsToggle(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF7C69EF), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Switch(
        value: value,
        activeColor: const Color(0xFF7C69EF),
        onChanged: onChanged,
      ),
    );
  }
}