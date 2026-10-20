import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../repositories/icebreaker_repository.dart';
import '../theme/app_theme.dart';

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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                  Icon(Icons.lightbulb_outline_rounded,
                      color: Theme.of(context).colorScheme.tertiary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Icebreaker',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                suggestion,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16, height: 1.5),
              ),
              if (_sharedInterestText().isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  'Shared interests: ${_sharedInterestText()}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tip copied to clipboard — paste it into the chat!'),
                        backgroundColor: AppTheme.onlineGreen,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(Icons.copy_rounded, color: Theme.of(context).colorScheme.onSurface),
                  label: Text(
                    'Copy to paste',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Icon(Icons.lightbulb_outline_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
