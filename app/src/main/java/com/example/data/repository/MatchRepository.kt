package com.example.data.repository

import android.util.Log
import com.example.data.model.MatchItem
import com.example.data.model.UserProfile
import com.example.data.supabase.LikeInsert
import com.example.data.supabase.MatchParams
import com.example.data.supabase.MatchRow
import com.example.data.supabase.PassInsert
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.filter.eq
import io.github.jan.supabase.postgrest.query.filter.neq
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private const val TAG = "WeekendMatchRepo"

class MatchRepository {

    private val _matches = MutableStateFlow<List<MatchItem>>(emptyList())
    val matches: StateFlow<List<MatchItem>> = _matches.asStateFlow()

    private val _likedProfiles = MutableStateFlow<List<String>>(emptyList())
    val likedProfiles: StateFlow<List<String>> = _likedProfiles.asStateFlow()

    private val _passes = MutableStateFlow<List<String>>(emptyList())
    val passes: StateFlow<List<String>> = _passes.asStateFlow()

    suspend fun swipeRight(
        userId: String,
        profileId: String,
        isStandOut: Boolean = false
    ): Boolean {
        val pg = SupabaseClient.postgrest ?: return false

        return try {
            pg.from("likes").insert(
                LikeInsert(
                    likerId = userId,
                    likedId = profileId,
                    isStandOut = isStandOut
                )
            )

            _likedProfiles.update { (it + profileId).distinct() }

            // The mutual-like trigger in the database creates the match and
            // its conversation. Re-fetch matches to detect a new match.
            val matchList = fetchMatchesInternal(pg, userId)
            _matches.value = matchList

            matchList.any { it.user.id == profileId }
        } catch (e: Exception) {
            // RLS/constraint violations (e.g. duplicate like) land here too.
            Log.w(TAG, "Failed to like profile: ${e.message}")
            false
        }
    }

    suspend fun swipeLeft(userId: String, profileId: String) {
        val pg = SupabaseClient.postgrest ?: return
        try {
            pg.from("passes").insert(
                PassInsert(userId = userId, targetId = profileId)
            )
            _passes.update { (it + profileId).distinct() }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to pass on profile: ${e.message}")
        }
    }

    suspend fun fetchMatches(userId: String): List<MatchItem> {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            val demoMatches = listOf(
                MatchItem(
                    id = "match_1",
                    user = com.example.data.mock.SampleData.initialProfiles[0],
                    lastMessage = "That sounds perfect! 👭",
                    lastMessageTime = "10:28 AM",
                    unreadCount = 0,
                    sharedInterests = listOf("Specialty Coffee", "Hiking", "Sunset Walks"),
                    suggestedStarter = "You both love hiking! Ask about their favorite weekend trail."
                )
            )
            _matches.value = demoMatches
            return demoMatches
        }

        return try {
            val matchList = fetchMatchesInternal(pg, userId)
            _matches.value = matchList
            matchList
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch matches: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchLikedProfiles(userId: String): List<String> {
        val pg = SupabaseClient.postgrest ?: return _likedProfiles.value
        return try {
            val rows = pg.from("likes")
                .select(Columns.list("liked_id")) {
                    filter { eq("liker_id", userId) }
                }
                .decodeList<LikedRow>()
            val ids = rows.mapNotNull { it.likedId }
            _likedProfiles.value = ids
            ids
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch liked profiles: ${e.message}")
            emptyList()
        }
    }

    suspend fun markMessagesRead(userId: String, conversationId: String) {
        val pg = SupabaseClient.postgrest ?: return
        try {
            pg.from("messages").update(
                { set("is_read", true) }
            ) {
                filter {
                    eq("conversation_id", conversationId)
                    neq("sender_id", userId)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to mark messages read: ${e.message}")
        }
    }

    private suspend fun fetchMatchesInternal(
        pg: Postgrest,
        userId: String
    ): List<MatchItem> {
        return pg.rpc(
            function = "get_matches_for_user",
            parameters = MatchParams(pUserId = userId)
        ).decodeList<MatchRow>().map { mapRowToMatchItem(it) }
    }

    private fun mapRowToMatchItem(row: MatchRow): MatchItem {
        val profile = UserProfile(
            id = row.otherUserId ?: "",
            name = row.displayName ?: "Unknown",
            age = row.age ?: 25,
            gender = row.gender ?: "Unknown",
            photos = listOfNotNull(row.primaryPhotoUrl),
            city = row.city ?: "",
            distanceKm = row.distanceKm?.toInt() ?: 0,
            bio = row.bio ?: "",
            occupation = "",
            education = "",
            relationshipIntent = row.relationshipIntent ?: "Dating",
            interests = row.interests ?: emptyList(),
            favoritePlaces = emptyList(),
            languages = emptyList(),
            prompts = emptyList(),
            isPhotoVerified = row.isPhotoVerified == true,
            trustScore = row.trustScore ?: 50,
            crossedPathsCount = 0,
            referralCode = ""
        )

        val formattedTime = formatTimestamp(row.lastMessageTime)

        return MatchItem(
            id = row.matchId ?: "",
            user = profile,
            matchedAt = parseTimestamp(row.matchedAt),
            lastMessage = row.lastMessageText ?: "",
            lastMessageTime = formattedTime,
            unreadCount = row.unreadCount ?: 0,
            sharedInterests = row.sharedInterests ?: emptyList(),
            suggestedStarter = ""
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

    private fun formatTimestamp(iso: String?): String {
        if (iso.isNullOrBlank()) return "Just now"
        return try {
            val time = OffsetDateTime.parse(iso)
            time.format(DateTimeFormatter.ofPattern("h:mm a", Locale.getDefault()))
        } catch (e: Exception) {
            "Just now"
        }
    }
}

@kotlinx.serialization.Serializable
private data class LikedRow(
    @kotlinx.serialization.SerialName("liked_id") val likedId: String? = null
)
