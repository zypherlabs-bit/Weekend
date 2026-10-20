import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/weekend_provider.dart';
import '../theme/app_theme.dart';

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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                  Text(
                    'Safety Center',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurface),
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
              SizedBox(height: 12),
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
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            title: Text(
              'Blocked Users',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: switch (snapshot.connectionState) {
              ConnectionState.waiting => Center(
                  child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                ),
              _ when snapshot.hasError => Text(
                  'Could not load your blocked users. Please try again.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              _ when blocked.isEmpty => Text(
                  'You have not blocked anyone yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              _ => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${blocked.length} blocked',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 8),
                    ...blocked.map(
                      (id) => ListTile(
                        title: Text(
                          id,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        trailing: IconButton(
                          tooltip: 'Unblock',
                          icon: Icon(
                            Icons.lock_open_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                  backgroundColor: AppTheme.onlineGreen,
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
                child: Text(
                  'Close',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
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
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          title: Text(
            'Share My Date',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contactCtrl,
                decoration: InputDecoration(
                  labelText: 'Contact Name',
                  labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: venueCtrl,
                decoration: InputDecoration(
                  labelText: 'Venue',
                  labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: timeCtrl,
                decoration: InputDecoration(
                  labelText: 'Time',
                  labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSharing ? null : () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                          SnackBar(
                            content: Text('Plan shared.'),
                            backgroundColor: AppTheme.onlineGreen,
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
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: Text(
                'Share',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text(
          'Photo Verification',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Open the Safety Center to submit a selfie for photo verification. '
          'Your selfie is uploaded to your private profile-photos bucket and '
          'reviewed by the moderation service.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/safety-center');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              'Open Safety Center',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
