package com.weekend.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfilePrompt(
    val prompt: String,
    val answer: String
)

@Serializable
data class UserProfile(
    val id: String,
    val name: String,
    val age: Int,
    val gender: String,
    val photos: List<String> = emptyList(),
    val city: String = "",
    val distanceKm: Int = 0,
    val bio: String = "",
    val occupation: String = "",
    val education: String = "",
    val relationshipIntent: String = "",
    val interests: List<String> = emptyList(),
    val favoritePlaces: List<String> = emptyList(),
    val languages: List<String> = emptyList(),
    val prompts: List<ProfilePrompt> = emptyList(),
    val isPhotoVerified: Boolean = false,
    val trustScore: Int = 50,
    val crossedPathsCount: Int = 0,
    val favoriteMusic: String = "",
    val idealWeekend: String = "",
    val referralCode: String = "",
    val openingQuestion: String = "What's your perfect Sunday?",
    val weekendStatus: String = "Free for coffee ☕",
    val voiceIntroText: String? = null,
    val voiceDurationSec: Int = 0,
    val crossedPathLocation: String = "",
    val riskLevel: String = "Unverified",
    val isDiscoverable: Boolean = true,
    val createdAt: String = "",
    val updatedAt: String = ""
)

@Serializable
data class CrossedPathEvent(
    val id: String,
    val userId: String,
    val user: UserProfile,
    val areaDescription: String,
    val frequencyText: String,
    val mutualPlace: String,
    val timeWindowText: String
)

@Serializable
data class WeekendPlan(
    val id: String,
    val creatorId: String,
    val creatorName: String = "",
    val creatorPhoto: String = "",
    val title: String,
    val category: String,
    val venue: String,
    val time: String,
    val description: String,
    val participants: List<String> = emptyList(),
    val isJoined: Boolean = false,
    val createdAt: String = ""
)

data class MatchItem(
    val id: String,
    val user: UserProfile,
    val matchedAt: Long = System.currentTimeMillis(),
    val lastMessage: String = "",
    val lastMessageTime: String = "Just now",
    val unreadCount: Int = 0,
    val sharedInterests: List<String> = emptyList(),
    val suggestedStarter: String = ""
)

@Serializable
data class ChatMessage(
    val id: String,
    val conversationId: String,
    val senderId: String,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val translatedText: String? = null,
    val isTranslated: Boolean = false,
    val isRead: Boolean = false
)

data class ReferralData(
    val code: String,
    val invitedCount: Int = 0,
    val verifiedCount: Int = 0,
    val badgeTitle: String = "Newcomer",
    val achievementTier: String = "Starter",
    val linkUrl: String = "https://weekend.app/invite/"
)

@Serializable
data class MatchRecord(
    val id: String,
    val user1Id: String,
    val user2Id: String,
    val createdAt: String = "",
    val lastMessage: String? = null,
    val lastMessageTime: String? = null
)

@Serializable
data class LikeRecord(
    val id: String,
    val likerId: String,
    val likedId: String,
    val createdAt: String = "",
    val isMatch: Boolean = false
)

@Serializable
data class BlockRecord(
    val id: String,
    val blockerId: String,
    val blockedId: String,
    val createdAt: String = ""
)

@Serializable
data class ReportRecord(
    val id: String,
    val reporterId: String,
    val reportedId: String,
    val reason: String,
    val description: String = "",
    val createdAt: String = ""
)

enum class DiscoveryMode(val title: String) {
    FOR_YOU("For You"),
    NEARBY("Nearby"),
    CROSSED_PATHS("Crossed Paths"),
    INTERESTS("Interests"),
    WEEKEND_PLANS("Plans"),
    GLOBAL("Global")
}

data class DateIdea(
    val title: String,
    val venueType: String,
    val description: String,
    val estimatedBudget: String,
    val conversationTip: String
)
