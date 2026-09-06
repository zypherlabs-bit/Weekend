package com.example.data.supabase

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Serializable DTOs used by the Supabase Kotlin SDK to encode/decode rows.
 * Field names map 1:1 to the public PostgreSQL columns defined in
 * supabase/migrations. Domain models in data.model stay UI-focused and are
 * mapped from these DTOs inside the repositories.
 */

@Serializable
data class ProfileRow(
    val id: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("date_of_birth") val dateOfBirth: String? = null,
    val gender: String? = null,
    val bio: String? = null,
    val city: String? = null,
    val locality: String? = null,
    val country: String? = null,
    @SerialName("relationship_intent") val relationshipIntent: String? = null,
    @SerialName("verification_status") val verificationStatus: String? = null,
    @SerialName("trust_score") val trustScore: Int? = null,
    @SerialName("profile_completion") val profileCompletion: Int? = null,
    @SerialName("last_active_at") val lastActiveAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class ProfileUpsert(
    val id: String,
    @SerialName("display_name") val displayName: String? = null,
    val gender: String? = null,
    val bio: String? = null,
    val city: String? = null,
    @SerialName("relationship_intent") val relationshipIntent: String? = null
)

@Serializable
data class ProfilePhotoRow(
    val id: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("photo_url") val photoUrl: String? = null,
    @SerialName("is_primary") val isPrimary: Boolean? = null,
    @SerialName("moderation_status") val moderationStatus: String? = null
)

@Serializable
data class ProfilePhotoInsert(
    @SerialName("user_id") val userId: String,
    @SerialName("photo_url") val photoUrl: String,
    @SerialName("is_primary") val isPrimary: Boolean,
    @SerialName("width") val width: Int,
    @SerialName("height") val height: Int,
    @SerialName("file_size_bytes") val fileSizeBytes: Long,
    @SerialName("mime_type") val mimeType: String,
    @SerialName("moderation_status") val moderationStatus: String = "pending"
)

@Serializable
data class DiscoveryProfileRow(
    @SerialName("profile_id") val profileId: String? = null,
    val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    val age: Int? = null,
    val gender: String? = null,
    val bio: String? = null,
    val city: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("is_photo_verified") val isPhotoVerified: Boolean? = null,
    @SerialName("trust_score") val trustScore: Int? = null,
    @SerialName("primary_photo_url") val primaryPhotoUrl: String? = null,
    val interests: List<String>? = null,
    @SerialName("relationship_intent") val relationshipIntent: String? = null,
    @SerialName("crossed_paths_count") val crossedPathsCount: Int? = null,
    @SerialName("similarity_score") val similarityScore: Double? = null
)

@Serializable
data class DiscoveryParams(
    @SerialName("p_user_id") val pUserId: String,
    @SerialName("p_limit") val pLimit: Int,
    @SerialName("p_offset") val pOffset: Int,
    @SerialName("p_max_distance_km") val pMaxDistanceKm: Double,
    @SerialName("p_preferred_genders") val pPreferredGenders: List<String> = emptyList(),
    @SerialName("p_age_min") val pAgeMin: Int = 18,
    @SerialName("p_age_max") val pAgeMax: Int = 65,
    @SerialName("p_discovery_mode") val pDiscoveryMode: String = "nearby"
)

@Serializable
data class MatchRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("other_user_id") val otherUserId: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    val age: Int? = null,
    val gender: String? = null,
    val bio: String? = null,
    val city: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("is_photo_verified") val isPhotoVerified: Boolean? = null,
    @SerialName("trust_score") val trustScore: Int? = null,
    @SerialName("primary_photo_url") val primaryPhotoUrl: String? = null,
    val interests: List<String>? = null,
    @SerialName("relationship_intent") val relationshipIntent: String? = null,
    @SerialName("matched_at") val matchedAt: String? = null,
    @SerialName("last_message_text") val lastMessageText: String? = null,
    @SerialName("last_message_time") val lastMessageTime: String? = null,
    @SerialName("last_message_sender") val lastMessageSender: String? = null,
    @SerialName("unread_count") val unreadCount: Int? = null,
    @SerialName("shared_interests") val sharedInterests: List<String>? = null
)

