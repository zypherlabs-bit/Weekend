import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';

import '../../models/models.dart';
import '../../providers/weekend_provider.dart';

class LocationSettingsScreen extends ConsumerStatefulWidget {
  const LocationSettingsScreen({super.key});

  @override
  ConsumerState<LocationSettingsScreen> createState() =>
      _LocationSettingsScreenState();
}

class _LocationSettingsScreenState
    extends ConsumerState<LocationSettingsScreen> {
  late bool _locationDiscovery;
  late bool _crossedPaths;
  late bool _showDistance;
  late bool _nearbyDiscovery;
  late bool _travelMode;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(weekendProvider).locationPreferences;
    _locationDiscovery = prefs.locationDiscoveryEnabled;
    _crossedPaths = prefs.crossedPathsEnabled;
    _showDistance = prefs.showDistanceEnabled;
    _nearbyDiscovery = prefs.nearbyDiscoveryEnabled;
    _travelMode = prefs.travelModeEnabled;
    _loadFromBackend();
  }

  /// Hydrate the toggles from the live `user_settings` row.
  ///
  /// They used to be seeded from the in-memory [LocationPreferences] defaults
  /// only, so the screen always showed the same values regardless of what the
  /// user had actually saved.
  Future<void> _loadFromBackend() async {
    final client = SupabaseConfig.client;
    final userId = SupabaseConfig.currentUserId;
    if (client == null || userId == 'unauthenticated' || userId == 'me') {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final row = await client
          .from('user_settings')
          .select(
            'location_discovery_enabled, nearby_discovery_enabled, '
            'show_distance_enabled, travel_mode_enabled, crossed_paths_enabled, '
            'max_distance_km',
          )
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _locationDiscovery =
              row['location_discovery_enabled'] as bool? ?? _locationDiscovery;
          _nearbyDiscovery =
              row['nearby_discovery_enabled'] as bool? ?? _nearbyDiscovery;
          _showDistance =
              row['show_distance_enabled'] as bool? ?? _showDistance;
          _travelMode = row['travel_mode_enabled'] as bool? ?? _travelMode;
          _crossedPaths =
              row['crossed_paths_enabled'] as bool? ?? _crossedPaths;
          final radius = row['max_distance_km'] as int?;
          if (radius != null) {
            ref.read(weekendProvider.notifier).setDiscoveryRadius(radius);
          }
        });
      }
    } catch (e) {
      debugPrint('Could not load location settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final prefs = LocationPreferences(
      locationDiscoveryEnabled: _locationDiscovery,
      crossedPathsEnabled: _crossedPaths,
      showDistanceEnabled: _showDistance,
      nearbyDiscoveryEnabled: _nearbyDiscovery,
      travelModeEnabled: _travelMode,
      discoveryRadiusKm: ref
          .read(weekendProvider)
          .locationPreferences
          .discoveryRadiusKm,
    );

    ref.read(weekendProvider.notifier).setLocationPreferences(prefs);

    final client = SupabaseConfig.client;
    final userId = SupabaseConfig.currentUserId;
    if (client == null || userId == 'unauthenticated' || userId == 'me') {
      if (mounted) {
        setState(() => _isSaving = false);
        _showMessage(
          'Settings are not connected to a backend, so nothing was saved.',
          isError: true,
        );
      }
      return;
    }

    // Persist every toggle, not just the radius. Reporting "Settings saved"
    // while only the radius reached the database is what made these switches
    // look functional but revert on the next launch.
    try {
      final updated = await client
          .from('user_settings')
          .upsert({
            'user_id': userId,
            'max_distance_km': prefs.discoveryRadiusKm,
            'location_discovery_enabled': prefs.locationDiscoveryEnabled,
            'nearby_discovery_enabled': prefs.nearbyDiscoveryEnabled,
            'show_distance_enabled': prefs.showDistanceEnabled,
            'travel_mode_enabled': prefs.travelModeEnabled,
            'crossed_paths_enabled': prefs.crossedPathsEnabled,
          })
          .select('user_id')
          .limit(1);
      if (updated.isEmpty) {
        throw StateError('The server did not save these settings.');
      }
      if (mounted) _showMessage('Settings saved', isError: false);
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Settings could not be saved. ${_readableError(e)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _readableError(Object e) {
    final text = e.toString();
    if (e is StateError) return e.message;
    if (text.contains('42703') || text.contains('does not exist')) {
      return 'The server is missing a settings column, so these options cannot '
          'be stored yet.';
    }
    if (text.contains('42501') || text.contains('row-level security')) {
      return 'The server rejected this change for your account.';
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
        ),
        title: Text(
          'Location Settings',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF4B72)),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SettingGroup(
                          title: 'Discovery',
                          children: [
                            _LocationToggle(
                              title: 'Location Discovery',
                              subtitle:
                                  'Use your location to find people nearby',
                              value: _locationDiscovery,
                              onChanged: (v) =>
                                  setState(() => _locationDiscovery = v!),
                            ),
                            _LocationToggle(
                              title: 'Nearby Discovery',
                              subtitle: 'Show nearby people in discovery',
                              value: _nearbyDiscovery,
                              onChanged: (v) =>
                                  setState(() => _nearbyDiscovery = v!),
                            ),
                            _LocationToggle(
                              title: 'Show Distance',
                              subtitle: 'Show approximate distance to others',
                              value: _showDistance,
                              onChanged: (v) =>
                                  setState(() => _showDistance = v!),
                            ),
                            _LocationToggle(
                              title: 'Travel Mode',
                              subtitle: 'Discover people in another city',
                              value: _travelMode,
                              onChanged: (v) =>
                                  setState(() => _travelMode = v!),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _SettingGroup(
                          title: 'Privacy',
                          children: [
                            _LocationToggle(
                              title: 'Crossed Paths',
                              subtitle:
                                  'Match with people you\'ve geographically crossed',
                              value: _crossedPaths,
                              onChanged: (v) =>
                                  setState(() => _crossedPaths = v!),
                            ),
                            _LocationToggle(
                              title: 'Exact Location Protection',
                              subtitle:
                                  'Your exact coordinates are never shared',
                              value: true,
                              onChanged: null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _SettingGroup(
                          title: 'Discovery Radius',
                          children: [
                            Consumer(
                              builder: (context, ref, child) {
                                final currentRadius = ref
                                    .watch(
                                      weekendProvider.select(
                                        (s) => s.locationPreferences,
                                      ),
                                    )
                                    .discoveryRadiusKm;
                                return _RadiusSlider(
                                  currentRadiusKm: currentRadius,
                                  onRadiusChanged: (km) {
                                    ref
                                        .read(weekendProvider.notifier)
                                        .setDiscoveryRadius(km);
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4B72),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Save Settings',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RadiusSlider extends StatelessWidget {
  final int currentRadiusKm;
  final Function(int) onRadiusChanged;

  const _RadiusSlider({
    required this.currentRadiusKm,
    required this.onRadiusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Maximum discovery distance: $currentRadiusKm km',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: const Color(0xFFFF4B72),

            overlayColor: const Color(0xFFFF4B72).withValues(alpha: 0.2),
            activeTrackColor: const Color(0xFFFF4B72),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            trackHeight: 4,
          ),
          child: Slider(
            value: currentRadiusKm.toDouble(),
            min: 1,
            max: 100,
            divisions: 20,

            label: '$currentRadiusKm km',
            onChanged: (value) => onRadiusChanged(value.round()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '1 km',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
            Text(
              '100 km',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: children.asMap().entries.map((entry) {
              final isLast = entry.key == children.length - 1;
              return Column(
                children: [
                  entry.value,
                  if (!isLast)
                    Divider(
                      color: Colors.white.withValues(alpha: 0.05),
                      height: 1,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _LocationToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const _LocationToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 12,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFFFF4B72),

        inactiveThumbColor: Colors.white.withValues(alpha: 0.3),

        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
      ),
    );
  }
}
