package com.weekend.domain.repository

import com.weekend.domain.common.Result
import com.weekend.domain.model.ThemeMode
import com.weekend.domain.model.ChatMessage
import com.weekend.domain.model.CrossedPathEvent
import com.weekend.domain.model.DateIdea
import com.weekend.domain.model.DiscoveryFilters
import com.weekend.domain.model.MatchItem
import com.weekend.domain.model.MessageState
import com.weekend.domain.model.MatchStatus
import com.weekend.domain.model.ProfilePrompt
import com.weekend.domain.model.ReferralData
import com.weekend.domain.model.ReportReason
import com.weekend.domain.model.RelationshipIntent
import com.weekend.domain.model.SubscriptionStatus
import com.weekend.domain.model.SubscriptionTier
import com.weekend.domain.model.User
import com.weekend.domain.model.UserProfile
import com.weekend.domain.model.WeekendPlan
import kotlinx.coroutines.flow.Flow

interface AuthRepository {
    suspend fun getCurrentUser(): User?
    suspend fun signInWithEmail(email: String, password: String): Result<User>
    suspend fun signInWithPhone(phone: String, otp: String): Result<User>
    suspend fun signInWithGoogle(idToken: String): Result<User>
    suspend fun signOut()
    suspend fun deleteAccount(): Result<Unit>
}

interface ProfileRepository {
    suspend fun getProfile(userId: String): Result<UserProfile>
    suspend fun updateProfile(profile: UserProfile): Result<UserProfile>
    suspend fun uploadPhoto(uri: String): Result<String>
    suspend fun deletePhoto(photoId: String): Result<Unit>
    suspend fun verifyPhoto(): Result<Int>
}

interface DiscoveryRepository {
    fun getDiscoveryProfiles(filters: DiscoveryFilters): Flow<List<UserProfile>>
    suspend fun likeProfile(profileId: String, isSuperLike: Boolean): Result<Boolean>
    suspend fun passProfile(profileId: String): Result<Unit>
    suspend fun rewindLastSwipe(): Result<UserProfile?>
    fun getRecommendedProfiles(): Flow<List<UserProfile>>
}

interface MatchRepository {
    fun getMatches(): Flow<List<MatchItem>>
    suspend fun getMatch(matchId: String): Result<MatchItem>
    suspend fun extendMatch(matchId: String): Result<MatchItem>
    suspend fun unmatch(matchId: String): Result<Unit>
    suspend fun deleteMatch(matchId: String): Result<Unit>
}

interface ChatRepository {
    fun getMessages(matchId: String): Flow<List<ChatMessage>>
    suspend fun sendMessage(matchId: String, text: String): Result<ChatMessage>
    suspend fun markAsRead(matchId: String, messageId: String): Result<Unit>
    suspend fun deleteMessage(matchId: String, messageId: String): Result<Unit>
    suspend fun translateMessage(matchId: String, messageId: String, targetLang: String): Result<String>
}

interface PlanRepository {
    fun getPlans(): Flow<List<WeekendPlan>>
    suspend fun createPlan(plan: WeekendPlan): Result<WeekendPlan>
    suspend fun joinPlan(planId: String): Result<WeekendPlan>
    suspend fun leavePlan(planId: String): Result<WeekendPlan>
}

interface EncounterRepository {
    fun getCrossedPaths(): Flow<List<CrossedPathEvent>>
    suspend fun enableEncounterDiscovery(): Result<Unit>
    suspend fun disableEncounterDiscovery(): Result<Unit>
}

interface SafetyRepository {
    suspend fun blockUser(userId: String): Result<Unit>
    suspend fun unblockUser(userId: String): Result<Unit>
    suspend fun reportUser(userId: String, reason: ReportReason, details: String): Result<Unit>
    suspend fun getBlockedUsers(): Result<List<String>>
    suspend fun shareDateDetails(details: String): Result<Unit>
}

interface SubscriptionRepository {
    fun getSubscriptionStatus(): Flow<SubscriptionStatus?>
    suspend fun purchaseSubscription(tier: SubscriptionTier): Result<SubscriptionStatus>
    suspend fun cancelSubscription(): Result<Unit>
    suspend fun restorePurchases(): Result<List<SubscriptionStatus>>
}

interface SettingsRepository {
    fun getThemeMode(): Flow<ThemeMode>
    suspend fun setThemeMode(mode: ThemeMode)
    fun getMaxDistance(): Flow<Int>
    suspend fun setMaxDistance(km: Int)
    fun getHideDistance(): Flow<Boolean>
    suspend fun setHideDistance(hide: Boolean)
    fun getHideOnlineStatus(): Flow<Boolean>
    suspend fun setHideOnlineStatus(hide: Boolean)
    fun getReadReceiptsEnabled(): Flow<Boolean>
    suspend fun setReadReceiptsEnabled(enabled: Boolean)
    fun getNotificationsEnabled(): Flow<Boolean>
    suspend fun setNotificationsEnabled(enabled: Boolean)
    fun getEncounterDiscoveryEnabled(): Flow<Boolean>
    suspend fun setEncounterDiscoveryEnabled(enabled: Boolean)
    suspend fun clearUserData(): Result<Unit>
}