package com.example.data.repository

import android.util.Log
import com.example.data.supabase.NotificationRow
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.eq
import io.github.jan.supabase.realtime.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import java.time.OffsetDateTime

private const val TAG = "WeekendNotificationRepo"

data class NotificationItem(
    val id: String,
    val title: String,
    val body: String,
    val type: String,
    val isRead: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
    val data: Map<String, String> = emptyMap()
)

class NotificationRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    private val _notifications = MutableStateFlow<List<NotificationItem>>(emptyList())
    val notifications: StateFlow<List<NotificationItem>> = _notifications.asStateFlow()

    private val _unreadCount = MutableStateFlow(0)
    val unreadCount: StateFlow<Int> = _unreadCount.asStateFlow()

    suspend fun fetchNotifications(userId: String, limit: Int = 50) {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            _notifications.value = emptyList()
            _unreadCount.value = 0
            return
        }

        try {
            val rows = pg.from("notifications")
                .select(
                    Columns.raw("id, type, title, body, data, is_read, created_at")
                ) {
                    filter { eq("user_id", userId) }
                    order("created_at", Order.DESCENDING)
                    limit(limit)
                }
                .decodeList<NotificationRow>()

            val items = rows.map { row ->
                NotificationItem(
                    id = row.id ?: "",
                    title = row.title ?: "",
                    body = row.body ?: "",
                    type = row.type ?: "",
                    isRead = row.isRead == true,
                    createdAt = parseTimestamp(row.createdAt),
                    data = row.data?.mapValues { (_, v) ->
                        when (val p = v as? kotlinx.serialization.json.JsonPrimitive) {
                            null -> ""
                            else -> p.content
                        }
                    } ?: emptyMap()
                )
            }

            _notifications.value = items
            _unreadCount.value = items.count { !it.isRead }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch notifications: ${e.message}")
            _notifications.value = emptyList()
            _unreadCount.value = 0
        }
    }

    suspend fun markAsRead(userId: String, notificationId: String) {
        val pg = SupabaseClient.postgrest ?: return
        try {
            pg.from("notifications").update(
                { set("is_read", true) }
            ) {
                filter {
                    eq("user_id", userId)
                    eq("id", notificationId)
                }
            }

            _notifications.update { list ->
                list.map { if (it.id == notificationId) it.copy(isRead = true) else it }
            }
            _unreadCount.update { maxOf(0, it - 1) }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to mark notification as read: ${e.message}")
        }
    }

    suspend fun markAllAsRead(userId: String) {
        val pg = SupabaseClient.postgrest ?: return
        try {
            pg.from("notifications").update(
                { set("is_read", true) }
            ) {
                filter { eq("user_id", userId) }
            }

            _notifications.update { list -> list.map { it.copy(isRead = true) } }
            _unreadCount.value = 0
        } catch (e: Exception) {
            Log.w(TAG, "Failed to mark notifications as read: ${e.message}")
        }
    }

    fun subscribeToNotifications(userId: String) {
        val realtime = SupabaseClient.realtime ?: return

        val channel = realtime.channel("notifications:$userId")

        val insertFlow = channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "notifications"
            filter("user_id", FilterOperator.EQ, userId)
        }
        insertFlow.onEach { action ->
            val row = json.decodeFromJsonElement<NotificationRow>(action.record)
            val item = NotificationItem(
                id = row.id ?: "",
                title = row.title ?: "",
                body = row.body ?: "",
                type = row.type ?: "",
                isRead = row.isRead == true,
                createdAt = parseTimestamp(row.createdAt)
            )
            _notifications.update { listOf(item) + it }
            _unreadCount.update { it + 1 }
        }.launchIn(scope)

        channel.subscribe()
    }

    private fun parseTimestamp(iso: String?): Long {
        if (iso.isNullOrBlank()) return System.currentTimeMillis()
        return try {
            OffsetDateTime.parse(iso).toInstant().toEpochMilli()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
    }
}