@Serializable
data class MatchParams(
    @SerialName("p_user_id") val pUserId: String,
    @SerialName("p_limit") val pLimit: Int = 50,
    @SerialName("p_offset") val pOffset: Int = 0
)

@Serializable
data class UserParams(
    @SerialName("p_user_id") val pUserId: String
)

@Serializable
data class LikeInsert(
    @SerialName("liker_id") val likerId: String,
    @SerialName("liked_id") val likedId: String,
    @SerialName("is_stand_out") val isStandOut: Boolean = false
)

@Serializable
data class PassInsert(
    @SerialName("user_id") val userId: String,
    @SerialName("target_id") val targetId: String
)

@Serializable
data class BlockInsert(
    @SerialName("blocker_id") val blockerId: String,
    @SerialName("blocked_id") val blockedId: String
)

@Serializable
data class ReportInsert(
    @SerialName("reporter_id") val reporterId: String,
    @SerialName("reported_id") val reportedId: String,
    @SerialName("report_type") val reportType: String,
    val description: String? = null
)

@Serializable
data class MessageRow(
    val id: String? = null,
    @SerialName("conversation_id") val conversationId: String? = null,
    @SerialName("sender_id") val senderId: String? = null,
    val text: String? = null,
    @SerialName("translated_text") val translatedText: String? = null,
    @SerialName("target_language") val targetLanguage: String? = null,
    @SerialName("is_translated") val isTranslated: Boolean? = null,
    @SerialName("is_read") val isRead: Boolean? = null,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
data class MessageInsert(
    @SerialName("conversation_id") val conversationId: String,
    @SerialName("sender_id") val senderId: String,
    val text: String,
    @SerialName("is_read") val isRead: Boolean = false
)

@Serializable
data class PlanRow(
    val id: String? = null,
    @SerialName("creator_id") val creatorId: String? = null,
    val title: String? = null,
    val category: String? = null,
    val venue: String? = null,
    val time: String? = null,
    val description: String? = null,
    @SerialName("privacy_level") val privacyLevel: String? = null,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
data class PlanInsert(
    val id: String,
    @SerialName("creator_id") val creatorId: String,
    val title: String,
    val category: String,
    val venue: String,
    val time: String,
    val description: String,
    @SerialName("privacy_level") val privacyLevel: String = "public"
)

@Serializable
data class PlanParticipantRow(
    @SerialName("plan_id") val planId: String? = null,
    @SerialName("user_id") val userId: String? = null
)

@Serializable
data class PlanParticipantInsert(
    @SerialName("plan_id") val planId: String,
    @SerialName("user_id") val userId: String
)

@Serializable
data class ProfileNameRow(
    val id: String,
    @SerialName("display_name") val displayName: String? = null
)

@Serializable
data class NotificationRow(
    val id: String? = null,
    val type: String? = null,
    val title: String? = null,
    val body: String? = null,
    val data: Map<String, kotlinx.serialization.json.JsonElement>? = null,
    @SerialName("is_read") val isRead: Boolean? = null,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
data class ReferralStatsRow(
    @SerialName("referral_code") val referralCode: String? = null,
    @SerialName("invited_count") val invitedCount: Int? = null,
    @SerialName("verified_count") val verifiedCount: Int? = null,
    @SerialName("badge_title") val badgeTitle: String? = null,
    @SerialName("achievement_tier") val achievementTier: String? = null,
    @SerialName("link_url") val linkUrl: String? = null
)

@Serializable
data class ReferralInsert(
    @SerialName("referrer_id") val referrerId: String,
    @SerialName("referee_id") val refereeId: String? = null,
    @SerialName("referral_code") val referralCode: String,
    val status: String = "pending"
)

@Serializable
data class ReferrerLookupRow(
    val id: String
)

@Serializable
data class SetUserInterestsParams(
    @SerialName("p_user_id") val pUserId: String,
    @SerialName("p_interests") val pInterests: List<String>
)
