import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/models.dart';
import '../../providers/interactions_provider.dart';
import '../../providers/weekend_provider.dart';
import '../../widgets/weekend_design_system.dart';
import '../../widgets/weekend_empty_state.dart';
import '../../widgets/weekend_states.dart';

/// People who liked this user.
///
/// This surface did not exist at any layer. The `likes` table is directional and
/// its SELECT policy has always permitted reading inbound likes, but nothing in
/// `lib/` ever issued that query and no notification was produced for a
/// one-sided like, so the information was collected and then never shown to
/// anyone.
///
/// Non-mutual likes only - a mutual like is a match and already appears on the
/// matches tab. The exclusion is enforced server-side in `get_received_likes` so
/// the two tabs cannot disagree.
class LikesScreen extends ConsumerStatefulWidget {
  const LikesScreen({super.key, this.onOpenDiscover});

  /// Sends the user to discovery from the empty state. Supplied when the screen
  /// is embedded as a tab, where there is no navigation stack to pop.
  final VoidCallback? onOpenDiscover;

  @override
  ConsumerState<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends ConsumerState<LikesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(receivedLikesProvider.notifier).load();
    });
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
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(receivedLikesProvider.notifier).loadMore();
    }
  }

  /// Like back. Routes through the same `swipeRight` the discovery card uses, so
  /// the gesture and this button cannot diverge into two business paths.
  Future<void> _likeBack(ReceivedLike like) async {
    final matched = await ref
        .read(weekendProvider.notifier)
        .swipeRight(like.profile);

    if (!mounted) return;

    if (matched) {
      // It became a match, so it is no longer a pending like.
      ref.read(receivedLikesProvider.notifier).remove(like.profile.id);
      ref.read(weekendProvider.notifier).clearCelebration();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You and ${like.profile.name} matched!')),
      );
    }
  }

  /// Pass. `record_pass` withdraws the outstanding like server-side, so the row
  /// is removed locally rather than left offering an action that would now be
  /// refused.
  Future<void> _pass(ReceivedLike like) async {
    await ref.read(weekendProvider.notifier).swipeLeft(like.profile.id);
    if (!mounted) return;
    ref.read(receivedLikesProvider.notifier).remove(like.profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receivedLikesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Likes you')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(receivedLikesProvider.notifier).load(),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(ReceivedLikesState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return WeekendErrorState(
        message: state.error!,
        onRetry: () => ref.read(receivedLikesProvider.notifier).load(),
      );
    }

    if (state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 96),
          WeekendEmptyState(
            icon: Icons.star_outline_rounded,
            title: 'No likes yet',
            subtitle:
                'When someone likes you, they will appear here. Keep '
                'discovering to be the first to say hello.',
            actionLabel: 'Start discovering',
            onAction: () {
              final callback = widget.onOpenDiscover;
              if (callback != null) {
                callback();
              } else {
                context.go('/home');
              }
            },
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final like = state.items[index];
        return _LikeCard(
          like: like,
          onLikeBack: () => _likeBack(like),
          onPass: () => _pass(like),
        );
      },
    );
  }
}

class _LikeCard extends StatelessWidget {
  final ReceivedLike like;
  final VoidCallback onLikeBack;
  final VoidCallback onPass;

  const _LikeCard({
    required this.like,
    required this.onLikeBack,
    required this.onPass,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = like.profile;
    final name = profile.name;
    final age = profile.age;

    return WeekendCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Photo(photoUrl: profile.photos.isEmpty ? null : profile.photos.first),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        // An age of 0 means the database had no date of birth.
                        // Rendering "0" would be nonsense and rendering a
                        // made-up age is worse, so the age is omitted.
                        age > 0 ? '$name, $age' : name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (profile.isPhotoVerified) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Photo verified',
                        child: Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (profile.city.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.city,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (like.isStandOut) ...[
                  const SizedBox(height: 6),
                  // `likes.is_stand_out` was a write-only column before
                  // migration 026 - nothing ever read it back.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Stood out for you',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (like.likedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Liked ${timeago.format(like.likedAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Every swipe action has a button equivalent. The
                    // discovery card's buttons already exist for this reason;
                    // a gesture-only interaction is unusable with a screen
                    // reader and with switch access.
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPass,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Pass'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onLikeBack,
                        icon: const Icon(Icons.favorite_rounded, size: 18),
                        label: const Text('Like'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar that tolerates a profile with no photo instead of trying to load an
/// empty URL.
class _Photo extends StatelessWidget {
  final String? photoUrl;

  const _Photo({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (photoUrl == null || photoUrl!.isEmpty) {
      return Container(
        width: 72,
        height: 96,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.person_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: photoUrl!,
        width: 72,
        height: 96,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 72,
          height: 96,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        // A broken photo URL must not leave a broken-image glyph on a dating
        // card; fall back to the same neutral placeholder as "no photo".
        errorWidget: (_, __, ___) => Container(
          width: 72,
          height: 96,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}