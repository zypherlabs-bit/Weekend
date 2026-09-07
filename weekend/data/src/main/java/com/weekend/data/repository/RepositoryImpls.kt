package com.weekend.data.repository

import com.weekend.domain.common.AppException
import com.weekend.domain.common.Result
import com.weekend.domain.model.ChatMessage
import com.weekend.domain.model.UserProfile
import com.weekend.domain.model.WeekendPlan
import com.weekend.domain.model.CrossedPathEvent
import com.weekend.domain.model.MatchItem
import com.weekend.domain.model.DateIdea
import com.weekend.domain.model.DiscoveryMode
import com.weekend.domain.model.DiscoveryFilters
import com.weekend.domain.model.SubscriptionStatus
import com.weekend.domain.model.ThemeMode
import com.weekend.domain.repository.AuthRepository
import com.weekend.domain.repository.ProfileRepository
import com.weekend.domain.repository.DiscoveryRepository
import com.weekend.domain.repository.MatchRepository
import com.weekend.domain.repository.ChatRepository
import com.weekend.domain.repository.PlanRepository
import com.weekend.domain.repository.EncounterRepository
import com.weekend.domain.repository.SafetyRepository
import com.weekend.domain.repository.SubscriptionRepository
import com.weekend.domain.repository.SettingsRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.AuthRemoteDataSource
) : AuthRepository {
    override suspend fun getCurrentUser(): Result<com.weekend.domain.model.User?> {
        return try {
            val user = remote.getCurrentUser()
            Result.Success(user)
        } catch (e: Exception) {
            Result.Error(AppException.AuthException(e.message))
        }
    }

    override suspend fun signInWithEmail(email: String, password: String): Result<com.weekend.domain.model.User> {
        return try {
            val user = remote.signInWithEmail(email, password)
            Result.Success(user)
        } catch (e: Exception) {
            Result.Error(AppException.AuthException(e.message))
        }
    }

    override suspend fun signInWithPhone(phone: String, otp: String): Result<com.weekend.domain.model.User> {
        return try {
            val user = remote.signInWithPhone(phone, otp)
            Result.Success(user)
        } catch (e: Exception) {
            Result.Error(AppException.AuthException(e.message))
        }
    }

    override suspend fun signInWithGoogle(idToken: String): Result<com.weekend.domain.model.User> {
        return try {
            val user = remote.signInWithGoogle(idToken)
            Result.Success(user)
        } catch (e: Exception) {
            Result.Error(AppException.AuthException(e.message))
        }
    }

    override suspend fun signOut(): Result<Unit> {
        return try {
            remote.signOut()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.AuthException(e.message))
        }
    }

    override suspend fun deleteAccount(): Result<Unit> {
        return try {
            remote.deleteAccount()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.AuthException(e.message))
        }
    }
}

