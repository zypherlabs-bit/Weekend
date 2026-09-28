import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/search_provider.dart';
import '../../widgets/weekend_empty_state.dart';

/// Vocabulary used by the filter chips.
///
/// These strings MUST match the CHECK constraints on `public.profiles`
/// (migrations 001/015) and the lifestyle CHECKs added in migration 022. The
/// database rejects anything else, so a typo surfaces as an empty result
/// rather than a silently wrong filter.
const _genders = ['Woman', 'Man', 'Non-binary', 'Prefer not to say'];

const _relationshipIntents = [
  'Long-term relationship',
  'Dating & Weekend Plans',
  'Dating',
  'New people & Friendships',
];

const _smokingOptions = ['Never', 'Social', 'Regular', 'Former'];
const _drinkingOptions = ['Never', 'Socially', 'Regularly'];
const _exerciseOptions = ['Often', 'Sometimes', 'Rarely'];
const _childrenOptions = ['No', 'Yes'];
const _petsOptions = ['Dog', 'Cat', 'Bird', 'Fish', 'No pets'];

const _languages = [
  'English',
  'Hindi',
  'Marathi',
  'Spanish',
  'French',
  'German',
  'Mandarin',
  'Portuguese',
  'Arabic',
];

const _interests = [
  'Travel',
  'Movies',
  'Music',
  'Food',
  'Sports',
  'Gaming',
  'Art',
  'Books',
  'Photography',
  'Hiking',
  'Coffee',
  'Dance',
];

const _distanceOptionsKm = [5.0, 10.0, 25.0, 50.0, 100.0, 200.0];

/// Discover / Search Filters.
///
/// Every control here maps to a hard filter enforced by the `search_profiles`
/// Postgres function. The screen never narrows a downloaded list locally, so
/// what the user sees is exactly what the database decided.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Prefetch the next page before the user reaches the very end.
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(searchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          if (state.filters.activeFilterCount > 0)
            TextButton.icon(
              onPressed: () => notifier.applyFilters(state.filters.cleared()),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: Text('Clear ${state.filters.activeFilterCount}'),
            ),
          IconButton(
            tooltip: 'Refresh results',
            onPressed: state.isLoading ? null : () => notifier.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _FilterBar(
              filters: state.filters,
              onChanged: notifier.applyFilters,
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(state, notifier)),
          ],
        ),
      ),
    );
  }


  Widget _buildBody(SearchState state, SearchNotifier notifier) {
    if (state.isLoading && state.profiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.hasError && state.profiles.isEmpty) {
      return WeekendEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Search failed',
        subtitle:
            state.error ??
            'We could not reach the server. Check your connection.',
        actionLabel: 'Retry',
        onAction: () => notifier.refresh(),
      );
    }

    if (state.profiles.isEmpty) {
      // Truthful empty state: the server really did apply every filter. The
      // widening actions below are explicit, user-initiated steps - the app
      // never relaxes a filter behind the user's back.
      return _NoMatchesView(
        hasFilters: state.filters.hasActiveFilters,
        onAdjust: () => _showFilterSheet(context, state.filters),
        onIncreaseDistance: () => notifier.applyFilters(
          _nextWiderDistance(state.filters),
        ),
        onExpandAge: () => notifier.applyFilters(_widerAge(state.filters)),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => notifier.refresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: state.profiles.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == state.profiles.length) {
            if (state.isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  state.filters.hasActiveFilters
                      ? 'Every profile matching all your filters is shown.'
                      : "That's everyone for now.",
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _SearchResultTile(
            profile: state.profiles[index],
            onOpen: () => context.push('/explore'),
          );
        },
      ),
    );
  }
}

/// Widen the radius one step, never beyond 200 km.
///
/// Triggered explicitly from the empty state; this is NOT a silent relaxation
/// of the user's query.
SearchFilters _nextWiderDistance(SearchFilters f) {
  for (final step in _distanceOptionsKm) {
    if (step > f.maxDistanceKm) return f.copyWith(maxDistanceKm: step);
  }
  return f.copyWith(maxDistanceKm: 200);
}

/// Widen the age band by 3 years on each side, within adult bounds.
SearchFilters _widerAge(SearchFilters f) {
  final lo = ((f.ageMin ?? 21) - 3).clamp(18, 120);
  final hi = ((f.ageMax ?? 45) + 3).clamp(18, 120);
  return f.copyWith(ageMin: lo, ageMax: hi);
}

