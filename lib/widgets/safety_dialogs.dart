import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SafetyCenterDialog extends StatelessWidget {
  const SafetyCenterDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1C162E),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Safety Center',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SafetyOption(
                icon: Icons.block_rounded,
                title: 'Blocked Users',
                subtitle: 'Manage your blocked users',
                onTap: () {
                  Navigator.pop(context);
                  _showBlockedUsers(context);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.flag_rounded,
                title: 'Report a User',
                subtitle: 'Report inappropriate behavior',
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog(context);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.share_rounded,
                title: 'Share My Date',
                subtitle: 'Share your plans with trusted contacts',
                onTap: () {
                  Navigator.pop(context);
                  _showShareDateDialog(context);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.verified_user_rounded,
                title: 'Photo Verification',
                subtitle: 'Verify your profile photo',
                onTap: () {
                  Navigator.pop(context);
                  _showVerificationDialog(context);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.help_outline_rounded,
                title: 'Safety Tips',
                subtitle: 'Learn how to stay safe',
                onTap: () {
                  Navigator.pop(context);
                  context.go('/safety-center');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockedUsers(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Blocked Users',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your blocked users list will appear here.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFFFF4B72)),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Report a User',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select a reason for reporting:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ..._reportReasons.map(
              (reason) => ListTile(
                title: Text(
                  reason,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Report submitted: $reason'),
                      backgroundColor: const Color(0xFF4CAF50),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<String> _reportReasons = [
    'Inappropriate photos',
    'Harassment or bullying',
    'Spam or scam',
    'Fake profile',
    'Inappropriate messages',
    'Underage user',
    'Other',
  ];
  void _showShareDateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Share My Date',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Contact Name',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'Who are you meeting?',
                hintStyle: TextStyle(color: Colors.white38),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Venue',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'Where are you meeting?',
                hintStyle: TextStyle(color: Colors.white38),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Time',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'When?',
                hintStyle: TextStyle(color: Colors.white38),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4B72),
            ),
            child: const Text('Share', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Photo Verification',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Upload a selfie to verify your profile. This helps ensure a safe community.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4B72),
            ),
            child: const Text(
              'Upload Photo',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SafetyOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2E244A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B72).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFFF4B72), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
