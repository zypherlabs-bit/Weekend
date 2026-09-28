import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/supabase_config.dart';
import '../../models/discovery_preferences.dart';
import '../../models/models.dart';
import '../../providers/weekend_provider.dart';
import '../../repositories/search_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/filter_controls.dart';
import '../../widgets/weekend_design_system.dart';

/// Storage key for the user's saved discovery preferences.
const String _kPrefsKey = 'weekend.discovery_preferences.v1';

/// **Preferred Match** - where the user declares who they want to meet.
///
/// Every control here maps to a HARD filter. A selection is never advisory:
/// the `search_profiles` RPC excludes any candidate that fails even one of
/// the chosen criteria, and the screen states that explicitly so a user who
/// sees fewer results understands why.
///
/// The screen never silently relaxes a filter to manufacture results. The
/// only actions offered are "Adjust Preferences" (stay here and change the
/// selection) and, when a distance filter is set, an explicit "Increase
/// distance" button that visibly changes the selection before re-running.
class PreferredMatchScreen extends ConsumerStatefulWidget {
  const PreferredMatchScreen({super.key});

  @override
  ConsumerState<PreferredMatchScreen> createState() =>
      _PreferredMatchScreenState();
}

class _PreferredMatchScreenState extends ConsumerState<PreferredMatchScreen> {
  late DiscoveryPreferences _prefs;
  final _cityController = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  String? _error;
  List<UserProfile> _results = const [];
  bool _searched = false;