Future<void> _showFilterSheet(BuildContext context, SearchFilters current) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _AdvancedFilterSheet(initial: current),
  );
}


/// Summary strip showing the active filters; tapping opens the full sheet.
class _FilterBar extends StatelessWidget {
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  const _FilterBar({required this.filters, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    void addChip(String label, SearchFilters cleared) {
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: () => onChanged(cleared),
          deleteButtonTooltipMessage: 'Remove the $label filter',
        ),
      );
    }

    if (filters.ageMin != null || filters.ageMax != null) {
      addChip(
        'Age ${filters.ageMin ?? 18}-${filters.ageMax ?? 120}',
        filters.copyWith(clearAge: true),
      );
    }
    if (filters.interestedIn.isNotEmpty) {
      addChip(
        filters.interestedIn.join(', '),
        filters.copyWith(interestedIn: const []),
      );
    }
    if (filters.relationshipIntents.isNotEmpty) {
      addChip(
        filters.relationshipIntents.length == 1
            ? filters.relationshipIntents.first
            : '${filters.relationshipIntents.length} intents',
        filters.copyWith(relationshipIntents: const []),
      );
    }
    if (filters.cities.isNotEmpty) {
      addChip(filters.cities.join(', '), filters.copyWith(cities: const []));
    }
    if (filters.interests.isNotEmpty) {
      addChip(
        'Interests: ${filters.interests.length}',
        filters.copyWith(interests: const []),
      );
    }
    if (filters.languages.isNotEmpty) {
      addChip(
        filters.languages.join(', '),
        filters.copyWith(languages: const []),
      );
    }
    if (filters.smoking != null) {
      addChip(
        'Smoking: ${filters.smoking}',
        filters.copyWith(clearSmoking: true),
      );
    }
    if (filters.drinking != null) {
      addChip(
        'Drinking: ${filters.drinking}',
        filters.copyWith(clearDrinking: true),
      );
    }
    if (filters.exercise != null) {
      addChip(
        'Exercise: ${filters.exercise}',
        filters.copyWith(clearExercise: true),
      );
    }
    if (filters.children != null) {
      addChip(
        'Children: ${filters.children}',
        filters.copyWith(clearChildren: true),
      );
    }
    if (filters.pets != null) {
      addChip('Pets: ${filters.pets}', filters.copyWith(clearPets: true));
    }

    final spaced = <Widget>[];
    for (final c in chips) {
      spaced
        ..add(c)
        ..add(const SizedBox(width: 8));
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          ActionChip(
            avatar: const Icon(Icons.tune_rounded, size: 18),
            label: Text(
              filters.hasActiveFilters
                  ? 'Filters (${filters.activeFilterCount})'
                  : 'Filters',
            ),
            onPressed: () => _showFilterSheet(context, filters),
          ),
          const SizedBox(width: 8),
          ...spaced,
        ],
      ),
    );
  }
}

/// The "nothing matched" state.
///
/// The message is truthful: the server really did apply every filter. The
/// three actions are explicit, user-initiated widenings.
class _NoMatchesView extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onAdjust;
  final VoidCallback onIncreaseDistance;
  final VoidCallback onExpandAge;

  const _NoMatchesView({
    required this.hasFilters,
    required this.onAdjust,
    required this.onIncreaseDistance,
    required this.onExpandAge,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 20),
        Text(
          'No profiles match all your filters',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          hasFilters
              ? 'Every filter you set is applied together. Try widening one of '
                    'them to see more people.'
              : 'There is nobody nearby yet. Check back soon or try a wider area.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onAdjust,
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Adjust filters'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onIncreaseDistance,
          icon: const Icon(Icons.social_distance_rounded),
          label: const Text('Increase distance'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onExpandAge,
          icon: const Icon(Icons.cake_outlined),
          label: const Text('Expand age range'),
        ),
      ],
    );
  }
}


