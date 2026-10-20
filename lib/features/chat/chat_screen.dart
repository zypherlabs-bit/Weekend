import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../config/supabase_config.dart';
import '../../providers/weekend_provider.dart';
import '../../repositories/match_repository.dart';
import '../../repositories/message_repository.dart';
import '../../repositories/privacy_repository.dart';
import '../../widgets/date_ideas_widget.dart';
import '../../widgets/icebreaker_widget.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final MatchItem match;

  const ChatScreen({super.key, required this.match});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Stream<List<ChatMessage>>? _messagesStream;

  final MessageRepository _messageRepository = MessageRepository();
  final MatchRepository _matchRepository = MatchRepository();
  final PrivacyRepository _privacyRepository = PrivacyRepository();

  /// The OTHER member's away note, conversation-scoped. Seeded from
  /// `get_matches_for_user` (via `MatchItem.awayMessage`) and refreshed once
  /// from `get_conversation_away_note` on entry, so it reflects the current
  /// server state rather than the last matches fetch.
  String _awayNote = '';

  /// The match's initiation-window deadline in epoch millis (0 = none/known).
  /// Only ever advanced by the server's `extend_match` response.
  int _windowEndsAtMs = 0;

  bool _windowActionInFlight = false;

  @override
  void initState() {
    super.initState();
    _messagesStream = _messageRepository.subscribeToMessages(widget.match.id);
    _awayNote = widget.match.awayMessage;
    _windowEndsAtMs = widget.match.windowEndsAtMs;
    _refreshAwayNote();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    final text = _messageController.text.trim();
    _messageController.clear();
    _scrollToBottom();
    try {
      // Persisted via the provider; the persisted row is delivered to both
      // participants through the Realtime subscription — no local echo.
      await ref.read(weekendProvider.notifier).sendMessage(
            widget.match.id,
            text,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message failed to send. Check your connection.'),
            backgroundColor: Color(0xFFFF4B72),
          ),
        );
      }
      // Restore the text so the user can retry without retyping.
      if (mounted) setState(() => _messageController.text = text);
    }
  }

  /// A relative label for the last message, derived from real database data.
  /// Returns an explicit "unknown" rather than inventing a recency.
  String _lastSeenLabel(MatchItem match) {
    final value = match.lastMessageTime.trim();
    if (value.isEmpty) return 'unknown';
    if (value == 'No messages yet') return value;
    return value;
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF4CAF50),
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  Future<void> _refreshAwayNote() async {
    // No conversation row exists yet server-side, so there is no member pair
    // to read an away note for — the seeded value stays as-is.
    final conversationId = widget.match.conversationId;
    if (conversationId.isEmpty) return;
    final result = await _privacyRepository.fetchConversationAwayNote(
      conversationId,
    );
    if (!mounted || result == null) return;
    final note = result.away ? result.message : '';
    if (note == _awayNote) return;
    setState(() => _awayNote = note);
  }

  /// Display status derived from the server's `initiation_status` and the
  /// server-provided deadline. `active` and `no_window` (and blank values
  /// from an older backend) mean no action bar, and once messages exist the
  /// window is settled server-side.
  String _effectiveInitiationStatus({required bool conversationStarted}) {
    final status = widget.match.initiationStatus;
    if (conversationStarted && status != 'expired') return '';
    if (conversationStarted) return 'expired';
    switch (status) {
      case 'awaiting_you':
      case 'awaiting_them':
        // The local clock can read the window as expired slightly before the
        // server does; display-only, enforcement stays server-side.
        if (_windowEndsAtMs > 0 &&
            DateTime.now().millisecondsSinceEpoch >= _windowEndsAtMs) {
          return 'expired';
        }
        return status;
      case 'expired':
        return 'expired';
      default:
        return '';
    }
  }

  String _countdownSuffix() {
    if (_windowEndsAtMs == 0) return '';
    final remaining = _windowEndsAtMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return '';
    final hours = remaining ~/ 3600000;
    final minutes = (remaining % 3600000) ~/ 60000;
    if (hours > 0) return ' · ${hours}h ${minutes}m left';
    return ' · ${minutes}m left';
  }

  /// Server-verified extension: only advances to the deadline `extend_match`
  /// reports and never fabricates one on failure.
  Future<void> _extendWindow() async {
    if (_windowActionInFlight) return;
    setState(() => _windowActionInFlight = true);
    final deadline = await _matchRepository.extendMatch(widget.match.id);
    if (!mounted) return;
    setState(() {
      _windowActionInFlight = false;
      if (deadline > 0) _windowEndsAtMs = deadline;
    });
    if (deadline > 0) {
      _notify('Window extended — the new deadline was set by the server.');
    } else {
      _notify('Could not extend the window. It may have already been extended.',
          isError: true);
    }
  }

  /// Rematch path: another like from this user while the partner's like is
  /// outstanding re-opens a fresh window via `check_mutual_like` (at most
  /// one rematch per 7 days, enforced server-side).
  Future<void> _rematch() async {
    if (_windowActionInFlight) return;
    final me = SupabaseConfig.currentUserId;
    if (me.isEmpty) return;
    setState(() => _windowActionInFlight = true);
    final outcome = await _matchRepository.recordLike(
      me,
      widget.match.user.id,
    );
    if (!mounted) return;
    setState(() => _windowActionInFlight = false);
    switch (outcome) {
      case LikeOutcome.matched:
        _notify('Rematched — a fresh 24-hour opening window is live.');
        break;
      case LikeOutcome.recorded:
        _notify('Like re-sent. The window reopens if they still like you.');
        break;
      case LikeOutcome.failed:
        _notify('Rematch failed. Please try again.', isError: true);
        break;
    }
  }

  Widget _lifecycleArea(List<ChatMessage> messages) {
    final banners = <Widget>[];
    if (_awayNote.isNotEmpty) banners.add(_awayBanner());
    final status =
        _effectiveInitiationStatus(conversationStarted: messages.isNotEmpty);
    if (status == 'awaiting_you') {
      banners.add(_windowBar(
        'It’s your move — send the first message',
        _countdownSuffix(),
        icon: Icons.edit_rounded,
      ));
    } else if (status == 'awaiting_them') {
      banners.add(_windowBar(
        'Waiting for ${widget.match.user.name} to send the first message',
        _countdownSuffix(),
        icon: Icons.hourglass_top_rounded,
      ));
    } else if (status == 'expired') {
      banners.add(_expiredBar());
    }
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(children: banners);
  }

  Widget _awayBanner() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.warningAmber.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.do_not_disturb_on_rounded,
              color: Color(0xFFFFB74D), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.match.user.name} is away: “$_awayNote”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFFFFB74D)
                    : const Color(0xFF8A4B00),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _windowBar(String label, String suffix, {IconData? icon}) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Icon(icon ?? Icons.hourglass_top_rounded, color: secondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label + suffix,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _windowActionInFlight ? null : _extendWindow,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: _windowActionInFlight
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Extend +24h'),
          ),
        ],
      ),
    );
  }

  Widget _expiredBar() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
      child: Row(
        children: [
          Icon(Icons.timer_off_rounded, color: theme.colorScheme.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The first-message window expired',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: _windowActionInFlight ? null : _rematch,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: _windowActionInFlight
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Rematch'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final theme = Theme.of(context);

    // Message ownership must come from the auth session. `state.currentUser.id`
    // is the 'me' placeholder until the profile load resolves, which would
    // render every bubble on the wrong side.
    final authId = SupabaseConfig.client?.auth.currentUser?.id;
    final currentUserId = (authId != null &&
            authId.isNotEmpty &&
            authId != 'unauthenticated' &&
            authId != 'me')
        ? authId
        : state.currentUser.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              backgroundImage: widget.match.user.photos.isEmpty
                  ? null
                  : CachedNetworkImageProvider(
                      widget.match.user.photos.first,
                    ),
              child: widget.match.user.photos.isEmpty
                  ? Icon(
                      Icons.person_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.match.user.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // No presence source exists in the backend, so no
                  // fabricated "Online now" label or green dot is shown. The
                  // only real activity timestamp available is the last
                  // message, so it is labelled as exactly that.
                  Text(
                    'Last message: ${_lastSeenLabel(widget.match)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
         actions: [
DateIdeasButton(
              partnerInterests: widget.match.user.interests,
              city: state.currentUser.city.isNotEmpty
                  ? state.currentUser.city
                  : widget.match.user.city,
            ),
            IcebreakerButton(
              match: widget.match,
              currentUser: state.currentUser,
            ),
           IconButton(
             tooltip: 'Voice calls are not available in this release',
             onPressed: null,
             icon: Icon(
               Icons.call_rounded,
               color: theme.colorScheme.onSurfaceVariant.withValues(
                 alpha: 0.5,
               ),
             ),
           ),
            PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded),
            color: theme.colorScheme.surfaceContainerHigh,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'block',
                child: Text('Block User', style: TextStyle(color: Colors.grey)),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Text(
                  'Report Profile',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
            onSelected: (value) async {
              final otherId = widget.match.user.id;
              final navigator = Navigator.of(context);
              try {
                switch (value) {
                  case 'block':
                    await ref
                        .read(weekendProvider.notifier)
                        .blockUser(otherId);
                    if (mounted) _notify('User blocked.');
                    break;
                  case 'report':
                    await ref
                        .read(weekendProvider.notifier)
                        .reportUser(otherId, 'Inappropriate behavior');
                    if (mounted) _notify('Report submitted.');
                    break;
                }
              } catch (e) {
                // The write is no longer swallowed upstream, so a rejected
                // block/report is reported instead of looking successful.
                if (mounted) {
                  _notify(
                    'Could not save that action. Please try again.',
                    isError: true,
                  );
                }
              }
              if (navigator.canPop()) navigator.pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                return Column(
                  children: [
                    _lifecycleArea(messages),
                    Expanded(
                      child: ListView.builder(
                  controller: _scrollController,

                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),

                  itemCount: messages.length,

                  itemBuilder: (context, index) {
                    final message = messages[index];

                    final isMe = message.senderId == currentUserId;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,

                      child: Container(
                        margin: EdgeInsets.only(
                          bottom: 8,

                          left: isMe ? 48 : 0,

                          right: isMe ? 0 : 48,
                        ),

                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),

                        decoration: BoxDecoration(
                          gradient: isMe
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFFF5E62),
                                    Color(0xFFFF4081),
                                  ],
                                )
                              : null,
                          color: isMe
                              ? null
                              : theme.colorScheme.surfaceContainerHighest,

                          borderRadius: BorderRadius.circular(18).copyWith(
                            bottomLeft: isMe
                                ? const Radius.circular(18)
                                : const Radius.circular(4),

                            bottomRight: isMe
                                ? const Radius.circular(4)
                                : const Radius.circular(18),
                          ),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              message.text,

                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : theme.colorScheme.onSurface,

                                fontSize: 14.5,

                                height: 1.4,
                              ),
                            ),

                            // Explainable risk surfacing: server-computed
                            // flags only (migration 033). Never an automatic
                            // ban and never a fabricated warning — the
                            // flags are shown as the server produced them.
                            if (!isMe && message.riskFlags.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Flagged: ${message.riskFlags.join(' · ')}',
                                style: TextStyle(
                                  color: theme.brightness == Brightness.dark
                                      ? const Color(0xFFFFB74D)
                                      : const Color(0xFF8A4B00),
                                  fontSize: 11,
                                ),
                              ),
                            ],

                            if (message.isTranslated &&
                              message.translatedText != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${message.translatedText}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ],

                            if (!isMe && !message.isTranslated) ...[
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () async {
                                  await _messageRepository.translateMessage(
                                    widget.match.id,
                                    message.id,
                                  );
                                  setState(() {});
                                },
                                child: Text(
                                  'Translate',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 12,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 4),

                            Text(
                              _formatTime(message.timestamp),

                              style: TextStyle(
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : theme.colorScheme.onSurfaceVariant,

                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,

              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: SupabaseConfig.isConfigured,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: SupabaseConfig.isConfigured
                          ? 'Type a message...'
                          : 'Connect a backend to enable messaging',

                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.75,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                  ),
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