  final _searchRepo = SearchRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var prefs = const DiscoveryPreferences.unrestricted();
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString(_kPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        prefs = DiscoveryPreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // A corrupt or unreadable payload must not trap the user on a blank
      // screen; fall back to defaults rather than pretending nothing loads.
      prefs = const DiscoveryPreferences.unrestricted();
    }
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _cityController.text = prefs.city ?? '';
      _loading = false;
    });
  }

  Future<void> _persist() async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(_kPrefsKey, jsonEncode(_prefs.toJson()));
    } catch (_) {
      // Persistence is a convenience; the in-memory selection still applies
      // to the search that follows.
    }
  }

  void _update(DiscoveryPreferences next) {
    setState(() {
      _prefs = next;
      // Any change invalidates the previous result set: showing stale
      // matches next to new filters would misrepresent what was selected.
      _results = const [];
      _searched = false;
    });
  }

  void _toggleMulti(
    DiscoveryPreferences Function(List<String>) apply,
    List<String> current,
    String value,
  ) {
    final next = List<String>.from(current);
    if (!next.remove(value)) next.add(value);
    _update(apply(next));
  }

  void _toggleGender(String value) => _toggleMulti(
        (v) => _prefs.copyWith(genders: v),
        _prefs.genders,
        value,
      );

  void _toggleIntent(String value) => _toggleMulti(
        (v) => _prefs.copyWith(relationshipIntents: v),
        _prefs.relationshipIntents,
        value,
      );

  void _toggleInterest(String value) => _toggleMulti(
        (v) => _prefs.copyWith(interests: v),
        _prefs.interests,
        value,
      );

  void _toggleLanguage(String value) => _toggleMulti(
        (v) => _prefs.copyWith(languages: v),
        _prefs.languages,
        value,
      );

  /// Lifestyle is single-select per key, and re-picking the current value
  /// clears it so the dimension stops filtering.
  void _toggleIn(String key, String value) {
    final lifestyle = Map<String, String>.from(_prefs.lifestyle);
    if (lifestyle[key] == value) {
      lifestyle.remove(key);
    } else {
      lifestyle[key] = value;
    }
    _update(_prefs.copyWith(lifestyle: lifestyle));
  }

  void _reset() {
    _cityController.clear();
    setState(() {
      _prefs = const DiscoveryPreferences.unrestricted();
      _results = const [];
      _searched = false;
      _error = null;
    });
  }

  Future<void> _search() async {
    final userId = SupabaseConfig.currentUserId;
    if (userId.isEmpty || userId == 'me' || userId == 'unauthenticated') {
      setState(
        () => _error = 'You are not signed in, so search is unavailable.',
      );
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    await _persist();

    // Mirror the choices the rest of the app already understands so the deck
    // and the location settings cannot disagree.
    final current = ref.read(weekendProvider).locationPreferences;
    ref.read(weekendProvider.notifier).setLocationPreferences(
          current.copyWith(
            preferredGenders: _prefs.genders,
            discoveryRadiusKm: (_prefs.maxDistanceKm ?? 50).round(),
          ),
        );

    final result = await _searchRepo.search(userId, _prefs);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _error = result.error;
      _results = result.profiles;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preferred Match')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferred Match'),
        actions: [
          TextButton(
            onPressed: _searching ? null : _reset,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildExplainer(theme),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _buildSection(
                    theme,
                    'Show me',
                    'Every option you pick is required. A profile appears '
                        'only if it matches all of them.',
                    _chipWrap(
                      PreferredMatchOptions.genders,
                      _prefs.genders,
                      _toggleGender,
                    ),
                  ),
                  _buildSection(
                    theme,
                    'Age range',
                    'Profiles with an unknown age are never shown while this '
                        'is set.',
                    _buildAgeRange(theme),
                  ),
                  _buildSection(
                    theme,
                    'Distance',
                    'Measured from your saved city, never your address.',
                    _buildDistance(theme),
                  ),
                  _buildSection(
                    theme,
                    'Location',
                    'How far and where to look.',
                    _buildLocationMode(),
                  ),
                  _buildSection(
                    theme,
                    'City',
                    'Leave empty to search every city.',
                    _buildCity(theme),
                  ),
                  _buildSection(
                    theme,
                    'Looking for',
                    'A profile must state one of these intents.',
                    _chipWrap(
                      PreferredMatchOptions.relationshipIntents,
                      _prefs.relationshipIntents,
                      _toggleIntent,
                    ),
                  ),
                  _buildSection(
                    theme,
                    'Interests',
                    'A profile must have every interest you select here.',
                    _chipWrap(
                      PreferredMatchOptions.interests,
                      _prefs.interests,
                      _toggleInterest,
                    ),
                  ),
                  _buildSection(
                    theme,
                    'Lifestyle',
                    'Each choice must match exactly. Leave one blank to '
                        'ignore it.',
                    _buildLifestyle(theme),
                  ),
                  _buildSection(
                    theme,
                    'Languages',
                    'A profile must speak every language you select.',
                    _chipWrap(
                      PreferredMatchOptions.languages,
                      _prefs.languages,
                      _toggleLanguage,
                    ),
                  ),
                  if (_searched) ...[
                    const SizedBox(height: WeekendTokens.spacingXxl),
                    _buildResults(theme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildExplainer(ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.all(WeekendTokens.spacingLg),
      decoration: BoxDecoration(
        color: AppTheme.sunsetCoral.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(WeekendTokens.radiusLg),
        border: Border.all(
          color: AppTheme.sunsetCoral.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.sunsetCoral,
          ),
          const SizedBox(width: WeekendTokens.spacingMd),
          Expanded(
            child: Text(
              'These are exact filters, not suggestions. Every profile you '
              'see matches all of them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    String helper,
    Widget child,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: WeekendTokens.spacingXxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: WeekendTokens.spacingMd),
          child,
        ],
      ),
    );
  }

  Widget _chipWrap(
    List<String> options,
    List<String> selected,
    void Function(String) onTap,
  ) {
    return Wrap(
      spacing: WeekendTokens.spacingSm,
      runSpacing: WeekendTokens.spacingSm,
      children: [
        for (final option in options)
          SelectChip(
            label: option,
            selected: selected.contains(option),
            onTap: () => onTap(option),
          ),
      ],
    );
  }

  Widget _buildAgeRange(ThemeData theme) {
    final min = _prefs.ageMin ?? DiscoveryPreferences.kMinimumAge;
    final max = _prefs.ageMax ?? DiscoveryPreferences.kMaximumAge;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: NumberStepper(
                label: 'From',
                value: min,
                min: DiscoveryPreferences.kMinimumAge,
                max: max,
                onChanged: (v) => _update(
                  _prefs.copyWith(ageMin: v, ageMax: v > max ? v : max),
                ),
              ),
            ),
            const SizedBox(width: WeekendTokens.spacingMd),
            Expanded(
              child: NumberStepper(
                label: 'To',
                value: max,
                min: min,
                max: DiscoveryPreferences.kMaximumAge,
                onChanged: (v) => _update(
                  _prefs.copyWith(ageMax: v, ageMin: v < min ? v : min),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: WeekendTokens.spacingSm),
        Text(
          '$min - $max years old',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildDistance(ThemeData theme) {
    final selected = _prefs.maxDistanceKm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: WeekendTokens.spacingSm,
          runSpacing: WeekendTokens.spacingSm,
          children: [
            for (final km in PreferredMatchOptions.distancesKm)
              SelectChip(
                label: 'Within $km km',
                selected: selected != null && (selected - km).abs() < 0.5,
                onTap: () => _update(
                  _prefs.copyWith(
                    maxDistanceKm:
                        (selected != null && (selected - km).abs() < 0.5)
                            ? null
                            : km,
                  ),
                ),
              ),
          ],
        ),
        if (selected == null)
          Padding(
            padding: const EdgeInsets.only(top: WeekendTokens.spacingSm),
            child: Text(
              'No distance limit - filtering by other criteria only.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationMode() {
    return Wrap(
      spacing: WeekendTokens.spacingSm,
      runSpacing: WeekendTokens.spacingSm,
      children: [
        for (final mode in LocationMode.values)
          SelectChip(
            label: mode.label,
            icon: mode.icon,
            selected: _prefs.locationMode == mode,
            onTap: () {
              if (mode == LocationMode.explore) {
                // 'Explore' deliberately lifts the distance restriction, so
                // the distance control must not keep claiming to apply.
                _update(
                  DiscoveryPreferences(
                    genders: _prefs.genders,
                    ageMin: _prefs.ageMin,
                    ageMax: _prefs.ageMax,
                    city: _prefs.city,
                    relationshipIntents: _prefs.relationshipIntents,
                    interests: _prefs.interests,
                    languages: _prefs.languages,
                    lifestyle: _prefs.lifestyle,
                    locationMode: mode,
                  ),
                );
              } else {
                _update(_prefs.copyWith(locationMode: mode));
              }
            },
          ),
      ],
    );
  }

  Widget _buildCity(ThemeData theme) {
    return TextField(
      controller: _cityController,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        hintText: 'e.g. Pune',
        prefixIcon: const Icon(Icons.location_city_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WeekendTokens.radiusLg),
        ),
        suffixIcon: (_prefs.city == null || _prefs.city!.isEmpty)
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                tooltip: 'Clear city filter',
                onPressed: () {
                  _cityController.clear();
                  _update(_prefs.copyWith(clearCity: true));
                },
              ),
      ),
      onChanged: (value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          if (_prefs.city != null) _update(_prefs.copyWith(clearCity: true));
        } else if (trimmed != _prefs.city) {
          _update(_prefs.copyWith(city: trimmed));
        }
      },
    );
  }

  Widget _buildLifestyle(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in PreferredMatchOptions.lifestyleLabels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: WeekendTokens.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: WeekendTokens.spacingSm),
                _chipWrap(
                  PreferredMatchOptions.lifestyle[entry.key]!,
                  [
                    if (_prefs.lifestyle[entry.key] != null)
                      _prefs.lifestyle[entry.key]!,
                  ],
                  (value) => _toggleIn(entry.key, value),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_error != null) {
      return ResultPanel(
        theme: theme,
        icon: Icons.cloud_off_rounded,
        title: 'Could not load profiles',
        message: _error!,
        tint: AppTheme.errorRed,
      );
    }

    if (_results.isEmpty) {
      // The exact wording matters: the user's filters were honoured in full,
      // so the honest explanation is that nothing matched - not a failure,
      // and not a reason to quietly widen the search.
      return ResultPanel(
        theme: theme,
        icon: Icons.search_off_rounded,
        title: 'No profiles match all your preferences',
        message: _prefs.activeFilterLabels.isEmpty
            ? 'There are no active profiles on Weekend yet. Check back soon.'
            : 'Nothing matches every filter you selected.\n\n'
                'Your filters were not changed. Adjust them to widen the '
                'search.',
        tint: AppTheme.sunsetCoral,
        chips: _prefs.activeFilterLabels,
        primaryLabel: 'Adjust Preferences',
        onPrimary: () {
          setState(() => _searched = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adjust the filters above, then search again.'),
            ),
          );
        },
        secondaryLabel: _prefs.maxDistanceKm == null
            ? null
            : 'Increase distance',
        onSecondary: _prefs.maxDistanceKm == null
            ? null
            : () {
                // Explicit and visible: the user pressed the button, and the
                // distance control visibly updates before re-running.
                final next = _prefs.maxDistanceKm! * 2;
                _update(
                  _prefs.copyWith(
                    maxDistanceKm: next > DiscoveryPreferences.kMaximumDistanceKm
                        ? null
                        : next,
                  ),
                );
                _search();
              },
      );
    }

    return ResultPanel(
      theme: theme,
      icon: Icons.people_alt_rounded,
      title: '${_results.length} '
          '${_results.length == 1 ? 'profile matches' : 'profiles match'} '
          'every filter',
      message: 'Each of these satisfies all '
          '${_prefs.activeFilterCount} active '
          '${_prefs.activeFilterCount == 1 ? 'filter' : 'filters'}.',
      tint: AppTheme.successGreen,
      chips: _prefs.activeFilterLabels,
      profiles: _results,
      primaryLabel: 'Open Discover',
      onPrimary: () => context.go('/explore'),
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _searching ? null : _search,
            icon: _searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(_searching ? 'Searching...' : 'See who matches'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.sunsetCoral,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeekendTokens.radiusXl),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
