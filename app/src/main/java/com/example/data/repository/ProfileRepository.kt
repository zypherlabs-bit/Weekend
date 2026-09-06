package com.example.data.repository

import android.util.Log
import com.example.data.model.UserProfile
import com.example.data.supabase.ProfilePhotoInsert
import com.example.data.supabase.ProfilePhotoRow
import com.example.data.supabase.ProfileRow
import com.example.data.supabase.ProfileUpsert
import com.example.data.supabase.SupabaseClient
import com.example.data.supabase.UserParams
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.eq
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import io.ktor.http.ContentType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.LocalDate
import java.time.Period

private const val TAG = "WeekendProfileRepo"

class ProfileRepository {

    private val _profiles = MutableStateFlow<Map<String, UserProfile>>(emptyMap())
    val profiles: StateFlow<Map<String, UserProfile>> = _profiles.asStateFlow()

    suspend fun fetchUserProfile(userId: String): UserProfile? {
        val pg = SupabaseClient.postgrest ?: return getDemoUserProfile(userId)

        return try {
            val rows = pg.from("profiles")
                .select(PROFILE_COLUMNS) { filter { eq("id", userId) } }
                .decodeList<ProfileRow>()

            rows.firstOrNull()?.let { profile ->
                val mapped = mapRowToProfile(profile)
                _profiles.update { it + (userId to mapped) }
                mapped
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch profile: ${e.message}")
            null
        }
    }

    suspend fun saveUserProfile(profile: UserProfile): Result<Boolean> {
        val pg = SupabaseClient.postgrest
            ?: return Result.success(saveDemoProfile(profile))

        return try {
            pg.from("profiles").upsert(
                ProfileUpsert(
                    id = profile.id,
                    displayName = profile.name,
                    gender = profile.gender,
                    bio = profile.bio,
                    city = profile.city,
                    relationshipIntent = profile.relationshipIntent
                )
            ) {
                onConflict = "id"
            }

            _profiles.update { it + (profile.id to profile) }
            Result.success(true)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to save profile: ${e.message}")
            Result.failure(e)
        }
    }

    suspend fun fetchProfilePhotos(userId: String): List<String> {
        val pg = SupabaseClient.postgrest
        if (pg == null) return getDemoProfilePhotos(userId)

        return try {
            val rows = pg.from("profile_photos")
                .select(Columns.list("photo_url, is_primary, moderation_status")) {
                    filter { eq("user_id", userId) }
                    order("is_primary", Order.DESCENDING)
                }
                .decodeList<ProfilePhotoRow>()

            rows
                .filter { it.moderationStatus == "approved" || it.moderationStatus == null }
                .mapNotNull { it.photoUrl }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch photos: ${e.message}")
            emptyList()
        }
    }

    suspend fun uploadProfilePhoto(userId: String, photoBytes: ByteArray, isPrimary: Boolean): Result<String> {
        val storage = SupabaseClient.storage
            ?: return Result.failure(IllegalStateException("Supabase storage not initialized"))

        return try {
            val path = "$userId/photo_${System.currentTimeMillis()}.jpg"
            val bucket = storage.from("profile-photos")

            bucket.upload(path, photoBytes) {
                upsert = true
                contentType = ContentType.Image.JPEG
            }

            val publicUrl = bucket.publicUrl(path)

            val pg = SupabaseClient.postgrest
            if (pg != null) {
                pg.from("profile_photos").insert(
                    ProfilePhotoInsert(
                        userId = userId,
                        photoUrl = publicUrl,
                        isPrimary = isPrimary,
                        width = 800,
                        height = 800,
                        fileSizeBytes = photoBytes.size.toLong(),
                        mimeType = "image/jpeg",
                        // Moderation status is decided by the trusted backend
                        // pipeline, never by the client.
                        moderationStatus = "pending"
                    )
                )
            }

            Result.success(publicUrl)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to upload photo: ${e.message}")
            Result.failure(e)
        }
    }

    suspend fun fetchUserInterests(userId: String): List<String> {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            return com.example.data.mock.SampleData.initialProfiles
                .find { it.id == userId }?.interests ?: emptyList()
        }

        return try {
            val rows = pg.rpc("get_user_interests", UserParams(pUserId = userId))
            rows.decodeList<com.example.data.supabase.ProfileNameRow>()
                .mapNotNull { it.displayName }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch interests: ${e.message}")
            emptyList()
        }
    }

    suspend fun updateUserInterests(userId: String, interests: List<String>): Result<Unit> {
        val pg = SupabaseClient.postgrest ?: return Result.failure(
            IllegalStateException("Supabase not initialized")
        )
        return try {
            // Atomic, RLS-safe: the database function enforces that users can
            // only modify their own interests.
            pg.rpc(
                function = "set_user_interests",
                parameters = SetUserInterestsParams(
                    pUserId = userId,
                    pInterests = interests
                )
            )
            Result.success(Unit)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update interests: ${e.message}")
            Result.failure(e)
        }
    }

    private fun mapRowToProfile(row: ProfileRow): UserProfile {
        return UserProfile(
            id = row.id,
            name = row.displayName ?: "Unknown",
            age = calculateAge(row.dateOfBirth),
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

    private fun calculateAge(dobString: String?): Int {
        return try {
            val dob = dobString?.let { LocalDate.parse(it.substringBefore('T')) }
            if (dob != null) Period.between(dob, LocalDate.now()).years else 25
        } catch (e: Exception) {
            25
        }
    }

    private fun getDemoUserProfile(userId: String): UserProfile? {
        return com.example.data.mock.SampleData.initialProfiles.find { it.id == userId }
    }

    private fun saveDemoProfile(profile: UserProfile): Boolean {
        _profiles.update { it + (profile.id to profile) }
        return true
    }

    private fun getDemoProfilePhotos(userId: String): List<String> {
        return com.example.data.mock.SampleData.initialProfiles
            .find { it.id == userId }
            ?.photos ?: emptyList()
    }

    companion object {
        // Never select raw latitude/longitude - location is private.
        private val PROFILE_COLUMNS = Columns.raw(
            """
            id, display_name, date_of_birth, gender, bio, city, locality,
            country, relationship_intent, verification_status, trust_score,
            profile_completion, last_active_at, created_at, updated_at
            """.trimIndent()
        )
    }
}
