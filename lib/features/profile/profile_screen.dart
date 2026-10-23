import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../../providers/weekend_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/image_optimizer.dart';
import '../../repositories/profile_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';

import '../settings/settings_dialog.dart';
import 'opening_moves_dialog.dart';
import 'verification_dialog.dart';
import 'visibility_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isUploadingPhoto = false;

  /// The avatar photo widget shown for the current user. Reused both inside
  /// the [Hero] (when the user has photos) and as a plain fallback (when
  /// they don't), keeping a single source of truth for the avatar render.
  Widget _avatarPhoto(UserProfile user, ColorScheme scheme) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary, width: 3),
      ),
      child: CircleAvatar(
        radius: 58,
        backgroundImage: user.photos.isNotEmpty
            ? NetworkImage(user.photos.first)
            : null,
        backgroundColor: scheme.surfaceContainerHighest,
        child: user.photos.isEmpty
            ? Icon(
                Icons.person_rounded,
                size: 60,
                color: scheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final user = state.currentUser;
    final heroTag =
        'profileAvatar_${user.primaryPhotoId.isNotEmpty ? user.primaryPhotoId : user.id}';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  if (user.photos.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => context.push('/profile/viewer'),
                      child: Hero(
                        tag: heroTag,
                        child: _avatarPhoto(user, scheme),
                      ),
                    )
                  else
                    _avatarPhoto(user, scheme),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: _isUploadingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Name and age together, per the dating-card hierarchy.
                  // The age is omitted entirely when unknown rather than
                  // showing a fabricated number.
                  Text(
                    user.age > 0 ? '${user.name}, ${user.age}' : user.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (user.isPhotoVerified) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.verified_rounded,
                      color: AppTheme.onlineGreen,
                      size: 24,
                    ),
                  ],
                ],
              ),
              // City on its own line, clearly visible and separate from the
              // relationship intent.
              if (user.city.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.city,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              if (user.relationshipIntent.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    user.relationshipIntent,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _StatCard(
                icon: Icons.verified_user_rounded,
                label: 'Trust Score',
                value: '${user.trustScore}%',
                color: AppTheme.onlineGreen,
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.people_rounded,
                label: 'Crossed Paths',
                value: '${user.crossedPathsCount}',
                color: scheme.primary,
              ),
              const SizedBox(height: 24),
              // Server-backed profile tools: Spotlight + Photo Insights,
              // manual photo verification, and Opening Moves editing.
              _ProfileSection(
                title: 'Profile Tools',
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.visibility_rounded,
                        color: theme.colorScheme.tertiary,
                      ),
                      title: const Text('Spotlight & Photo Insights'),
                      subtitle: const Text(
                        'Boost your profile and see how your photos perform',
                      ),
                      onTap: () => showDialog(
                        context: context,
                        builder: (dialogContext) => const VisibilityDialog(),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(
                        Icons.verified_rounded,
                        color: AppTheme.onlineGreen,
                      ),
                      title: const Text('Photo Verification'),
                      subtitle: const Text(
                        'Verify your profile with a live selfie',
                      ),
                      onTap: () => showDialog(
                        context: context,
                        builder: (dialogContext) => const VerificationDialog(),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.waving_hand_rounded,
                        color: theme.colorScheme.tertiary,
                      ),
                      title: const Text('Opening Moves'),
                      subtitle: const Text(
                        'Lines the server may use when you match',
                      ),
                      onTap: () => showDialog(
                        context: context,
                        builder: (dialogContext) => const OpeningMovesDialog(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _ProfileSection(
                title: 'About',
                child: Text(
                  user.bio.isNotEmpty ? user.bio : 'No bio yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ProfileSection(
                title: 'Interests',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: user.interests.map((interest) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),

                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        interest,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              _ProfileSection(
                title: 'Referral Code',
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),

                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.referralCode,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final ctx = context;
                          final code = user.referralCode;
                          if (code.isEmpty) {
                            return;
                          }
                          await Clipboard.setData(ClipboardData(text: code));
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Referral code copied: $code'),
                              backgroundColor: AppTheme.successGreen,
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        label: Text(
                          'Copy',
                          style: TextStyle(color: scheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showEditProfile(context),
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      label: const Text('Edit Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showSettings(context),
                    icon: const Icon(Icons.settings_rounded, size: 20),
                    label: const Text('Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHigh,
                      foregroundColor: scheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref.read(authStateProvider.notifier).signOut();
                    if (!context.mounted) return;
                    context.go('/auth');
                  },

                  icon: Icon(Icons.logout_rounded, color: scheme.error),
                  label: Text(
                    'Sign Out',

                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/qr-invite'),
                  icon: Icon(
                    Icons.qr_code_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                  label: Text(
                    'My Weekend QR',
                    style: TextStyle(color: scheme.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/qr-scanner'),
                  icon: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 20,
                    color: theme.colorScheme.tertiary,
                  ),
                  label: Text(
                    'Scan Weekend QR',
                    style: TextStyle(color: theme.colorScheme.tertiary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.tertiary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_isUploadingPhoto) return;
    // Upload under the auth session's id, not the (possibly still
    // placeholder) id held in app state.
    final authId = SupabaseConfig.client?.auth.currentUser?.id;
    if (authId == null || authId.isEmpty || authId == 'unauthenticated') {
      _showMessage(
        'You are not signed in, so the photo was not uploaded.',
        isError: true,
      );
      return;
    }

    final file = await ImageOptimizer.pickAndOptimizeImage();
    if (file == null) {
      if (mounted && ImageOptimizer.lastError != null) {
        _showMessage(ImageOptimizer.lastError!, isError: true);
      }
      return;
    }

    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      final repo = ProfileRepository();
      // Throws unless Storage AND the profile_photos row both succeeded.
      await repo.uploadProfilePhoto(authId, bytes, true);
      // Re-read from the database so the avatar shows the real signed URL.
      await ref.read(weekendProvider.notifier).refreshProfile();
      if (mounted) {
        _showMessage('Photo uploaded!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Failed to upload photo. ${_readableError(e)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  /// Surfaces the real failure reason without leaking tokens or internals.
  String _readableError(Object e) {
    final text = e.toString();
    if (e is StateError) return e.message;
    if (text.contains('413') || text.contains('Payload too large')) {
      return 'That image is too large. Please choose a smaller photo.';
    }
    if (text.contains('mime') || text.contains('mimeType')) {
      return 'That file type is not accepted. Please choose a JPG, PNG or WebP.';
    }
    if (text.contains('42501') || text.contains('row-level security')) {
      return 'The server rejected this upload for your account.';
    }
    return text.replaceAll('Exception: ', '').replaceFirst('Bad state: ', '');
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF4CAF50),
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  void _showEditProfile(BuildContext context) {
    context.push('/edit-profile');
  }

  void _showSettings(BuildContext context) {
    showDialog(context: context, builder: (context) => const SettingsDialog());
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WeekendGlassCard(
      padding: const EdgeInsets.all(16),
      radius: 16,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
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
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _ProfileSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        WeekendGlassCard(
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ],
    );
  }
}
