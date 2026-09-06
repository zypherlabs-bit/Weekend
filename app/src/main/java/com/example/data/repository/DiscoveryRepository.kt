package com.example.data.repository

import android.util.Log
import com.example.data.model.UserProfile
import com.example.data.supabase.DiscoveryParams
import com.example.data.supabase.DiscoveryProfileRow
import com.example.data.supabase.ProfileRow
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.eq
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val TAG = "WeekendDiscoveryRepo"

class DiscoveryRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _deckProfiles = MutableStateFlow<List<UserProfile>>(emptyList())
    val deckProfiles: StateFlow<List<UserProfile>> = _deckProfiles.asStateFlow()

    private val _nearbyProfiles = MutableStateFlow<List<UserProfile>>(emptyList())
    val nearbyProfiles: StateFlow<List<UserProfile>> = _nearbyProfiles.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    suspend fun loadDiscoveryProfiles(
        userId: String,
        maxDistanceKm: Double = 50.0,
        preferredGenders: List<String> = emptyList(),
        ageMin: Int = 18,
        ageMax: Int = 65,
        limit: Int = 20,
        offset: Int = 0,
        mode: String = "nearby"
    ): List<UserProfile> {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            val demoProfiles = getDemoDiscoveryProfiles(userId)
            _deckProfiles.value = demoProfiles
            return demoProfiles
        }

        _isLoading.value = true
        return try {
            val rows = pg.rpc(
                function = "get_nearby_profiles",
                parameters = DiscoveryParams(
                    pUserId = userId,
                    pLimit = limit,
                    pOffset = offset,
                    pMaxDistanceKm = maxDistanceKm,
                    pPreferredGenders = preferredGenders,
                    pAgeMin = ageMin,
                    pAgeMax = ageMax,
                    pDiscoveryMode = mode
                )
            ).decodeList<DiscoveryProfileRow>()

            val profiles = rows.map { mapDiscoveryRowToProfile(it) }

            _deckProfiles.value = profiles
            _nearbyProfiles.value = profiles
            _isLoading.value = false
            profiles
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load discovery profiles: ${e.message}")
            _isLoading.value = false
            // Network/API failure: return what we have, never fake profiles.
            _deckProfiles.value
        }
    }

    suspend fun loadMoreProfiles(userId: String, offset: Int, limit: Int = 20) {
        loadDiscoveryProfiles(
            userId = userId,
            offset = offset,
            limit = limit
        )
    }

    suspend fun getNearbyUsers(
        userLat: Double,
        userLon: Double,
        maxDistanceKm: Double = 10.0,
        limit: Int = 50
    ): List<UserProfile> {
        val pg = SupabaseClient.postgrest ?: return emptyList()

        return try {
            val rows = pg.from("profiles")
                .select(
                    Columns.raw(
                        """
                        id, display_name, gender, city, bio, relationship_intent,
                        verification_status, trust_score, last_active_at
                        """.trimIndent()
                    )
                ) {
                    order("last_active_at", Order.DESCENDING)
                    limit(limit)
                }
                .decodeList<ProfileRow>()

            rows.map { row ->
                UserProfile(
                    id = row.id,
                    name = row.displayName ?: "Unknown",
                    age = 25,
                    gender = row.gender ?: "Prefer not to say",
                    photos = emptyList(),
                    city = row.city ?: "",
                    distanceKm = 0,
                    bio = row.bio ?: "",
                    occupation = "",
                    education = "",
                    relationshipIntent = row.relationshipIntent ?: "Dating",
                    interests = emptyList(),
                    favoritePlaces = emptyList(),
                    languages = emptyList(),
                    prompts = emptyList(),
                    isPhotoVerified = row.verificationStatus == "verified",
                    trustScore = row.trustScore ?: 50,
                    crossedPathsCount = 0,
                    referralCode = ""
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get nearby users: ${e.message}")
            emptyList()
        }
    }

    suspend fun updateLocation(userId: String, lat: Double, lon: Double, city: String) {
        val pg = SupabaseClient.postgrest ?: return
        try {
            pg.from("profiles").update(
                {
                    set("latitude", lat)
                    set("longitude", lon)
                    set("city", city)
                    set("last_active_at", java.time.OffsetDateTime.now().toString())
                }
            ) {
                filter { eq("id", userId) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update location: ${e.message}")
        }
    }

    fun resetDeck(userId: String) {
        _deckProfiles.value = emptyList()
        scope.launch {
            loadDiscoveryProfiles(userId = userId, offset = 0, limit = 20)
        }
    }

    private fun mapDiscoveryRowToProfile(row: DiscoveryProfileRow): UserProfile {
        return UserProfile(
            id = row.profileId ?: row.id ?: "",
            name = row.displayName ?: "Unknown",
            age = row.age ?: 25,
            gender = row.gender ?: "Prefer not to say",
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
            crossedPathsCount = row.crossedPathsCount ?: 0,
            referralCode = ""
        )
    }

    private fun getDemoDiscoveryProfiles(currentUserId: String): List<UserProfile> {
        return com.example.data.mock.SampleData.initialProfiles.filter { it.id != currentUserId }
    }
}