@Singleton
class ProfileRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.ProfileRemoteDataSource
) : ProfileRepository {
    override suspend fun getProfile(userId: String): Result<UserProfile> {
        return try {
            val profile = remote.getProfile(userId)
            Result.Success(profile)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override suspend fun updateProfile(profile: UserProfile): Result<UserProfile> {
        return try {
            val updated = remote.updateProfile(profile)
            Result.Success(updated)
        } catch (e: Exception) {
            Result.Error(AppException.ValidationException(e.message))
        }
    }

    override suspend fun uploadPhoto(uri: android.net.Uri): Result<String> {
        return try {
            val url = remote.uploadPhoto(uri)
            Result.Success(url)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun deletePhoto(photoId: String): Result<Unit> {
        return try {
            remote.deletePhoto(photoId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun verifyPhoto(): Result<Int> {
        return try {
            val score = remote.verifyPhoto()
            Result.Success(score)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }
}

@Singleton
class DiscoveryRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.DiscoveryRemoteDataSource
) : DiscoveryRepository {
    override fun getDiscoveryProfiles(filters: DiscoveryFilters): Flow<List<UserProfile>> {
        return remote.getDiscoveryProfiles(filters)
    }

    override suspend fun likeProfile(profileId: String, isSuperLike: Boolean): Result<Boolean> {
        return try {
            val matched = remote.likeProfile(profileId, isSuperLike)
            Result.Success(matched)
        } catch (e: Exception) {
            Result.Error(AppException.NetworkException(e.message))
        }
    }

    override suspend fun passProfile(profileId: String): Result<Unit> {
        return try {
            remote.passProfile(profileId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.NetworkException(e.message))
        }
    }

    override suspend fun rewindLastSwipe(): Result<UserProfile?> {
        return try {
            val profile = remote.rewindLastSwipe()
            Result.Success(profile)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override fun getRecommendedProfiles(): Flow<List<UserProfile>> {
        return remote.getRecommendedProfiles()
    }
}

@Singleton
class MatchRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.ChatRemoteDataSource,
    private val local: com.weekend.data.local.LocalDataSource
) : MatchRepository {
    override fun getMatches(): Flow<List<MatchItem>> {
        return local.getAllMatches()
    }

    override suspend fun getMatch(matchId: String): Result<MatchItem> {
        return try {
            val match = local.getMatchById(matchId)
            if (match != null) Result.Success(match.toDomain()) else Result.Error(AppException.NotFoundException("Match not found"))
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override suspend fun extendMatch(matchId: String): Result<MatchItem> {
        return try {
            val match = local.getMatchById(matchId)
            if (match != null) Result.Success(match.toDomain()) else Result.Error(AppException.NotFoundException("Match not found"))
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override suspend fun unmatch(matchId: String): Result<Unit> {
        return try {
            local.deleteMatch(matchId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override suspend fun deleteMatch(matchId: String): Result<Unit> {
        return try {
            local.deleteMatch(matchId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }
}

@Singleton
class ChatRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.ChatRemoteDataSource,
    private val local: com.weekend.data.local.LocalDataSource
) : ChatRepository {
    override fun getMessages(matchId: String): Flow<List<ChatMessage>> {
        return local.getMessagesForMatch(matchId)
    }

    override suspend fun sendMessage(matchId: String, text: String): Result<ChatMessage> {
        return try {
            val message = remote.sendMessage(matchId, text)
            local.insertMessage(message)
            Result.Success(message.toDomain())
        } catch (e: Exception) {
            Result.Error(AppException.NetworkException(e.message))
        }
    }

    override suspend fun markAsRead(matchId: String, messageId: String): Result<Unit> {
        return try {
            remote.markAsRead(matchId, messageId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.NetworkException(e.message))
        }
    }

    override suspend fun deleteMessage(matchId: String, messageId: String): Result<Unit> {
        return try {
            remote.deleteMessage(matchId, messageId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override suspend fun translateMessage(matchId: String, messageId: String, targetLang: String): Result<String> {
        return try {
            val translation = remote.translateMessage(matchId, messageId, targetLang)
            Result.Success(translation)
        } catch (e: Exception) {
            Result.Error(AppException.NetworkException(e.message))
        }
    }
}

@Singleton
class PlanRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.ProfileRemoteDataSource,
    private val local: com.weekend.data.local.LocalDataSource
) : PlanRepository {
    override fun getPlans(): Flow<List<WeekendPlan>> {
        return local.getAllPlans()
    }

    override suspend fun createPlan(plan: WeekendPlan): Result<WeekendPlan> {
        return try {
            val created = remote.createPlan(plan)
            local.insertPlan(created)
            Result.Success(created)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun joinPlan(planId: String): Result<WeekendPlan> {
        return try {
            val plan = remote.joinPlan(planId)
            Result.Success(plan)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }

    override suspend fun leavePlan(planId: String): Result<WeekendPlan> {
        return try {
            val plan = remote.leavePlan(planId)
            Result.Success(plan)
        } catch (e: Exception) {
            Result.Error(AppException.NotFoundException(e.message))
        }
    }
}

@Singleton
class EncounterRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.DiscoveryRemoteDataSource
) : EncounterRepository {
    override fun getCrossedPaths(): Flow<List<CrossedPathEvent>> {
        return remote.getCrossedPaths()
    }

    override suspend fun enableEncounterDiscovery(): Result<Unit> {
        return try {
            remote.enableEncounterDiscovery()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun disableEncounterDiscovery(): Result<Unit> {
        return try {
            remote.disableEncounterDiscovery()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }
}

@Singleton
class SafetyRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.ProfileRemoteDataSource,
    private val local: com.weekend.data.local.LocalDataSource
) : SafetyRepository {
    override suspend fun blockUser(userId: String): Result<Unit> {
        return try {
            remote.blockUser(userId)
            local.insertBlockedUser(
                com.weekend.data.entity.BlockedUserEntity(
                    userId = userId,
                    blockedAt = System.currentTimeMillis(),
                    reason = null
                )
            )
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun unblockUser(userId: String): Result<Unit> {
        return try {
            remote.unblockUser(userId)
            local.deleteBlockedUserById(userId)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun reportUser(userId: String, reason: String, details: String): Result<Unit> {
        return try {
            remote.reportUser(userId, reason, details)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun getBlockedUsers(): Result<List<String>> {
        return try {
            val ids = local.getBlockedUserIds()
            Result.Success(ids)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun shareDateDetails(details: String): Result<Unit> {
        return try {
            remote.shareDateDetails(details)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }
}

@Singleton
class SubscriptionRepositoryImpl @Inject constructor(
    private val remote: com.weekend.data.remote.SubscriptionRemoteDataSource
) : SubscriptionRepository {
    override fun getSubscriptionStatus(): Flow<SubscriptionStatus?> {
        return remote.getSubscriptionStatus()
    }

    override suspend fun purchaseSubscription(tier: com.weekend.domain.model.SubscriptionTier): Result<SubscriptionStatus> {
        return try {
            val status = remote.purchaseSubscription(tier)
            Result.Success(status)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun cancelSubscription(): Result<Unit> {
        return try {
            remote.cancelSubscription()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }

    override suspend fun restorePurchases(): Result<List<SubscriptionStatus>> {
        return try {
            val purchases = remote.restorePurchases()
            Result.Success(purchases)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }
}

@Singleton
class SettingsRepositoryImpl @Inject constructor(
    private val preferencesManager: com.weekend.datastore.PreferencesManager,
    private val remote: com.weekend.data.remote.ProfileRemoteDataSource
) : SettingsRepository {
    override fun getThemeMode(): Flow<ThemeMode> = preferencesManager.themeMode
    override suspend fun setThemeMode(mode: ThemeMode) = preferencesManager.setThemeMode(mode)
    override fun getMaxDistance(): Flow<Int> = preferencesManager.maxDistanceKm
    override suspend fun setMaxDistance(km: Int) = preferencesManager.setMaxDistanceKm(km)
    override fun getHideDistance(): Flow<Boolean> = preferencesManager.hideDistance
    override suspend fun setHideDistance(hide: Boolean) = preferencesManager.setHideDistance(hide)
    override fun getHideOnlineStatus(): Flow<Boolean> = preferencesManager.hideOnlineStatus
    override suspend fun setHideOnlineStatus(hide: Boolean) = preferencesManager.setHideOnlineStatus(hide)
    override fun getReadReceiptsEnabled(): Flow<Boolean> = preferencesManager.readReceiptsEnabled
    override suspend fun setReadReceiptsEnabled(enabled: Boolean) = preferencesManager.setReadReceiptsEnabled(enabled)
    override fun getNotificationsEnabled(): Flow<Boolean> = preferencesManager.notificationsEnabled
    override suspend fun setNotificationsEnabled(enabled: Boolean) = preferencesManager.setNotificationsEnabled(enabled)
    override fun getEncounterDiscoveryEnabled(): Flow<Boolean> = preferencesManager.encounterDiscoveryEnabled
    override suspend fun setEncounterDiscoveryEnabled(enabled: Boolean) = preferencesManager.setEncounterDiscoveryEnabled(enabled)
    override suspend fun clearUserData(): Result<Unit> {
        return try {
            remote.clearUserData()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.ServerException(e.message))
        }
    }
}
