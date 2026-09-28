import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../repositories/discovery_repository.dart';

/// Page size for the advanced search.
const _pageSize = 20;

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository();
});

/// State of the Discover / Search Filters screen.
class SearchState {
  final SearchFilters filters;
  final List<UserProfile> profiles;
  final bool isLoading;
  final bool isLoadingMore;
  final bool reachedEnd;
  final String? error;

  const SearchState({
    this.filters = const SearchFilters(),
    this.profiles = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.reachedEnd = false,
    this.error,
  });

  bool get hasError => error != null;

  /// True when the search finished cleanly and matched nothing.
  ///
  /// This is only meaningful when [hasError] is false: a failed request must
  /// never be reported to the user as "no matches".
  bool get isGenuinelyEmpty =>
      !isLoading && !hasError && profiles.isEmpty && reachedEnd;

  SearchState copyWith({
    SearchFilters? filters,
    List<UserProfile>? profiles,
    bool? isLoading,
    bool? isLoadingMore,
    bool? reachedEnd,
    String? error,
    bool clearError = false,
  }) {
    return SearchState(
      filters: filters ?? this.filters,
      profiles: profiles ?? this.profiles,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      reachedEnd: reachedEnd ?? this.reachedEnd,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
      return SearchNotifier(ref.watch(discoveryRepositoryProvider));
    });

/// Drives the advanced-search screen.
///
/// The notifier owns no filtering logic of its own beyond pagination: it
/// forwards [SearchFilters] to `search_profiles` and renders whatever the
/// database returns. Hard filters are enforced server-side by design.
class SearchNotifier extends StateNotifier<SearchState> {
  final DiscoveryRepository _repo;
  int _offset = 0;

  SearchNotifier(this._repo) : super(const SearchState());

  /// Re-run the search from the beginning with a new set of filters.
  Future<void> applyFilters(SearchFilters filters) async {
    _offset = 0;
    state = state.copyWith(
      filters: filters,
      profiles: const [],
      reachedEnd: false,
      isLoading: true,
      clearError: true,
    );
    await _fetch(replace: true);
  }

  /// Reload the current filters.
  Future<void> refresh() async {
    _offset = 0;
    state = state.copyWith(isLoading: true, clearError: true);
    await _fetch(replace: true);
  }

  /// Load the next page, if there is one.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || state.reachedEnd) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _fetch(replace: false);
  }

  Future<void> _fetch({required bool replace}) async {
    final userId = SupabaseConfig.currentUserId;

    // Not signed in (or no backend): say so honestly instead of showing an
    // empty list that looks like "nobody matches".
    if (userId == 'unauthenticated' || SupabaseConfig.client == null) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        profiles: const [],
        reachedEnd: true,
        error: SupabaseConfig.isConfigured
            ? 'Sign in to search for profiles.'
            : SupabaseConfig.configError,
      );
      return;
    }

    final result = await _repo.searchProfiles(
      state.filters,
      userId: userId,
      limit: _pageSize,
      offset: _offset,
    );

    if (!mounted) return;
    _offset += _pageSize;

    state = state.copyWith(
      isLoading: false,
      isLoadingMore: false,
      profiles: replace ? result.profiles : [...state.profiles, ...result.profiles],
      reachedEnd: result.reachedEnd,
      // reachedEnd=false on an empty page is the failure signal the
      // repository returns; surface it as an error rather than "no matches".
      error: result.profiles.isEmpty && !result.reachedEnd
          ? 'We could not complete that search. Please try again.'
          : null,
      clearError: result.profiles.isNotEmpty || result.reachedEnd,
    );
  }
}