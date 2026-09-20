import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/weekend_provider.dart';
import '../../config/supabase_config.dart';
import '../../repositories/safety_repository.dart';

class SafetyCenterScreen extends ConsumerStatefulWidget {
  const SafetyCenterScreen({super.key});
  @override
  ConsumerState<SafetyCenterScreen> createState() => _SafetyCenterScreenState();
}

class _SafetyCenterScreenState extends ConsumerState<SafetyCenterScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130E20),
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: const Text(
          'Safety Center',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emergency banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF4B72), Color(0xFFFF6B45)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emergency_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Emergency Assistance',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'If you\'re in immediate danger, contact emergency services.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _launchPhone('112'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFFF4B72),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Call 112',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Safety Tools
              _buildSectionTitle('Safety Tools'),
              const SizedBox(height: 12),
              _SafetyToolCard(
                icon: Icons.block_rounded,
                title: 'Blocked Users',
                subtitle: 'Manage users you\'ve blocked',
                color: const Color(0xFFFF4B72),
                onTap: () => _showBlockedUsers(context),
              ),
              _SafetyToolCard(
                icon: Icons.flag_rounded,
                title: 'Report a User',
                subtitle: 'Report inappropriate behavior',
                color: Colors.red,
                onTap: () => _showReportDialog(context),
              ),
              _SafetyToolCard(
                icon: Icons.share_rounded,
                title: 'Share My Date',
                subtitle: 'Share plans with trusted contacts',
                color: const Color(0xFFFF9966),
                onTap: () => _showShareDateDialog(context),
              ),
              _SafetyToolCard(
                icon: Icons.verified_user_rounded,
                title: 'Photo Verification',
                subtitle: 'Verify your profile photo',
                color: const Color(0xFF4CAF50),
                onTap: () => _showVerificationDialog(context),
              ),
              _SafetyToolCard(
                icon: Icons.security_rounded,
                title: 'Account Security',
                subtitle: 'Manage sessions and passwords',
                color: const Color(0xFF9C27B0),
                onTap: () => _showAccountSecurity(context),
              ),
              _SafetyToolCard(
                icon: Icons.privacy_tip_rounded,
                title: 'Privacy Controls',
                subtitle: 'Manage your visibility and data',
                color: const Color(0xFF00BCD4),
                onTap: () => _showPrivacyControls(context),
              ),
              const SizedBox(height: 24),

              // Safety Tips
              _buildSectionTitle('Safety Tips'),
              const SizedBox(height: 12),
              _SafetyTipCard(
                title: 'Meet in Public Places',
                description:
                    'Always meet matches in well-lit, public locations for first dates.',
                icon: Icons.place_rounded,
              ),
              _SafetyTipCard(
                title: 'Tell Someone Your Plans',
                description:
                    'Share your date details with a friend or family member.',
                icon: Icons.share_rounded,
              ),
              _SafetyTipCard(
                title: 'Trust Your Instincts',
                description:
                    'If something feels off, leave the situation immediately.',
                icon: Icons.psychology_rounded,
              ),
              _SafetyTipCard(
                title: 'Keep Drinks in Sight',
                description:
                    'Never leave your drink unattended and don\'t accept drinks from strangers.',
                icon: Icons.local_bar_rounded,
              ),
              _SafetyTipCard(
                title: 'Video Chat First',
                description: 'Consider a video call before meeting in person.',
                icon: Icons.videocam_rounded,
              ),
              _SafetyTipCard(
                title: 'Protect Personal Info',
                description:
                    'Don\'t share your address, financial info, or workplace until you trust someone.',
                icon: Icons.lock_rounded,
              ),
              const SizedBox(height: 24),

              // Resources
              _buildSectionTitle('Helpful Resources'),
              const SizedBox(height: 12),
              _ResourceCard(
                title: 'Dating Safety Guide',
                description: 'Comprehensive guide to staying safe while dating',
                icon: Icons.menu_book_rounded,
                onTap: () => _launchUrl(
                  'https://www.rainn.org/articles/staying-safe-online-dating',
                ),
              ),
              _ResourceCard(
                title: 'Report Scams & Fraud',
                description: 'Learn how to identify and report romance scams',
                icon: Icons.warning_rounded,
                onTap: () => _launchUrl(
                  'https://www.consumer.ftc.gov/articles/romance-scams',
                ),
              ),
              _ResourceCard(
                title: 'Mental Health Support',
                description: 'Resources for emotional wellbeing',
                icon: Icons.favorite_rounded,
                onTap: () => _launchUrl('https://findahelpline.com/'),
              ),
              const SizedBox(height: 24),

              // App-specific safety features
              _buildSectionTitle('Weekend Safety Features'),
              const SizedBox(height: 12),
              _FeatureCard(
                title: 'Photo Verification',
                description:
                    'Verified profiles show a green badge. Request verification from matches.',
                icon: Icons.verified_rounded,
                color: const Color(0xFF4CAF50),
              ),
              _FeatureCard(
                title: 'Trust Score',
                description:
                    'Each profile has a trust score based on activity and community feedback.',
                icon: Icons.shield_rounded,
                color: const Color(0xFFFF9966),
              ),
              _FeatureCard(
                title: 'Crossed Paths Privacy',
                description:
                    'Location data is converted to geohash buckets — exact coordinates never shared.',
                icon: Icons.location_on_rounded,
                color: const Color(0xFF00BCD4),
              ),
              _FeatureCard(
                title: 'In-App Reporting',
                description:
                    'Report any profile, message, or photo directly from the app.',
                icon: Icons.flag_rounded,
                color: Colors.red,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    );
  }

  void _showBlockedUsers(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<String>>(
        future: _blockedUserIds(),
        builder: (context, snapshot) {
          final blocked = snapshot.data ?? const [];
          return AlertDialog(
            backgroundColor: const Color(0xFF1C162E),
            title: const Text(
              'Blocked Users',
              style: TextStyle(color: Colors.white),
            ),
            content: blocked.isEmpty
                ? const Text(
                    'No blocked users yet. Use the block button on any profile or in chat.',
                    style: TextStyle(color: Colors.white70),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${blocked.length} blocked',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      ...blocked.map((id) => ListTile(
                            title: Text(
                              id,
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.lock_open_rounded,
                                color: Colors.white70,
                              ),
                              onPressed: () async {
                                final repo = SafetyRepository();
                                await repo.unblockUser(
                                  SupabaseConfig.currentUserId,
                                  id,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Unblocked: $id'),
                                      backgroundColor:
                                          const Color(0xFF4CAF50),
                                    ),
                                  );
                                }
                              },
                            ),
                          )),
                    ],
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
          );
        },
      ),
    );
  }

  Future<List<String>> _blockedUserIds() async {
    final client = SupabaseConfig.client;
    if (client == null) return const [];
    try {
      final result = await client
          .from('blocks')
          .select('blocked_id')
          .eq('blocker_id', SupabaseConfig.currentUserId);
      return (result as List).map((r) => r['blocked_id'] as String).toList();
    } catch (_) {
      return const [];
    }
  }

  void _showReportDialog(BuildContext context) {
      final targetCtrl = TextEditingController();
    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C162E),
          title: const Text(
            'Report a User',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Target user ID:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: targetCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter user ID to report',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: const Color(0xFF2E244A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select a reason for reporting:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ..._reportReasons.map(
                (reason) => ListTile(
                  title: Text(
                    reason,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    setDialogState(() => selectedReason = reason);
                  },
                ),
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
              onPressed: targetCtrl.text.isNotEmpty && selectedReason != null
                  ? () async {
                      Navigator.pop(context);
                      await ref
                          .read(weekendProvider.notifier)
                          .reportUser(
                            targetCtrl.text.trim(),
                            selectedReason!,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Report submitted: $selectedReason'),
                            backgroundColor: const Color(0xFF4CAF50),
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4B72),
              ),
              child: const Text(
                'Submit',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final List<String> _reportReasons = [
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

  void _showAccountSecurity(BuildContext context) {
    context.push('/settings');
  }

  void _showPrivacyControls(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        bool showMeInSearch = true;
        bool showDistance = true;
        bool crossedPaths = true;
        bool readReceipts = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1C162E),
            title: const Text(
              'Privacy Controls',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Show me in search',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Allow others to find your profile',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  value: showMeInSearch,
                  onChanged: (v) => setDialogState(() => showMeInSearch = v),
                  activeThumbColor: const Color(0xFFFF4B72),
                ),
                SwitchListTile(
                  title: const Text(
                    'Show distance',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Show approximate distance to others',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  value: showDistance,
                  onChanged: (v) => setDialogState(() => showDistance = v),
                  activeThumbColor: const Color(0xFFFF4B72),
                ),
                SwitchListTile(
                  title: const Text(
                    'Crossed paths',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    "Match with people you've crossed paths with",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  value: crossedPaths,
                  onChanged: (v) => setDialogState(() => crossedPaths = v),
                  activeThumbColor: const Color(0xFFFF4B72),
                ),
                SwitchListTile(
                  title: const Text(
                    'Read receipts',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Let others see when you have read messages',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  value: readReceipts,
                  onChanged: (v) => setDialogState(() => readReceipts = v),
                  activeThumbColor: const Color(0xFFFF4B72),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Color(0xFFFF4B72)),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final client = SupabaseConfig.client;
                  if (client != null) {
                    final userId = SupabaseConfig.currentUserId;
                    try {
                      await client.from('user_settings').upsert({
                        'user_id': userId,
                        'show_me_in_search': showMeInSearch,
                        'discovery_emails_enabled': true,
                        'push_notifications_enabled': true,
                        'max_distance_km': 25,
                        'preferred_genders': <String>[],
                      });
                    } catch (_) {}
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Privacy settings saved'),
                        backgroundColor: Color(0xFF4CAF50),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4B72),
                ),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchPhone(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SafetyToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _SafetyToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1C162E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white38,
        ),
      ),
    );
  }
}

class _SafetyTipCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  const _SafetyTipCard({
    required this.title,
    required this.description,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1C162E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
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
}

class _ResourceCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  const _ResourceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1C162E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9966).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFFF9966), size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        trailing: const Icon(Icons.open_in_new_rounded, color: Colors.white38),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  const _FeatureCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1C162E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
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
}
