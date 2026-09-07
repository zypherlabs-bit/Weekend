package com.weekend.data.remote

import com.weekend.core.common.Constants
import com.weekend.data.mapper.EntityMapper
import com.weekend.data.network.ApiService
import com.weekend.domain.model.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRemoteDataSource @Inject constructor(private val apiService: ApiService) {
    suspend fun getCurrentUser(): User = throw NotImplementedError()
    suspend fun signInWithEmail(email: String, password: String): User = throw NotImplementedError()
    suspend fun signInWithPhone(phone: String, otp: String): User = throw NotImplementedError()
    suspend fun signInWithGoogle(idToken: String): User = throw NotImplementedError()
    suspend fun signOut() = throw NotImplementedError()
    suspend fun deleteAccount() = throw NotImplementedError()
}

@Singleton
class ProfileRemoteDataSource @Inject constructor(private val apiService: ApiService) {
    suspend fun getProfile(userId: String): UserProfile = throw NotImplementedError()
    suspend fun updateProfile(profile: UserProfile): UserProfile = throw NotImplementedError()
    suspend fun uploadPhoto(uri: android.net.Uri): String = throw NotImplementedError()
    suspend fun deletePhoto(photoId: String) = throw NotImplementedError()
    suspend fun verifyPhoto(): Int = throw NotImplementedError()
    suspend fun createPlan(plan: WeekendPlan): WeekendPlan = throw NotImplementedError()
    suspend fun joinPlan(planId: String): WeekendPlan = throw NotImplementedError()
    suspend fun leavePlan(planId: String): WeekendPlan = throw NotImplementedError()
    suspend fun blockUser(userId: String) = throw NotImplementedError()
    suspend fun unblockUser(userId: String) = throw NotImplementedError()
    suspend fun reportUser(userId: String, reason: String, details: String) = throw NotImplementedError()
    suspend fun shareDateDetails(details: String) = throw NotImplementedError()
    suspend fun clearUserData() = throw NotImplementedError()
}

@Singleton
class DiscoveryRemoteDataSource @Inject constructor(private val apiService: ApiService) {
    fun getDiscoveryProfiles(filters: DiscoveryFilters): Flow<List<UserProfile>> = flow { emptyList() }
    suspend fun likeProfile(profileId: String, isSuperLike: Boolean): Boolean = throw NotImplementedError()
    suspend fun passProfile(profileId: String) = throw NotImplementedError()
    suspend fun rewindLastSwipe(): UserProfile? = throw NotImplementedError()
    fun getRecommendedProfiles(): Flow<List<UserProfile>> = flow { emptyList() }
    fun getCrossedPaths(): Flow<List<CrossedPathEvent>> = flow { emptyList() }
    suspend fun enableEncounterDiscovery() = throw NotImplementedError()
    suspend fun disableEncounterDiscovery() = throw NotImplementedError()
}

@Singleton
class ChatRemoteDataSource @Inject constructor(private val apiService: ApiService) {
    suspend fun sendMessage(matchId: String, text: String): com.weekend.data.entity.MessageEntity =
        throw NotImplementedError()
    suspend fun markAsRead(matchId: String, messageId: String) = throw NotImplementedError()
    suspend fun deleteMessage(matchId: String, messageId: String) = throw NotImplementedError()
    suspend fun translateMessage(matchId: String, messageId: String, targetLang: String): String =
        throw NotImplementedError()
}

@Singleton
class SubscriptionRemoteDataSource @Inject constructor(private val apiService: ApiService) {
    fun getSubscriptionStatus(): Flow<SubscriptionStatus?> = flow { null }
    suspend fun purchaseSubscription(tier: SubscriptionTier): SubscriptionStatus = throw NotImplementedError()
    suspend fun cancelSubscription() = throw NotImplementedError()
    suspend fun restorePurchases(): List<SubscriptionStatus> = emptyList()
}
