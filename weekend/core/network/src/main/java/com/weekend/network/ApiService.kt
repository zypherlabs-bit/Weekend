package com.weekend.network

interface ApiService {
    suspend fun requestOtp(phone: String): Result<Unit>
    suspend fun verifyOtp(phone: String, otp: String): Result<Unit>
    suspend fun signInWithEmail(email: String, password: String): Result<Unit>
    suspend fun getProfile(): Result<Unit>
    suspend fun updateProfile(): Result<Unit>
    suspend fun getDiscoveryProfiles(): Result<Unit>
    suspend fun likeProfile(profileId: String): Result<Boolean>
    suspend fun passProfile(profileId: String): Result<Unit>
    suspend fun getMatches(): Result<Unit>
    suspend fun sendMessage(matchId: String, text: String): Result<Unit>
    suspend fun blockUser(userId: String): Result<Unit>
    suspend fun reportUser(userId: String, reason: String): Result<Unit>
    suspend fun getSubscriptionStatus(): Result<Unit>
}

interface WebSocketService {
    suspend fun connect()
    suspend fun disconnect()
    suspend fun sendMessage(message: ChatMessageDto)
    fun observeMessages(): kotlinx.coroutines.flow.Flow<ChatMessageDto>
    fun observeTyping(): kotlinx.coroutines.flow.Flow<String>
    fun observePresence(): kotlinx.coroutines.flow.Flow<String>
}

data class ChatMessageDto(
    val id: String,
    val matchId: String,
    val senderId: String,
    val text: String,
    val timestamp: Long
)
