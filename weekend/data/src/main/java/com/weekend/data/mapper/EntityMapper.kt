package com.weekend.data.mapper

import com.weekend.data.entity.UserEntity
import com.weekend.data.entity.MatchEntity
import com.weekend.data.entity.MessageEntity
import com.weekend.data.entity.PlanEntity
import com.weekend.domain.model.*

object EntityMapper {
    fun UserEntity.toDomain(): User = User(
        id = id,
        name = name,
        email = "",
        phone = "",
        status = UserStatus.ACTIVE,
        createdAt = createdAt,
        updatedAt = updatedAt,
        lastActiveAt = updatedAt
    )

    fun MatchEntity.toDomain(): MatchItem = MatchItem(
        id = id,
        user = UserProfile(
            id = userId,
            name = userName,
            age = 0,
            gender = "",
            photos = listOf(userPhoto),
            city = "",
            distanceKm = 0,
            bio = "",
            occupation = "",
            education = "",
            relationshipIntent = "",
            interests = emptyList(),
            favoritePlaces = emptyList(),
            languages = emptyList(),
            prompts = emptyList(),
            isPhotoVerified = false,
            trustScore = 0,
            crossedPathsCount = 0,
            favoriteMusic = "",
            idealWeekend = "",
            referralCode = "",
            openingQuestion = "",
            weekendStatus = "",
            voiceIntroText = null,
            voiceDurationSec = 0,
            crossedPathLocation = "",
            riskLevel = ""
        ),
        matchedAt = matchedAt,
        lastMessage = lastMessage,
        lastMessageTime = lastMessageTime,
        unreadCount = unreadCount,
        sharedInterests = sharedInterests,
        suggestedStarter = suggestedStarter,
        status = MatchStatus.ACTIVE,
        expiresAt = expiresAt
    )

    fun MessageEntity.toDomain(): ChatMessage = ChatMessage(
        id = id,
        senderId = senderId,
        receiverId = receiverId,
        matchId = matchId,
        text = text,
        timestamp = timestamp,
        translatedText = translatedText,
        isTranslated = isTranslated,
        isRead = isRead,
        messageState = MessageState.valueOf(messageState)
    )

    fun PlanEntity.toDomain(): WeekendPlan = WeekendPlan(
        id = id,
        creatorId = creatorId,
        creatorName = creatorName,
        creatorPhoto = creatorPhoto,
        title = title,
        category = category,
        venue = venue,
        time = time,
        description = description,
        participants = participants,
        isJoined = isJoined,
        createdAt = createdAt
    )
}
