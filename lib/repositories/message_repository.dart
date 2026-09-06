import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class MessageRepository {
  Future<List<ChatMessage>> loadMessages(String matchId) async {
    try {
      final conversation = await Supabase.instance.client
          .from('conversations')
          .select()
          .eq('match_id', matchId)
          .single();
      
      final messages = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('conversation_id', conversation['id'])
          .order('created_at', ascending: true);
      
      return (messages as List).map((msg) {
        return ChatMessage(
          id: msg['id'],
          senderId: msg['sender_id'],
          text: msg['text'] ?? '',
          timestamp: DateTime.parse(msg['created_at']).millisecondsSinceEpoch,
          translatedText: msg['translated_text'],
          isTranslated: msg['is_translated'] ?? false,
          isRead: msg['is_read'] ?? false,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<ChatMessage> sendMessage(String matchId, String text) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    
    final conversation = await Supabase.instance.client
        .from('conversations')
        .select()
        .eq('match_id', matchId)
        .maybeSingle();
    
    String conversationId;
    if (conversation != null) {
      conversationId = conversation['id'];
    } else {
      final newConv = await Supabase.instance.client
          .from('conversations')
          .insert({'match_id': matchId})
          .select()
          .single();
      conversationId = newConv['id'];
    }
    
    final message = await Supabase.instance.client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': userId,
          'text': text,
        })
        .select()
        .single();
    
    return ChatMessage(
      id: message['id'],
      senderId: message['sender_id'],
      text: message['text'] ?? '',
      timestamp: DateTime.parse(message['created_at']).millisecondsSinceEpoch,
      isRead: message['is_read'] ?? false,
    );
  }

  Future<void> subscribeToMessages(String matchId) async {
    try {
      final conversation = await Supabase.instance.client
          .from('conversations')
          .select()
          .eq('match_id', matchId)
          .single();
      
      Supabase.instance.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversation['id'])
          .listen((data) {
            // Handle realtime messages
          });
    } catch (e) {
      // ignore
    }
  }

  Future<void> translateMessage(String matchId, String messageId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'translate-message',
        body: {'messageId': messageId},
      );
    } catch (e) {
      // ignore
    }
  }
}
