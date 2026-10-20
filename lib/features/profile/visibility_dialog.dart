import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repositories/engagement_repository.dart';
import '../../services/photo_url_service.dart';

/// Visibility tools on the user's own profile:
///
///   * Spotlight — activation goes through `activate_spotlight` (migration
///     031); the dialog reports the window the server created or the reason
///     it did not (`monthly_limit`, `already_active`, no entitlement).
///   * Photo Insights — `get_my_photo_insights`, 30-day impressions per
///     photo. "Not enough data yet" is the honest rendering for small
///     samples; numbers are never invented.
class VisibilityDialog extends StatefulWidget {
  const VisibilityDialog({super.key});

  @override
  State<VisibilityDialog> createState() => _VisibilityDialogState();
}

class _VisibilityDialogState extends State<VisibilityDialog> {
  final EngagementRepository _repository = EngagementRepository();

  bool _busySpotlight = false;
  bool _loadingInsights = true;

  SpotlightStatus _spotlight = const SpotlightStatus(active: false);
  PhotoInsights? _insights;
  final Map<String, String> _photoUrls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final spotlight = await _repository.getMySpotlight();
    final insights = await _repository.getMyPhotoInsights();
    // Signed URLs for the photos the insights cover, resolved once.
    final paths = insights?.photos
            .map((p) => p.storagePath)
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList() ??
        const <String>[];
    final urls = await PhotoUrlService.resolve(paths);
    if (!mounted) return;
    setState(() {
      _spotlight = spotlight;
      _insights = insights;
      _photoUrls.addAll(urls);
      _loadingInsights = false;
    });
  }

  Future<void> _activateSpotlight() async {
    if (_busySpotlight) return;
    setState(() => _busySpotlight = true);
    final (status, reason) = await _repository.activateSpotlight();
    if (!mounted) return;
    setState(() {
      _busySpotlight = false;
      if (status.active) _spotlight = status;
    });
    final messenger = ScaffoldMessenger.of(context);
    switch (reason) {
      case '':
        break; // fresh activation — covered by re-render below
      case 'already_active':
        break; // the live window is rendered
      case 'monthly_limit':
        messenger.showSnackBar(const SnackBar(
          content: Text('You have used all 3 Spotlights in the last 30 days.'),
          backgroundColor: Colors.red,
        ));
        break;
      case 'insufficient_privilege':
        messenger.showSnackBar(const SnackBar(
          content: Text('Spotlight is not available for this account.'),
          backgroundColor: Colors.red,
        ));
        break;
      default:
        messenger.showSnackBar(const SnackBar(
          content: Text('Spotlight could not be activated. Try again.'),
          backgroundColor: Colors.red,
        ));
        break;
    }
  }

  String _formatEnd(DateTime? end) {
    if (end == null) return '';
    return end.toLocal().toString().substring(0, 16);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Visibility',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18)),
            const SizedBox(height: 12),
            Text(
              _spotlight.active
                  ? 'Spotlight is LIVE until ${_formatEnd(_spotlight.endsAt)}'
                  : 'Boost your profile to the top of nearby decks for 4 hours.',
              style: TextStyle(
                color: _spotlight.active
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _busySpotlight
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _spotlight.active ? null : _activateSpotlight,
                      child: Text(
                        _spotlight.active
                            ? 'Spotlight already active'
                            : 'Spotlight my profile',
                        style: TextStyle(
                          color: _spotlight.active
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ),
            ),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            Text(
              'Photo Insights',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15),
            ),
            Text(
              _insights == null
                  ? 'Insights are available once your photos are approved and viewed.'
                  : 'Impressions over the last ${_insights!.windowDays} days '
                      '(a photo needs ${_insights!.minimumRequiredImpressions} '
                      'for a meaningful sample).',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_loadingInsights)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_insights == null || _insights!.photos.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No approved photos with impressions yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              )
            else
              for (final entry in _insights!.photos)
                _InsightTile(entry: entry, photoUrl: _photoUrls[entry.storagePath]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final PhotoInsightEntry entry;
  final String? photoUrl;

  const _InsightTile({required this.entry, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: photoUrl == null
            ? Icon(Icons.image_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(photoUrl!, fit: BoxFit.cover),
              ),
      ),
      title: Text(
        entry.isPrimary ? 'Primary photo' : 'Photo',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
      ),
      subtitle: Text(
        entry.hasSufficientData
            ? '${entry.impressions30d} views · ${entry.uniqueViewers30d} unique'
            : 'Not enough data yet — keep it up',
        style: TextStyle(
          color: entry.hasSufficientData
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}
