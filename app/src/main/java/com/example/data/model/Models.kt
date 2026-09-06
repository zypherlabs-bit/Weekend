package com.example.data.model

data class ProfilePrompt(
    val prompt: String,
    val answer: String
)

data class UserProfile(
    val id: String,
    val name: String,
    val age: Int,
    val gender: String,
    val photos: List<String>,
    val city: String,
    val distanceKm: Int,
    val bio: String,
    val occupation: String,
    val education: String,
    val relationshipIntent: String,
    val interests: List<String>,
    val favoritePlaces: List<String>,
    val languages: List<String>,
    val prompts: List<ProfilePrompt>,
    val isPhotoVerified: Boolean = true,
    val trustScore: Int = 96,
    val crossedPathsCount: Int = 0,
    val favoriteMusic: String = "",
    val idealWeekend: String = "",
    val referralCode: String = ""
)

data class WeekendPlan(
    val id: String,
    val creatorId: String,
    val creatorName: String,
    val creatorPhoto: String,
    val title: String,
    val category: String, // Coffee, Hiking, Dinner, Concert, Movies, Travel, Sports, Art
    val venue: String,
    val time: String,
    val description: String,
    val participants: List<String> = emptyList(),
    val isJoined: Boolean = false
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

data class ChatMessage(
    val id: String,
    val senderId: String,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val translatedText: String? = null,
    val isTranslated: Boolean = false,
    val isRead: Boolean = true
)

data class ReferralData(
    val code: String,
    val invitedCount: Int = 7,
    val verifiedCount: Int = 5,
    val badgeTitle: String = "Founding Pioneer",
    val achievementTier: String = "Silver Ambassador",
    val linkUrl: String = "https://weekend.app/invite/"
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