/// One search result row.
class _SearchResultTile extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onOpen;

  const _SearchResultTile({required this.profile, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = profile.photos.isEmpty ? null : profile.photos.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: photo == null
                      ? ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person_outline_rounded),
                        )
                      : Image.network(
                          photo,
                          fit: BoxFit.cover,
                          // A broken or expired signed URL must not crash the
                          // row; show a neutral placeholder instead.
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (profile.isPhotoVerified) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Age 0 means "not stated" - never render a made-up age.
                    Text(
                      profile.age > 0 ? '${profile.age}' : 'Age not stated',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            // Privacy-safe: the server supplies this label.
                            profile.distanceDisplay.isEmpty
                                ? 'Nearby'
                                : profile.distanceDisplay,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (profile.commonInterests.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: profile.commonInterests
                            .take(3)
                            .map((i) => _InterestPill(label: i))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded label used for shared interests.
class _InterestPill extends StatelessWidget {
  final String label;

  const _InterestPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}


/// Dual-handle age range. Both bounds null means "any".
class _AgeRangeSelector extends StatelessWidget {
  final int? min;
  final int? max;
  final void Function(int?, int?) onChanged;

  const _AgeRangeSelector({
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final lo = (min ?? 18).clamp(18, 100);
    final hi = (max ?? 100).clamp(18, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                min == null && max == null
                    ? 'Any age'
                    : '$lo - ${hi >= 100 ? '100+' : hi}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (min != null || max != null)
              TextButton(
                onPressed: () => onChanged(null, null),
                child: const Text('Any'),
              ),
          ],
        ),
        RangeSlider(
          values: RangeValues(lo.toDouble(), hi.toDouble()),
          min: 18,
          max: 100,
          divisions: 82,
          labels: RangeLabels('$lo', '$hi'),
          onChanged: (v) => onChanged(v.start.round(), v.end.round()),
        ),
      ],
    );
  }
}

/// A single-select chip group (lifestyle attributes).
class _SingleSelect extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _SingleSelect({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (o) => ChoiceChip(
                    label: Text(o),
                    selected: value == o,
                    onSelected: (sel) => onChanged(sel ? o : null),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}


/// The full multi-filter editor.
///
/// The draft is local to the sheet; nothing is applied until the user taps
/// "Apply filters", so a half-built query is never sent to the database.
class _AdvancedFilterSheet extends ConsumerStatefulWidget {
  final SearchFilters initial;

  const _AdvancedFilterSheet({required this.initial});

  @override
  ConsumerState<_AdvancedFilterSheet> createState() =>
      _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState
    extends ConsumerState<_AdvancedFilterSheet> {
  late SearchFilters _draft = widget.initial;
  late final TextEditingController _cityController = TextEditingController(
    text: widget.initial.searchCity ?? '',
  );

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  void _apply() {
    final city = _cityController.text.trim();
    Navigator.of(context).pop();
    ref.read(searchProvider.notifier).applyFilters(
      _draft.copyWith(
        cities: city.isEmpty ? const [] : [city],
        clearSearchCity: city.isEmpty,
        searchCity: city.isEmpty ? null : city,
      ),
    );
  }

  /// Toggle a value inside one of the multi-select lists.
  void _toggleMulti(
    String value,
    List<String> current,
    void Function(List<String>) apply,
  ) {
    final next = List<String>.from(current);
    if (!next.remove(value)) next.add(value);
    apply(next);
  }

  void _reset() {
    setState(() {
      _draft = _draft.cleared();
      _cityController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: _sections(context),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply filters'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );

  List<Widget> _sections(BuildContext context) => <Widget>[
    _section(context, 'Distance'),
    _distanceChips(),
    const SizedBox(height: 8),
    Text(
      'Filters are applied on the server. Your exact location is never shown '
      'to anyone.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 24),
    _section(context, 'Interested in'),
    _genderChips(),
    const SizedBox(height: 24),
    _section(context, 'Age range'),
    _ageSelector(),
    const SizedBox(height: 24),
    _section(context, 'Relationship intent'),
    _intentChips(),
    const SizedBox(height: 24),
    _section(context, 'City'),
    _cityField(),
    const SizedBox(height: 24),
    _section(context, 'Interests'),
    _interestChips(),
    const SizedBox(height: 24),
    _section(context, 'Languages'),
    _languageChips(),
    const SizedBox(height: 24),
    _section(context, 'Lifestyle'),
    _lifestyle(),
    const SizedBox(height: 8),
    SwitchListTile(
      value: _draft.includeDealt,
      onChanged: (v) => setState(
        () => _draft = _draft.copyWith(includeDealt: v),
      ),
      title: const Text('Include people I have already seen'),
      subtitle: const Text(
        'Off by default so you are not shown the same profiles twice.',
      ),
    ),
  ];


  Widget _distanceChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _distanceOptionsKm
        .map(
          (km) => ChoiceChip(
            label: Text('${km.toInt()} km'),
            selected: _draft.maxDistanceKm == km,
            onSelected: (_) => setState(
              () => _draft = _draft.copyWith(maxDistanceKm: km),
            ),
          ),
        )
        .toList(),
  );

  Widget _genderChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _genders
        .map(
          (g) => FilterChip(
            label: Text(g),
            selected: _draft.interestedIn.contains(g),
            onSelected: (sel) => setState(
              () => _toggleMulti(
                g,
                _draft.interestedIn,
                (v) => _draft = _draft.copyWith(interestedIn: v),
              ),
            ),
          ),
        )
        .toList(),
  );

  Widget _ageSelector() => _AgeRangeSelector(
    min: _draft.ageMin,
    max: _draft.ageMax,
    onChanged: (min, max) => setState(
      () => _draft = min == null && max == null
          ? _draft.copyWith(clearAge: true)
          : _draft.copyWith(ageMin: min, ageMax: max),
    ),
  );

  Widget _intentChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _relationshipIntents
        .map(
          (r) => FilterChip(
            label: Text(r),
            selected: _draft.relationshipIntents.contains(r),
            onSelected: (sel) => setState(
              () => _toggleMulti(
                r,
                _draft.relationshipIntents,
                (v) => _draft = _draft.copyWith(relationshipIntents: v),
              ),
            ),
          ),
        )
        .toList(),
  );

  Widget _cityField() => TextField(
    controller: _cityController,
    textCapitalization: TextCapitalization.words,
    decoration: const InputDecoration(
      labelText: 'City',
      helperText: 'Exact city name, e.g. Pune',
      prefixIcon: Icon(Icons.location_city_outlined),
      border: OutlineInputBorder(),
    ),
  );

  Widget _interestChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _interests
        .map(
          (i) => FilterChip(
            label: Text(i),
            selected: _draft.interests.contains(i),
            onSelected: (sel) => setState(
              () => _toggleMulti(
                i,
                _draft.interests,
                (v) => _draft = _draft.copyWith(interests: v),
              ),
            ),
          ),
        )
        .toList(),
  );

  Widget _languageChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _languages
        .map(
          (l) => FilterChip(
            label: Text(l),
            selected: _draft.languages.contains(l),
            onSelected: (sel) => setState(
              () => _toggleMulti(
                l,
                _draft.languages,
                (v) => _draft = _draft.copyWith(languages: v),
              ),
            ),
          ),
        )
        .toList(),
  );

  Widget _lifestyle() => Column(
    children: [
      _SingleSelect(
        label: 'Smoking',
        options: _smokingOptions,
        value: _draft.smoking,
        onChanged: (v) => setState(
          () => _draft = v == null
              ? _draft.copyWith(clearSmoking: true)
              : _draft.copyWith(smoking: v),
        ),
      ),
      _SingleSelect(
        label: 'Drinking',
        options: _drinkingOptions,
        value: _draft.drinking,
        onChanged: (v) => setState(
          () => _draft = v == null
              ? _draft.copyWith(clearDrinking: true)
              : _draft.copyWith(drinking: v),
        ),
      ),
      _SingleSelect(
        label: 'Exercise',
        options: _exerciseOptions,
        value: _draft.exercise,
        onChanged: (v) => setState(
          () => _draft = v == null
              ? _draft.copyWith(clearExercise: true)
              : _draft.copyWith(exercise: v),
        ),
      ),
      _SingleSelect(
        label: 'Children',
        options: _childrenOptions,
        value: _draft.children,
        onChanged: (v) => setState(
          () => _draft = v == null
              ? _draft.copyWith(clearChildren: true)
              : _draft.copyWith(children: v),
        ),
      ),
      _SingleSelect(
        label: 'Pets',
        options: _petsOptions,
        value: _draft.pets,
        onChanged: (v) => setState(
          () => _draft = v == null
              ? _draft.copyWith(clearPets: true)
              : _draft.copyWith(pets: v),
        ),
      ),
    ],
  );
}

