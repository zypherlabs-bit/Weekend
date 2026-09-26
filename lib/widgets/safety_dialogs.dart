import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/weekend_provider.dart';

/// Quick-access Safety Center.
///
/// Every action here goes to the same LIVE Supabase paths the full Safety
/// Center screen uses. The previous version of this dialog was entirely
/// decorative: the blocked-users list was a hard-coded string, "Report a User"
/// showed a green "Report submitted" without any database call at all, and
/// "Share My Date" discarded the text the user typed.
class SafetyCenterDialog extends ConsumerWidget {
  const SafetyCenterDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  _showBlockedUsers(context, ref);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.flag_rounded,
                title: 'Report a User',
                subtitle: 'Report inappropriate behavior',
                // A report is always about one specific person, so the user
                // is sent to the report flow that can identify them.
                onTap: () {
                  Navigator.pop(context);
                  context.push('/safety-center');
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.share_rounded,
                title: 'Share My Date',
                subtitle: 'Share your plans with trusted contacts',
                onTap: () {
                  Navigator.pop(context);
                  _showShareDateDialog(context, ref);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.verified_user_rounded,
                title: 'Photo Verification',
                subtitle: 'Verify your profile photo',
                onTap: () {
                  Navigator.pop(context);
                  _showVerificationDialog(context, ref);
                },
              ),
              const SizedBox(height: 12),
              _SafetyOption(
                icon: Icons.help_outline_rounded,
                title: 'Safety Tips',
                subtitle: 'Learn how to stay safe',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/safety-center');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Real blocked users, read from the live `blocks` table.
  void _showBlockedUsers(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => FutureBuilder<List<String>>(
        future: ref.read(weekendProvider.notifier).loadBlockedUserIds(),
        builder: (context, snapshot) {
          final blocked = snapshot.data ?? const <String>[];
          return AlertDialog(
            backgroundColor: const Color(0xFF1C162E),
            title: const Text(
              'Blocked Users',
              style: TextStyle(color: Colors.white),
            ),
            content: switch (snapshot.connectionState) {
              ConnectionState.waiting => const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF4B72)),
                ),
              _ when snapshot.hasError => const Text(
                  'Could not load your blocked users. Please try again.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              _ when blocked.isEmpty => const Text(
                  'You have not blocked anyone yet.',
                  style: TextStyle(color: Colors.white70),
                ),
              _ => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${blocked.length} blocked',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    ...blocked.map(
                      (id) => ListTile(
                        title: Text(
                          id,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: IconButton(
                          tooltip: 'Unblock',
                          icon: const Icon(
                            Icons.lock_open_rounded,
                            color: Colors.white70,
                          ),
                          onPressed: () async {
                            final messenger =
                                ScaffoldMessenger.of(dialogContext);
                            try {
                              await ref
                                  .read(weekendProvider.notifier)
                                  .unblockUser(id);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Unblocked: $id'),
                                  backgroundColor: const Color(0xFF4CAF50),
                                ),
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not unblock this user. '
                                    'Please try again.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
            },
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

  /// "Share My Date" hands the typed plan to the OS share sheet.
  ///
  /// The previous version just called `Navigator.pop`, so the text the user
  /// entered was silently thrown away while the button implied it was shared.
  void _showShareDateDialog(BuildContext context, WidgetRef ref) {
    final contactCtrl = TextEditingController();
    final venueCtrl = TextEditingController();
    final timeCtrl = TextEditingController();
    var isSharing = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C162E),
          title: const Text(
            'Share My Date',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contactCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contact Name',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: venueCtrl,
                decoration: const InputDecoration(
                  labelText: 'Venue',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: timeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSharing ? null : () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: isSharing
                  ? null
                  : () async {
                      final text = _dateSummary(
                        contact: contactCtrl.text,
                        venue: venueCtrl.text,
                        time: timeCtrl.text,
                      );
                      if (text == null) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Add at least a contact name or a venue first.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isSharing = true);
                      final messenger =
                          ScaffoldMessenger.of(context);
                      try {
                        final result = await Share.share(text);
                        if (result.status != ShareResultStatus.success) {
                          // Dismissed: say so instead of claiming it was
                          // shared.
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Sharing was cancelled.'),
                            ),
                          );
                          return;
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Plan shared.'),
                            backgroundColor: Color(0xFF4CAF50),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() => isSharing = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not open the share sheet.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4B72),
              ),
              child: const Text(
                'Share',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the message body, or `null` when the user supplied nothing useful.
  static String? _dateSummary({
    required String contact,
    required String venue,
    required String time,
  }) {
    final parts = <String>['Weekend plan'];
    if (contact.trim().isNotEmpty) parts.add('With: ${contact.trim()}');
    if (venue.trim().isNotEmpty) parts.add('Where: ${venue.trim()}');
    if (time.trim().isNotEmpty) parts.add('When: ${time.trim()}');
    // "Weekend plan" alone carries no information the recipient did not have.
    if (parts.length == 1) return null;
    return parts.join('\n');
  }

  /// Photo verification is a real backend flow that needs a signed-in user,
  /// so it is opened in the Safety Center rather than faked with a toast.
  void _showVerificationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Photo Verification',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Open the Safety Center to submit a selfie for photo verification. '
          'Your selfie is uploaded to your private profile-photos bucket and '
          'reviewed by the moderation service.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/safety-center');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4B72),
            ),
            child: const Text(
              'Open Safety Center',
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
