import 'package:flutter/material.dart';
import '../safety/safety_dialogs.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _pushNotifications = true;
  bool _darkMode = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C162E),
      title: const Text('Settings', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Push Notifications', style: TextStyle(color: Colors.white)),
            value: _pushNotifications,
            onChanged: (value) => setState(() => _pushNotifications = value),
            activeColor: const Color(0xFFFF4B72),
          ),
          SwitchListTile(
            title: const Text('Dark Mode', style: TextStyle(color: Colors.white)),
            value: _darkMode,
            onChanged: (value) => setState(() => _darkMode = value),
            activeColor: const Color(0xFFFF4B72),
          ),
          ListTile(
            title: const Text('Language', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white60),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Privacy', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white60),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Safety Center', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white60),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => const SafetyCenterDialog(),
              );
            },
          ),
          ListTile(
            title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.red),
            onTap: () {
              Navigator.pop(context);
              _showDeleteAccountDialog(context);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Color(0xFFFF4B72))),
        ),
      ],
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
        content: const Text(
          'This action cannot be undone. All your data will be permanently deleted.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle account deletion
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
