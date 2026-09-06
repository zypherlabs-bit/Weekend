import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/weekend_provider.dart';
import '../../models/models.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final MatchItem match;

  const ChatScreen({super.key, required this.match});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    
    ref.read(weekendProvider.notifier).sendMessage(
      widget.match.id,
      _messageController.text.trim(),
    );
    
    _messageController.clear();
    
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final messages = state.chatMessages[widget.match.id] ?? [];
    final currentUserId = state.currentUser.id;

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
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: CachedNetworkImageProvider(widget.match.user.photos.firstOrNull ?? ''),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF130E20), width: 2),
                    ),
                  ),
                ),
              ],
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
                  const Text(
                    'Online now',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
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
            onPressed: () {},
            icon: const Icon(Icons.call_rounded, color: Colors.white),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: const Color(0xFF2E244A),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'date_ideas',
                child: Text('Smart Date Ideas', style: TextStyle(color: Color(0xFFFF9966))),
              ),
              const PopupMenuItem(
                value: 'share_date',
                child: Text('Share My Date', style: TextStyle(color: Color(0xFFFF4B72))),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Text('Block User', style: TextStyle(color: Colors.grey)),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Text('Report Profile', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (value) {
              // Handle menu actions
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isMe = message.senderId == currentUserId;
                
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(
                      bottom: 8,
                      left: isMe ? 48 : 0,
                      right: isMe ? 0 : 48,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              colors: [Color(0xFFFF5E62), Color(0xFFFF4081)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF23212B), Color(0xFF282534)],
                            ),
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomLeft: isMe ? Radius.circular(18) : Radius.circular(4),
                        bottomRight: isMe ? Radius.circular(4) : Radius.circular(18),
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
                        if (message.isTranslated && message.translatedText != null) ...[
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
                            color: Colors.white.withOpacity(0.6),
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
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1C24),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.image_rounded, color: Colors.white.withOpacity(0.6)),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2E244A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
