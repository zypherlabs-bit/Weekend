import 'package:flutter/material.dart';
import 'weekend_design_system.dart';

/// Inline error banner with retry, shared by Discover/Matches/Plans/Chat.
class WeekendErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const WeekendErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WeekendTokens.spacingXxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: WeekendTokens.spacingMd),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: WeekendTokens.spacingLg),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
