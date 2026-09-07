package com.weekend.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class User(
    val id: String,
    val email: String? = null,
    val name: String? = null
)

@Serializable
data class UserProfile(
    val id: String,
    val name: String,
    val age: Int,
    val gender: String,
    val photos: List<String>,
    val city: String,
    val distanceKm: Double? = null,
    val bio: String? = null,
    val occupation: String? = null,
    val education: String? = null,
    val relationshipIntent: RelationshipIntent? = null,
    val interests: List<String> = emptyList(),
    val favoritePlaces: List<String> = emptyList(),
    val languages: List<String> = emptyList(),
    val prompts: List<ProfilePrompt> = emptyList(),
    val isPhotoVerified: Boolean = false,
    val trustScore: Int = 0,
    val crossedPathsCount: Int = 0,
    val favoriteMusic: String? = null,
    val idealWeekend: String? = null,
    val referralCode: String? = null,
    val openingQuestion: String? = null,
    val weekendStatus: String? = null,
    val voiceIntroText: String? = null,
    val voiceDurationSec: Int? = null,
    val crossedPathLocation: String? = null,
    val riskLevel: Int? = null,
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val isActive: Boolean = true,
    val isBlocked: Boolean = false
)

@Serializable
data class ProfilePrompt(
    val prompt: String,
    val answer: String
)

@Serializable
data class CrossedPathEvent(
    val id: String,
    val user: UserProfile? = null,
    val areaDescription: String,
    val frequencyText: String,
    val mutualPlace: String? = null,
    val timeWindowText: String,
    val timestamp: String
)

@Serializable
data class WeekendPlan(
    val id: String,
    val creatorId: String,
    val creatorName: String,
    val creatorPhoto: String,
    val title: String,
    val category: String,
    val venue: String? = null,
    val time: String? = null,
    val description: String? = null,
    val participants: List<String> = emptyList(),
    val isJoined: Boolean = false,
    val createdAt: String
)

@Serializable
data class MatchItem(
    val id: String,
    val user: UserProfile,
    val matchedAt: String,
    val lastMessage: String? = null,
    val lastMessageTime: String? = null,
    val unreadCount: Int = 0,
    val sharedInterests: List<String> = emptyList(),
    val suggestedStarter: String? = null,
    val status: MatchStatus,
    val expiresAt: String? = null
)

@Serializable
data class ChatMessage(
    val id: String,
    val senderId: String,
    val receiverId: String,
    val matchId: String,
    val text: String,
    val timestamp: String,
    val translatedText: String? = null,
    val isTranslated: Boolean = false,
    val isRead: Boolean = false,
    val messageState: MessageState
)

@Serializable
data class ReferralData(
    val code: String,
    val invitedCount: Int,
    val verifiedCount: Int,
    val badgeTitle: String? = null,
    val achievementTier: String? = null,
    val linkUrl: String
)

@Serializable
data class DateIdea(
    val id: String,
    val title: String,
    val venueType: String,
    val description: String,
    val estimatedBudget: Double? = null,
    val conversationTip: String? = null,
    val matchId: String
)

@Serializable
data class DiscoveryFilters(
    val discoveryMode: DiscoveryMode? = null,
    val maxDistanceKm: Int? = null,
    val minAge: Int? = null,
    val maxAge: Int? = null,
    val genders: List<String>? = null,
    val relationshipIntent: RelationshipIntent? = null
)

@Serializable
enum class DiscoveryMode {
    FOR_YOU,
    NEARBY,
    CROSSED_PATHS,
    INTERESTS,
    WEEKEND_PLANS,
    GLOBAL
}

@Serializable
enum class MessageState {
    SENDING,
    SENT,
    DELIVERED,
    READ,
    FAILED,
    DELETED
}

@Serializable
enum class MatchStatus {
    ACTIVE,
    EXPIRED,
    EXTENDED,
    UNMATCHED
}

@Serializable
enum class UserStatus {
    ACTIVE,
    PAUSED,
    BANNED,
    DELETED
}

@Serializable
enum class RelationshipIntent {
    LONG_TERM,
    CASUAL,
    FRIENDSHIP,
    EXPLORING
}

@Serializable
enum class ReportReason {
    FAKE_PROFILE,
    HARASSMENT,
    HATE_SPEECH,
    SEXUAL_HARASSMENT,
    SCAM_FRAUD,
    THREATS,
    UNDERAGE_USER,
    SPAM,
    INAPPROPRIATE_CONTENT,
    OTHER
}

@Serializable
enum class SubscriptionStatus {
    ACTIVE,
    CANCELLED,
    EXPIRED,
    GRACE_PERIOD,
    PAUSED,
    REFUNDED
}

@Serializable
enum class SubscriptionTier {
    FREE,
    PREMIUM_MONTHLY,
    PREMIUM_QUARTERLY,
    PREMIUM_ANNUAL
}

enum class ThemeMode {
    LIGHT,
    DARK,
    SYSTEM
}