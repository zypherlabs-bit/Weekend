import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../repositories/match_repository.dart';
import '../repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);

final matchRepositoryProvider = Provider<MatchRepository>((ref) => MatchRepository());

/// Unread notification count, used for the tab badge.
///
/// Kept separate from the notification list so the badge can be refreshed on a
/// timer / realtime push without rebuilding the list a user is scrolling.
class UnreadCountNotifier extends StateNotifier<int> {
  UnreadCountNotifier(this._repo) : super(0);

  final NotificationRepository _repo;

  Future<void> refresh() async {
    try {
      final count = await _repo.unreadCount();
      if (mounted) state = count;
    } catch (_) {
      // A failed count leaves the previous value. A badge is not worth an error
      // surface, and showing 0 when it is actually 12 is worse than showing a
      // slightly stale number.
    }
  }

  void decrement() {
    if (state > 0) state = state - 1;
  }

  /// Set the count directly.
  ///
  /// Used by the notification centre after a local mark-read, so the badge
  /// does not have to be re-fetched from the server for a change the client
  /// already knows about. Only accepts a non-negative value: a negative badge
  /// is never a real state.
  void setLocal(int count) {
    final safe = count < 0 ? 0 : count;
    if (safe != state) state = safe;
  }
}

final unreadCountProvider =
    StateNotifierProvider<UnreadCountNotifier, int>(
  (ref) => UnreadCountNotifier(ref.watch(notificationRepositoryProvider)),
);

/// State for the notification centre.
class NotificationCentreState {
  final List<AppNotification> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool reachedEnd;
  final String? error;

  const NotificationCentreState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.reachedEnd = false,
    this.error,
  });

  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationCentreState copyWith({
    List<AppNotification>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? reachedEnd,
    String? error,
    bool clearError = false,
  }) {
    return NotificationCentreState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      reachedEnd: reachedEnd ?? this.reachedEnd,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationCentreNotifier
    extends StateNotifier<NotificationCentreState> {
  NotificationCentreNotifier(this._repo) : super(const NotificationCentreState());

  static const _pageSize = 30;

  final NotificationRepository _repo;

  /// Reports the new unread count after a local mark-read so the tab badge can
  /// be updated without this notifier reaching into another provider.
  void Function(int count)? onUnreadChanged;

  /// Load the first page. Any previous error is cleared so a retry does not
  /// render the stale message underneath fresh results.
  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repo.fetchNotifications(limit: _pageSize);
      if (!mounted) return;
      state = state.copyWith(
        items: items,
        isLoading: false,
        reachedEnd: items.length < _pageSize,
        clearError: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Your notifications could not be loaded. Check your connection.',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.reachedEnd || state.isLoading) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final next = await _repo.fetchNotifications(
        limit: _pageSize,
        offset: state.items.length,
      );
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...next],
        isLoadingMore: false,
        reachedEnd: next.length < _pageSize,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: 'Could not load more notifications.',
      );
    }
  }

  /// Mark one notification read.
  ///
  /// The row updates immediately and [onUnreadChanged] reports the new local
  /// count, so the badge stays in step without the list having to reload. The
  /// server write follows. A failure is not surfaced because re-reading a
  /// notification is not destructive, and the entry will be re-synced on the
  /// next load.
  Future<void> markRead(String id) async {
    final index = state.items.indexWhere((n) => n.id == id);
    if (index == -1 || state.items[index].isRead) return;

    final updated = [...state.items];
    updated[index] = updated[index].copyWith(isRead: true);
    state = state.copyWith(items: updated);
    onUnreadChanged?.call(state.unreadCount);

    try {
      await _repo.markAsRead(id);
    } catch (_) {
      // Deliberately not reverted: the row stays read locally and the next
      // load reconciles with the server.
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;

    final updated = [
      for (final n in state.items)
        if (!n.isRead) n.copyWith(isRead: true) else n,
    ];
    state = state.copyWith(items: updated);
    onUnreadChanged?.call(0);

    await _repo.markAllAsRead();
  }

  /// Subscribe to new notifications so an inbound like appears without a pull to
  /// refresh.
  ///
  /// The subscription lives on [NotificationRepository], which holds and
  /// releases the handle. Keeping it there rather than opening a second
  /// Realtime channel here means one subscription per screen and one place
  /// responsible for tearing it down - the earlier leak came from attaching a
  /// listener and discarding the handle.
  void subscribe() {
    final client = SupabaseConfig.client;
    if (client == null) return;

    final userId = SupabaseConfig.currentUserId;
    if (userId == 'me' || userId == 'unauthenticated') return;

    _repo.subscribeToNotifications(
      userId,
      onNew: (incoming) {
        if (!mounted) return;
        // A duplicate would mean the row appears twice after a manual refresh.
        if (state.items.any((n) => n.id == incoming.id)) return;
        state = state.copyWith(items: [incoming, ...state.items]);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_repo.cancelSubscription());
    super.dispose();
  }
}

final notificationCentreProvider = StateNotifierProvider<
    NotificationCentreNotifier, NotificationCentreState>((ref) {
  final notifier = NotificationCentreNotifier(
    ref.watch(notificationRepositoryProvider),
  );
  notifier.onUnreadChanged = (count) =>
      ref.read(unreadCountProvider.notifier).setLocal(count);
  return notifier;
});

/// State for the "likes you" screen.
class ReceivedLikesState {
  final List<ReceivedLike> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool reachedEnd;
  final String? error;

  const ReceivedLikesState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.reachedEnd = false,
    this.error,
  });

  ReceivedLikesState copyWith({
    List<ReceivedLike>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? reachedEnd,
    String? error,
    bool clearError = false,
  }) {
    return ReceivedLikesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      reachedEnd: reachedEnd ?? this.reachedEnd,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ReceivedLikesNotifier extends StateNotifier<ReceivedLikesState> {
  ReceivedLikesNotifier(this._repo) : super(const ReceivedLikesState());

  static const _pageSize = 30;

  final MatchRepository _repo;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repo.fetchReceivedLikes(limit: _pageSize);
      if (!mounted) return;
      state = state.copyWith(
        items: items,
        isLoading: false,
        reachedEnd: items.length < _pageSize,
        clearError: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'We could not load your likes. Check your connection.',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.reachedEnd || state.isLoading) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final next = await _repo.fetchReceivedLikes(
        limit: _pageSize,
        offset: state.items.length,
      );
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...next],
        isLoadingMore: false,
        reachedEnd: next.length < _pageSize,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: 'Could not load more likes.',
      );
    }
  }

  /// Remove a like from the list locally.
  ///
  /// Used when the user passes on a received like: `record_pass` withdraws the
  /// outstanding like server-side, so keeping the row would offer an action the
  /// server would now refuse.
  void remove(String userId) {
    state = state.copyWith(
      items: state.items.where((l) => l.profile.id != userId).toList(),
    );
  }
}

final receivedLikesProvider =
    StateNotifierProvider<ReceivedLikesNotifier, ReceivedLikesState>(
  (ref) => ReceivedLikesNotifier(ref.watch(matchRepositoryProvider)),
);