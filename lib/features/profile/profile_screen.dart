import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/weekend_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/image_optimizer.dart';
import '../../repositories/profile_repository.dart';
import '../../widgets/safety_dialogs.dart';
import '../settings/settings_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final user = state.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFF4B72), width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 58,
                      backgroundImage: user.photos.isNotEmpty
                          ? NetworkImage(user.photos.first)
                          : null,
                      backgroundColor: const Color(0xFF2E244A),
                      child: user.photos.isEmpty
                          ? const Icon(Icons.person_rounded, size: 60, color: Colors.white38)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _pickAndUploadPhoto,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4B72),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (user.isPhotoVerified) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.verified_rounded, color: Color(0xFF4CAF50), size: 24),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4B72).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${user.relationshipIntent} · ${user.city}',
                  style: const TextStyle(
                    color: Color(0xFFFF9966),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _StatCard(
                icon: Icons.verified_user_rounded,
                label: 'Trust Score',
                value: '${user.trustScore}%',
                color: const Color(0xFF4CAF50),
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.people_rounded,
                label: 'Crossed Paths',
                value: '${user.crossedPathsCount}',
                color: const Color(0xFFFF4B72),
              ),
              const SizedBox(height: 24),
              _ProfileSection(
                title: 'About',
                child: Text(
                  user.bio.isNotEmpty ? user.bio : 'No bio yet',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4B72).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFF4B72).withOpacity(0.3)),
                      ),
                      child: Text(
                        interest,
                        style: const TextStyle(
                          color: Color(0xFFFF9966),
                          fontSize: 13,
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
                    color: const Color(0xFFFF4B72).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF4B72).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.referralCode,
                          style: const TextStyle(
                            color: Color(0xFFFF9966),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          // Copy referral code
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFFFF9966)),
                        label: const Text('Copy', style: TextStyle(color: Color(0xFFFF9966))),
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
                        backgroundColor: const Color(0xFFFF4B72),
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
                      backgroundColor: const Color(0xFF2E244A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
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
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/auth');
                    }
                  },
                  icon: Icon(Icons.logout_rounded, color: Colors.red.withOpacity(0.8)),
                  label: Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.red.withOpacity(0.8)),
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
    final file = await ImageOptimizer.pickAndOptimizeImage();
    if (file == null) return;
    
    final bytes = await file.readAsBytes();
    final userId = ref.read(weekendProvider.notifier).state.currentUser.id;
    
    final repo = ProfileRepository();
    await repo.uploadProfilePhoto(userId, bytes, true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo uploaded! Pending verification.'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    }
  }

  void _showEditProfile(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
        content: const Text('Profile editing coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF4B72))),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SettingsDialog(),
    );
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C162E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
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
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
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

  const _ProfileSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C162E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ],
    );
  }
}
