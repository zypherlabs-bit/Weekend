import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';

class MatchCelebrationDialog extends StatelessWidget {
  final UserProfile currentUser;
  final UserProfile matchedUser;
  final VoidCallback onStartChat;
  final VoidCallback onDismiss;

  const MatchCelebrationDialog({
    super.key,
    required this.currentUser,
    required this.matchedUser,
    required this.onStartChat,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF4B72), Color(0xFFFF9966)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'It\'s a Match!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You and ${matchedUser.name} liked each other',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: CachedNetworkImageProvider(currentUser.photos.firstOrNull ?? ''),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_rounded, color: Color(0xFFFF4B72)),
                    ),
                    const SizedBox(width: 16),
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: CachedNetworkImageProvider(matchedUser.photos.firstOrNull ?? ''),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onStartChat,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFFF4B72),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Start Chatting',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(
                    'Keep Swiping',
                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
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
