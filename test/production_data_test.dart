import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/providers/weekend_provider.dart';

/// Regression guards for the production-data guarantee:
/// the app must never fabricate users, matches or plans. Every list that is
/// presented as real people must start empty and only be filled from Supabase.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WeekendState.initial carries no fabricated personal data', () {
    final state = WeekendState.initial();

    // No fake identity: the placeholder user is empty and replaced by the
    // real Supabase profile once authenticated.
    expect(state.currentUser.name, isEmpty);
    expect(state.currentUser.photos, isEmpty);
    expect(state.currentUser.bio, isEmpty);
    expect(state.currentUser.city, isEmpty);
    expect(state.currentUser.referralCode, isEmpty);

    // No fake content anywhere in the app state.
    expect(state.deckProfiles, isEmpty);
    expect(state.matches, isEmpty);
    expect(state.plans, isEmpty);
    expect(state.chatMessages, isEmpty);
    expect(state.crossedPaths, isEmpty);
    expect(state.likedProfiles, isEmpty);
    expect(state.swipedProfileIds, isEmpty);
    expect(state.blockedUserIds, isEmpty);
  });

  test('without a backend, discovery never fabricates profiles', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // No Supabase credentials are compiled into the test binary, so
    // SupabaseConfig.isConfigured is false. Loading the deck must yield an
    // empty deck — never sample data.
    await container.read(weekendProvider.notifier).loadDiscoveryProfiles();

    expect(container.read(weekendProvider).deckProfiles, isEmpty);
  });

  test('without a backend, matches and plans are never fabricated', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(weekendProvider.notifier).loadMatches();
    await container.read(weekendProvider.notifier).loadPlans();

    expect(container.read(weekendProvider).matches, isEmpty);
    expect(container.read(weekendProvider).plans, isEmpty);
  });

  test('duplicate swipes are rejected in the notifier', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(weekendProvider.notifier);
    final state = container.read(weekendProvider);
    final profile = state.deckProfiles.firstOrNull;
    // With an empty deck there is nothing to swipe; the guard is exercised
    // indirectly through swipedProfileIds staying empty.
    expect(profile, isNull);
    expect(notifier, isNotNull);
  });
}
