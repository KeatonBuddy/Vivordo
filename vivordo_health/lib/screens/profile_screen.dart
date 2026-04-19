import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/models/user_model.dart';
import 'login_screen.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';
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


                      // --- Section: Connected Devices ---
                      _buildSectionHeader(
                        Icons.phone_iphone_outlined,
                        "Connected Devices",
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: Column(
                          children: [
                            _buildDeviceTile(
                              "Apple Health",
                              "Connected",
                              Icons.favorite,
                              Colors.pink,
                              trailing: Switch(
                                value: _appleHealthConnected,
                                activeColor: const Color(0xFF7C69EF),
                                onChanged: (val) => setState(
                                    () => _appleHealthConnected = val),
                              ),
                            ),
                            const Divider(height: 32),
                            _buildDeviceTile(
                              "Apple Watch Series 9",
                              "Connected • Synced 5 min ago",
                              Icons.watch,
                              Colors.black,
                              statusColor: Colors.green,
                            ),
                            const Divider(height: 32),
                            _buildDeviceTile(
                              "iPhone 15 Pro",
                              "Connected • Active",
                              Icons.phone_iphone,
                              Colors.blue,
                              statusColor: Colors.green,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {},
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  "Add New Device",
                                  style: TextStyle(color: Colors.black87),
                                ),
                              ),
                            ),
                          ],
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