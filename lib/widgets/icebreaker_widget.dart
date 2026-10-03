import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../repositories/icebreaker_repository.dart';

/// A button that generates an icebreaker (AI conversation starter) for the
/// current match and shows it in a bottom sheet.
class IcebreakerButton extends ConsumerStatefulWidget {
  final MatchItem match;
  final UserProfile currentUser;

  const IcebreakerButton({
    super.key,
    required this.match,
    required this.currentUser,
  });

  @override
  ConsumerState<IcebreakerButton> createState() => _IcebreakerButtonState();
}

class _IcebreakerButtonState extends ConsumerState<IcebreakerButton> {
  bool _isLoading = false;

  String _sharedInterestText() {
    final userInterests = widget.currentUser.interests.toSet();
    final matchInterests = widget.match.user.interests.toSet();
    final shared = userInterests.intersection(matchInterests).toList();
    return shared.join(', ');
  }

  List<String> _sharedInterests() {
    final userInterests = widget.currentUser.interests.toSet();
    final matchInterests = widget.match.user.interests.toSet();
    return userInterests.intersection(matchInterests).toList();
  }

  Future<void> _generateAndShow() async {
    setState(() => _isLoading = true);

    final repo = IcebreakerRepository();
    final suggestion = await repo.generateIcebreaker(
      userName: widget.currentUser.name,
      matchName: widget.match.user.name,
      sharedInterests: _sharedInterests(),
      favoritePlace: 'cafe',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1C24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      color: Color(0xFFFF9966), size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Icebreaker',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                suggestion,
                style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
              ),
              if (_sharedInterestText().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Shared interests: ${_sharedInterestText()}',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tip copied to clipboard — paste it into the chat!'),
                        backgroundColor: Color(0xFF4CAF50),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4B72),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.copy_rounded, color: Colors.white),
                  label: const Text(
                    'Copy to paste',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _isLoading ? 'Generating icebreaker...' : 'Icebreaker',
      onPressed: _isLoading ? null : _generateAndShow,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            )
          : const Icon(Icons.lightbulb_outline_rounded, color: Colors.white70),
    );
  }
}
