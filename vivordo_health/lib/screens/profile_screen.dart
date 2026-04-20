import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'package:vivordo_health/src/models/user_model.dart';
import 'login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';




class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});


  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}


class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _pushNotifications = true;
  bool _autoSyncData = true;

  bool _isEmailVerificationSignOut = false;

  // Loading states for HealthKit actions
  bool _isConnectingAll = false;           // "Connect Apple Health" button
  String? _togglingMetric;                 // key of metric currently being toggled

  StreamSubscription<User?>? _authSubscription;

  // Cached Firestore stream — MUST be created once in initState and reused.
  // If we create it inside build() a new stream object is made on every
  // rebuild, StreamBuilder detects the change, resets to 'waiting', and the
  // screen spins forever.
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    _userDocStream = uid != null
        ? FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots()
        : const Stream.empty();


    // Skip the first emission — it just reflects current login state, not a change
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
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    });


    // NOTE: We do NOT call _checkEmailSync() here anymore.
    // Cleanup of pendingEmail now happens in AuthService.emailLogin,
    // so by the time the user reaches this screen it is already clean.
  }


  @override
  void dispose() {
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only check when the user returns to the app — this handles the case
    // where they tap the verification link while the app is already open
    if (state == AppLifecycleState.resumed) {
      _checkEmailSync();
    }
  }


  Future<void> _checkEmailSync() async {
    final didLogout = await UserService.syncEmailWithAuth();
    if (didLogout) {
      _isEmailVerificationSignOut = true;
    }
    // Navigation handled by authStateChanges listener
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
                    errorMessage =
                        'For security, please log out and log back in to change your $field.';
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
    // Build is driven entirely by _userDocStream which was cached in initState.
    // We do NOT call context.watch<User?>() here — that triggers extra rebuilds
    // and can cause a spinner loop because the Provider's initialData is null.
    // Sign-out is handled by the _authSubscription listener in initState.
    return StreamBuilder<DocumentSnapshot>(
      stream: _userDocStream,
      builder: (context, snapshot) {
        // Still loading first snapshot
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF7C69EF)),
            ),
          );
        }

        // Firestore error — show message with back button so user isn't stuck
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.grey, size: 40),
                  const SizedBox(height: 12),
                  const Text('Could not load profile'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          );
        }

        // Doc missing — auto-create it and wait for the stream to update
        final authUser = FirebaseAuth.instance.currentUser;
        if (!snapshot.hasData || !snapshot.data!.exists) {
          if (authUser != null) UserService.createUser(authUser);
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF7C69EF)),
            ),
          );
        }


        // Extract everything from the ONE snapshot — no extra Firestore listeners.
        final rawData     = snapshot.data!.data() as Map<String, dynamic>;
        final userData    = UserModel.fromMap(rawData, snapshot.data!.id);
        final pendingEmail = rawData['pendingEmail'] as String?;

        // Read consent from the same doc — avoids opening extra listeners.
        final consentRaw   = rawData['healthKitConsent'] as Map? ?? {};
        final consent      = consentRaw.map((k, v) => MapEntry(k.toString(), v == true));
        final anyConsented = consent.values.any((v) => v);


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


                      // --- Section: Connected Devices ---
                      _buildSectionHeader(
                        Icons.phone_iphone_outlined,
                        "Connected Devices",
                      ),
                      const SizedBox(height: 12),
                      // Connected Devices — reads consent from _userDocStream snapshot,
                      // no extra Firestore listener needed.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: anyConsented
                                        ? const Color(0xFFFFE4EC)
                                        : Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.favorite,
                                    size: 18,
                                    color: anyConsented
                                        ? Colors.pinkAccent
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Apple Health",
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2D3142),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        anyConsented
                                            ? "Connected — syncing data"
                                            : "Not connected",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: anyConsented
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: anyConsented
                                        ? const Color(0xFFE6F4EA)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    anyConsented ? "Active" : "Off",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: anyConsented
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // "Connect Apple Health" button — only visible when not connected
                            if (!anyConsented) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isConnectingAll
                                      ? null
                                      : () async {
                                          setState(() => _isConnectingAll = true);
                                          try {
                                            await HealthService().enableAll();
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Could not connect: $e')),
                                              );
                                            }
                                          } finally {
                                            if (mounted) setState(() => _isConnectingAll = false);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C69EF),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: const Color(0xFFB8B0F8),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: _isConnectingAll
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.health_and_safety_outlined, size: 18),
                                            SizedBox(width: 8),
                                            Text(
                                              "Connect Apple Health",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Grants read-only access to all health metrics at once",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // --- Section: Health Data Permissions ---
                      _buildSectionHeader(
                        Icons.health_and_safety_outlined,
                        "Health Data Permissions",
                      ),
                      const SizedBox(height: 12),
                      // Reads from _userDocStream snapshot — no extra listener.
                      Container(
                        decoration: _cardDecoration(),
                        child: Column(
                          children: kHealthMetrics.map((metric) {
                            final enabled = consent[metric.key] == true;
                            final isToggling = _togglingMetric == metric.key;
                            return Column(
                              children: [
                                SwitchListTile(
                                  value: enabled,
                                  activeColor: const Color(0xFF7C69EF),
                                  // null disables the toggle while it's loading
                                  onChanged: isToggling
                                      ? null
                                      : (val) async {
                                          setState(() => _togglingMetric = metric.key);
                                          try {
                                            if (val) {
                                              await HealthService().enableMetric(metric.key);
                                            } else {
                                              await HealthService().disableMetric(metric.key);
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Error: $e')),
                                              );
                                            }
                                          } finally {
                                            if (mounted) setState(() => _togglingMetric = null);
                                          }
                                        },
                                  title: Text(
                                    metric.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isToggling ? Colors.grey : const Color(0xFF2D3142),
                                    ),
                                  ),
                                  subtitle: Text(
                                    isToggling
                                        ? (enabled ? 'Removing access…' : 'Requesting access…')
                                        : metric.description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isToggling
                                          ? const Color(0xFF7C69EF)
                                          : Colors.grey,
                                    ),
                                  ),
                                  secondary: isToggling
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF7C69EF),
                                          ),
                                        )
                                      : Icon(
                                          _metricIcon(metric.key),
                                          color: enabled
                                              ? const Color(0xFF7C69EF)
                                              : Colors.grey,
                                          size: 20,
                                        ),
                                ),
                                if (metric != kHealthMetrics.last)
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          }).toList(),
                        ),
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
                              "Syncs every 3 minutes in background",
                              Icons.favorite_border,
                              _autoSyncData,
                              (val) => setState(() => _autoSyncData = val),
                            ),
                          ],
                        ),
                      ),


                      const SizedBox(height: 32),


                      // --- Logout Button ---
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                            // Navigation handled by authStateChanges listener
                          },
                          icon: const Icon(
                            Icons.logout,
                            color: Colors.redAccent,
                          ),
                          label: const Text(
                            "Log Out",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFEBEE),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
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


  // --- Helper Widgets ---


  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }


  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF7C69EF)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }


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


  Widget _buildDeviceTile(
    String name,
    String sub,
    IconData icon,
    Color iconColor, {
    Widget? trailing,
    Color? statusColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF7C69EF)),
        const SizedBox(width: 8),
        Text(
          name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3142),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsToggle(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: Colors.grey),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      activeColor: const Color(0xFF7C69EF),
    );
  }

  IconData _metricIcon(String key) {
    switch (key) {
      // Activity
      case 'steps':              return Icons.directions_walk_rounded;
      case 'active_calories':    return Icons.local_fire_department_rounded;
      case 'exercise_time':      return Icons.fitness_center_rounded;
      case 'distance':           return Icons.straighten_rounded;
      case 'flights_climbed':    return Icons.stairs_rounded;
      // Heart
      case 'heart_rate':         return Icons.favorite_rounded;
      case 'resting_heart_rate': return Icons.favorite_border_rounded;
      case 'hrv':                return Icons.show_chart_rounded;
      // Breathing / Vitals
      case 'blood_oxygen':       return Icons.air_rounded;
      case 'respiratory_rate':   return Icons.wind_power_rounded;
      // Sleep
      case 'sleep':              return Icons.bedtime_rounded;
      // Body
      case 'weight':             return Icons.monitor_weight_rounded;
      case 'body_fat':           return Icons.percent_rounded;
      // Mind
      case 'mindfulness':        return Icons.self_improvement_rounded;
      // Fitness
      case 'vo2max':             return Icons.speed_rounded;
      default:                   return Icons.monitor_heart_outlined;
    }
  }
}