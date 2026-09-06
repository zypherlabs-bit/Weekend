package com.example.data.repository

import android.util.Log
import com.example.data.model.ChatMessage
import com.example.data.supabase.MessageInsert
import com.example.data.supabase.MessageRow
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.eq
import io.github.jan.supabase.realtime.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import java.time.OffsetDateTime
import java.util.UUID

private const val TAG = "WeekendMessageRepo"

class MessageRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    private val _chatMessages = MutableStateFlow<Map<String, List<ChatMessage>>>(emptyMap())
    val chatMessages: StateFlow<Map<String, List<ChatMessage>>> = _chatMessages.asStateFlow()

    private val _activeChannels = mutableMapOf<String, RealtimeChannel>()

    suspend fun loadMessages(matchId: String, limit: Int = 100) {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            _chatMessages.update { it + (matchId to getDemoMessages(matchId)) }
            return
        }

        try {
            val rows = pg.from("messages")
                .select(
                    Columns.raw(
                        """
                        id, sender_id, text, created_at, translated_text,
                        is_translated, is_read, target_language
                        """.trimIndent()
                    )
                ) {
                    filter { eq("conversation_id", matchId) }
                    order("created_at", Order.ASCENDING)
                    limit(limit)
                }
                .decodeList<MessageRow>()

            val messages = rows.map { mapRowToMessage(it) }
            _chatMessages.update { it + (matchId to messages) }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load messages: ${e.message}")
            // Do not fall back to fake chat content in production mode.
        }
    }

    suspend fun sendMessage(matchId: String, text: String): ChatMessage {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        val pg = SupabaseClient.postgrest

        val newMsg = ChatMessage(
            id = UUID.randomUUID().toString(),
            senderId = userId,
            text = text,
            timestamp = System.currentTimeMillis()
        )

        if (pg == null) {
            _chatMessages.update {
                it + (matchId to ((it[matchId] ?: emptyList()) + newMsg))
            }
            return newMsg
        }

        try {
            pg.from("messages").insert(
                MessageInsert(
                    conversationId = matchId,
                    senderId = userId,
                    text = text,
                    isRead = false
                )
            )

            _chatMessages.update {
                it + (matchId to ((it[matchId] ?: emptyList()) + newMsg))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to send message: ${e.message}")
            throw e
        }

        return newMsg
    }

    suspend fun translateMessage(
        matchId: String,
        messageId: String,
        targetLang: String = "English"
    ) {
        val messages = _chatMessages.value[matchId] ?: return
        val message = messages.find { it.id == messageId } ?: return

        val translated = SupabaseEdgeFunctions.getInstance()
            .translateMessage(text = message.text, targetLanguage = targetLang)

        _chatMessages.update { map ->
            val updatedList = (map[matchId] ?: emptyList()).map {
                if (it.id == messageId) {
                    it.copy(translatedText = translated, isTranslated = true)
                } else it
            }
            map + (matchId to updatedList)
        }
    }

    fun subscribeToMessages(matchId: String) {
        val realtime = SupabaseClient.realtime ?: return
        if (_activeChannels.containsKey(matchId)) return

        val channel = realtime.channel("messages:$matchId")

        val insertFlow = channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "messages"
            filter("conversation_id", FilterOperator.EQ, matchId)
        }
        insertFlow.onEach { action ->
            val row = json.decodeFromJsonElement<MessageRow>(action.record)
            appendMessage(matchId, mapRowToMessage(row))
        }.launchIn(scope)

        val updateFlow = channel.postgresChangeFlow<PostgresAction.Update>(schema = "public") {
            table = "messages"
            filter("conversation_id", FilterOperator.EQ, matchId)
        }
        updateFlow.onEach { action ->
            val row = json.decodeFromJsonElement<MessageRow>(action.record)
            val updatedMsg = mapRowToMessage(row)
            _chatMessages.update { map ->
                val updatedList = (map[matchId] ?: emptyList()).map {
                    if (it.id == updatedMsg.id) updatedMsg else it
                }
                map + (matchId to updatedList)
            }
        }.launchIn(scope)

        channel.subscribe()
        _activeChannels[matchId] = channel
    }

    fun unsubscribeFromMessages(matchId: String) {
        val channel = _activeChannels.remove(matchId) ?: return
        try {
            SupabaseClient.realtime?.removeChannel(channel)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unsubscribe from channel: ${e.message}")
        }
    }

    private fun appendMessage(matchId: String, message: ChatMessage) {
        _chatMessages.update { map ->
            val current = map[matchId] ?: emptyList()
            if (current.any { it.id == message.id }) map
            else map + (matchId to (current + message))
        }
    }

    private fun mapRowToMessage(row: MessageRow): ChatMessage {
        return ChatMessage(
            id = row.id ?: UUID.randomUUID().toString(),
            senderId = row.senderId ?: "",
            text = row.text ?: "",
            timestamp = parseTimestamp(row.createdAt),
            translatedText = row.translatedText,
            isTranslated = row.isTranslated == true,
            isRead = row.isRead == true
        )
    }

    private fun parseTimestamp(iso: String?): Long {
        if (iso.isNullOrBlank()) return System.currentTimeMillis()
        return try {
            OffsetDateTime.parse(iso).toInstant().toEpochMilli()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
    }

    private fun getDemoMessages(matchId: String): List<ChatMessage> {
        return when (matchId) {
            "match_1" -> listOf(
                ChatMessage(
                    id = "msg_1",
                    senderId = "user_1",
                    text = "Hey! That sunset photo looks amazing 🌅",
                    timestamp = System.currentTimeMillis() - 1000 * 60 * 25,
                    isRead = true
                ),
                ChatMessage(
                    id = "msg_2",
                    senderId = "user_me",
                    text = "Thanks! It was from my weekend trip. Do you like hiking too?",
                    timestamp = System.currentTimeMillis() - 1000 * 60 * 20,
                    isRead = true
                )
            )
            else -> emptyList()
        }
    }
}
