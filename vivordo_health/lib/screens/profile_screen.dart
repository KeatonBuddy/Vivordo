import 'package:flutter/material.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
    String _name = "Sarah Mitchell";
    String _email = "sarah.mitchell@email.com";

    void _showEditDialog(BuildContext context, String field, String currentValue) {
      final TextEditingController controller = TextEditingController(text: currentValue);
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Edit ' + field),
            content: field == "Password"
                ? TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New Password'),
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
                onPressed: () {
                  setState(() {
                    if (field == "Name") {
                      _name = controller.text;
                    } else if (field == "Email") {
                      _email = controller.text;
                    }
                    // Password change logic can be added here if needed
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$field updated!')),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    }
  // Toggle states for App Settings
  bool _appleHealthConnected = true;
  bool _pushNotifications = true;
  bool _autoSyncData = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7FF),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  height: 200,
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
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 60,
                  child: Column(
                    children: const [
                      Text(
                        "Profile",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 15),
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.person_outline, size: 50, color: Colors.white),
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
                  // Section: Account Information
                  _buildSectionCard(
                    icon: Icons.person_outline,
                    title: "Account Information",
                    children: [
                      _buildInfoTile("Name", _name, onEdit: () => _showEditDialog(context, "Name", _name)),
                      const Divider(),
                      _buildInfoTile("Email", _email, onEdit: () => _showEditDialog(context, "Email", _email)),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Password", style: TextStyle(color: Colors.grey, fontSize: 14)),
                        subtitle: const Text("••••••••", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showEditDialog(context, "Password", ""),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Section: Connected Devices
                  _buildSectionHeader(Icons.phone_iphone_outlined, "Connected Devices"),
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
                            onChanged: (val) => setState(() => _appleHealthConnected = val),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Add New Device", style: TextStyle(color: Colors.black87)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Section: App Settings
                  _buildSectionHeader(Icons.settings_outlined, "App Settings"),
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
                          (val) => setState(() => _pushNotifications = val),
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

                  const SizedBox(height: 32),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      label: const Text("Log Out", style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFEBEE),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  }

  // --- Helper Widgets ---

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF7C69EF)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSectionCard({required IconData icon, required String title, required List<Widget> children}) {
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w500)),
      trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF7C69EF)), onPressed: onEdit),
    );
  }

  Widget _buildDeviceTile(String name, String sub, IconData icon, Color iconColor, {Widget? trailing, Color? statusColor}) {
    return Row(
      children: [
        CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(icon, color: iconColor)),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  if (statusColor != null) CircleAvatar(radius: 4, backgroundColor: statusColor),
                  if (statusColor != null) const SizedBox(width: 5),
                  Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSettingsToggle(String title, String sub, IconData icon, bool val, Function(bool) onChanged) {
    return SwitchListTile(
      value: val,
      onChanged: onChanged,
      secondary: Icon(icon, color: Colors.grey),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      activeColor: const Color(0xFF7C69EF),
    );
  }

  Widget _buildDataCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF7C69EF))),
        ],
      ),
    );
  }
}