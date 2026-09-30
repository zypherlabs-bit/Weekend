import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/models.dart';
import '../../providers/interactions_provider.dart';
import '../../widgets/weekend_empty_state.dart';
import '../../widgets/weekend_states.dart';

/// The notification centre.
///
/// This screen did not exist. The `notifications` table has existed since
/// migration 001 and the database has been inserting `new_match` and
/// `new_message` rows into it, but nothing in `lib/` ever read them back:
/// `NotificationRepository` was called from nowhere, and the only thing a user
/// ever saw was a transient system toast raised by `NotificationService`. Every
/// notification was therefore lost the moment it was dismissed.
///
/// Rows deep-link: a `new_message` opens the conversation, a `new_like` opens
/// the likes screen, a `new_match` opens the match. The target ids come from the
/// `data.payload` the database trigger writes, and each is validated by the
/// destination before anything is shown.
class NotificationCentreScreen extends ConsumerStatefulWidget {
  const NotificationCentreScreen({super.key, this.onNavigate});

  /// Called instead of route navigation when this screen is embedded as a tab.
  ///
  /// Embedded in the tab bar's IndexedStack there is no navigation stack to
  /// push onto - `context.canPop()` is false at the root, and a `push` here
  /// would strand the user with a back button that leaves the tab. The tab host
  /// passes this so tapping a notification switches tabs instead.
  final void Function(String notificationType)? onNavigate;

  @override
  ConsumerState<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState
    extends ConsumerState<NotificationCentreScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Deferred to after the first frame so `load()` may set state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationCentreProvider.notifier).load();
      ref.read(notificationCentreProvider.notifier).subscribe();
      ref.read(unreadCountProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Prefetch one screen ahead rather than at the very bottom, so the next page
  /// is usually already resident by the time the user reaches it.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(notificationCentreProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    await ref.read(notificationCentreProvider.notifier).load();
    await ref.read(unreadCountProvider.notifier).refresh();
  }

  /// Route to whatever a notification points at.
  ///
  /// Marks the entry read first, because arriving at the destination is the
  /// user acting on it. A notification with no resolvable target is still
  /// marked read but does nothing else, rather than navigating somewhere
  /// arbitrary.
  void _open(AppNotification notification) {
    ref.read(notificationCentreProvider.notifier).markRead(notification.id);

    // Embedded as a tab: hand the decision back to the tab host rather than
    // touching the navigation stack.
    final onNavigate = widget.onNavigate;
    if (onNavigate != null) {
      onNavigate(notification.type);
      return;
    }

    switch (notification.type) {
      case 'new_message':
        // `/chat/:matchId` is keyed by MATCH id, and the trigger now writes
        // `match_id` into the payload precisely so this does not need a second
        // round trip to translate a conversation id.
        final matchId = notification.targetMatchId;
        if (matchId != null) {
          context.push('/chat/$matchId');
        }
      case 'new_match':
        context.go('/home');
      case 'new_like':
        context.push('/likes');
      default:
        // `safety_alert`, `verification_result`, `referral_success`,
        // `plan_invitation` and anything unrecognised have no destination of
        // their own; they are informational only.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationCentreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationCentreProvider.notifier).markAllRead(),
              child: Text('Mark all read (${state.unreadCount})'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(NotificationCentreState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return WeekendErrorState(
        message: state.error!,
        onRetry: () => ref.read(notificationCentreProvider.notifier).load(),
      );
    }

    if (state.items.isEmpty) {
      // A scrollable is required so pull-to-refresh still works in the empty
      // state; returning a centred column here would disable it.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 96),
          WeekendEmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Nothing yet',
            subtitle:
                'Matches, likes and messages will show up here. Pull down to '
                'refresh.',
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final notification = state.items[index];
        return _NotificationTile(
          notification: notification,
          onTap: () => _open(notification),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  /// The six types the schema allows, plus the `new_like` value added in
  /// migration 026. Anything else renders with a neutral icon rather than
  /// being hidden, so an unfamiliar server-side type is visible rather than
  /// silently dropped.
  static (IconData, String) _visualFor(String type) {
    switch (type) {
      case 'new_match':
        return (Icons.favorite_rounded, 'New match');
      case 'new_message':
        return (Icons.chat_bubble_rounded, 'New message');
      case 'new_like':
        return (Icons.star_rounded, 'Someone liked you');
      case 'referral_success':
        return (Icons.card_giftcard_rounded, 'Referral reward');
      case 'plan_invitation':
        return (Icons.event_rounded, 'Plan invitation');
      case 'safety_alert':
        return (Icons.shield_rounded, 'Safety');
      case 'verification_result':
        return (Icons.verified_user_rounded, 'Verification');
      default:
        return (Icons.notifications_rounded, 'Update');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = _visualFor(notification.type);
    final unread = !notification.isRead;
    final when = notification.createdAt;

    return Semantics(
      button: true,
      label: '$label. ${notification.title}. '
          '${notification.isRead ? '' : 'Unread. '}'
          '${when == null ? '' : timeago.format(when)}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(
                    alpha: unread ? 0.18 : 0.08,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: unread
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title.isEmpty
                                ? label
                                : notification.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unread)
                          Semantics(
                            label: 'Unread',
                            child: Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (when != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        timeago.format(when),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
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