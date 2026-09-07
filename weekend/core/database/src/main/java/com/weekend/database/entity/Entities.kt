package com.weekend.database.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
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
    val prompts: List<String>,
    val isPhotoVerified: Boolean,
    val trustScore: Int,
    val crossedPathsCount: Int,
    val favoriteMusic: String,
    val idealWeekend: String,
    val referralCode: String,
    val openingQuestion: String,
    val weekendStatus: String,
    val voiceIntroText: String?,
    val voiceDurationSec: Int,
    val crossedPathLocation: String,
    val riskLevel: String,
    val createdAt: Long,
    val updatedAt: Long,
    val isActive: Boolean,
    val isBlocked: Boolean
)

@Entity(tableName = "matches")
data class MatchEntity(
    @PrimaryKey val id: String,
    val userId: String,
    val userName: String,
    val userPhoto: String,
    val matchedAt: Long,
    val lastMessage: String,
    val lastMessageTime: String,
    val unreadCount: Int,
    val sharedInterests: List<String>,
    val suggestedStarter: String,
    val status: String,
    val expiresAt: Long?
)

@Entity(tableName = "messages")
data class MessageEntity(
    @PrimaryKey val id: String,
    val matchId: String,
    val senderId: String,
    val receiverId: String,
    val text: String,
    val timestamp: Long,
    val translatedText: String?,
    val isTranslated: Boolean,
    val isRead: Boolean,
    val messageState: String
)

@Entity(tableName = "plans")
data class PlanEntity(
    @PrimaryKey val id: String,
    val creatorId: String,
    val creatorName: String,
    val creatorPhoto: String,
    val title: String,
    val category: String,
    val venue: String,
    val time: String,
    val description: String,
    val participants: List<String>,
    val isJoined: Boolean,
    val createdAt: Long
)

@Entity(tableName = "blocked_users")
data class BlockedUserEntity(
    @PrimaryKey val userId: String,
    val blockedAt: Long,
    val reason: String?
)
