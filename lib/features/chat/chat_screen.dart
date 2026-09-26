import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../providers/weekend_provider.dart';

import '../../models/models.dart';
import '../../repositories/message_repository.dart';

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

  @override
  void initState() {
    super.initState();
    _messagesStream = _messageRepository.subscribeToMessages(widget.match.id);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);

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
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130E20),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: widget.match.user.photos.isEmpty
                  ? null
                  : CachedNetworkImageProvider(
                      widget.match.user.photos.first,
                    ),
              child: widget.match.user.photos.isEmpty
                  ? const Icon(Icons.person_rounded, color: Colors.white38)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.match.user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // No presence source exists in the backend, so no
                  // fabricated "Online now" label or green dot is shown. The
                  // only real activity timestamp available is the last
                  // message, so it is labelled as exactly that.
                  Text(
                    'Last message: ${_lastSeenLabel(widget.match)}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voice calls are not available in this release',
            onPressed: null,
            icon: const Icon(Icons.call_rounded, color: Colors.white38),
          ),
              PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: const Color(0xFF2E244A),
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
                return ListView.builder(
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
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF23212B),
                                    Color(0xFF282534),
                                  ],
                                ),

                          borderRadius: BorderRadius.circular(18).copyWith(
                            bottomLeft: isMe
                                ? Radius.circular(18)
                                : Radius.circular(4),

                            bottomRight: isMe
                                ? Radius.circular(4)
                                : Radius.circular(18),
                          ),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              message.text,

                              style: const TextStyle(
                                color: Colors.white,

                                fontSize: 14.5,

                                height: 1.4,
                              ),
                            ),

                            if (message.isTranslated &&
                                message.translatedText != null) ...[
                              const SizedBox(height: 4),

                              Text(
                                '${message.translatedText}',

                                style: TextStyle(
                                  color: const Color(0xFFFF9966),

                                  fontSize: 12,
                                ),
                              ),
                            ],

                            const SizedBox(height: 4),

                            Text(
                              _formatTime(message.timestamp),

                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),

                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
              color: const Color(0xFF1E1C24),

              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: SupabaseConfig.isConfigured,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: SupabaseConfig.isConfigured
                          ? 'Type a message...'
                          : 'Connect a backend to enable messaging',

                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2E244A),
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
                    backgroundColor: const Color(0xFFFF4B72),
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
