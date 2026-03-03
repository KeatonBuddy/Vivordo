import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/src/services/user_service.dart';
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
  bool _appleHealthConnected = true;
  bool _pushNotifications = true;
  bool _autoSyncData = true;


  bool _isEmailVerificationSignOut = false;


  StreamSubscription<User?>? _authSubscription;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);


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
          color: Colors.black.withOpacity(0.05),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF7C69EF)),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }


  Widget _buildInfoTile(String label, String value, {VoidCallback? onEdit}) {
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
          color: Colors.black,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(
          Icons.edit_outlined,
          size: 20,
          color: Color(0xFF7C69EF),
        ),
        onPressed: onEdit,
      ),
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
        CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  if (statusColor != null)
                    CircleAvatar(radius: 4, backgroundColor: statusColor),
                  if (statusColor != null) const SizedBox(width: 5),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }


  Widget _buildSettingsToggle(
    String title,
    String sub,
    IconData icon,
    bool val,
    Function(bool) onChanged,
  ) {
    return SwitchListTile(
      value: val,
      onChanged: onChanged,
      secondary: Icon(icon, color: Colors.grey),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      activeColor: const Color(0xFF7C69EF),
    );
  }
}
