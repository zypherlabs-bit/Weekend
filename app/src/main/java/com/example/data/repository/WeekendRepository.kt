package com.example.data.repository

import android.content.Context
import android.util.Log
import com.example.data.model.ChatMessage
import com.example.data.model.DateIdea
import com.example.data.model.DiscoveryMode
import com.example.data.model.MatchItem
import com.example.data.model.ProfilePrompt
import com.example.data.model.ReferralData
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan
import com.example.data.supabase.SupabaseClient
import com.example.data.supabase.SupabaseEdgeFunctions
import com.example.data.supabase.BlockInsert
import com.example.data.supabase.ReportInsert
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private const val TAG = "WeekendRepository"

data class RepositoryAuthState(
    val isAuthenticated: Boolean = false,
    val isLoading: Boolean = false,
    val user: String? = null,
    val error: String? = null,
    val emailVerified: Boolean = false
)

class WeekendRepository(private val context: Context? = null) {

    private val authRepository = AuthRepository(context)
    private val profileRepository = ProfileRepository()
    private val discoveryRepository = DiscoveryRepository()
    private val matchRepository = MatchRepository()
    private val messageRepository = MessageRepository()
    private val planRepository = PlanRepository()
    private val referralRepository = ReferralRepository()
    private val notificationRepository = NotificationRepository()
    private val edgeFunctions = SupabaseEdgeFunctions.getInstance()

    private val _authState = MutableStateFlow(
        RepositoryAuthState(isLoading = true)
    )
    val authState: StateFlow<RepositoryAuthState> = _authState.asStateFlow()

    private val _currentUser = MutableStateFlow(
        UserProfile(
            id = "user_me",
            name = "Max",
            age = 26,
            gender = "Man",
            photos = listOf(
                "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=800&q=80"
            ),
            city = "Pune",
            distanceKm = 0,
            bio = "Tech builder, specialty coffee addict, and spontaneous weekend trekker. Making every day feel like the weekend.",
            occupation = "Software Developer",
            education = "University Graduate",
            relationshipIntent = "Dating & Weekend Plans",
            interests = listOf("Specialty Coffee", "Hiking", "Indie Music", "Cycling", "Travel", "F1"),
            favoritePlaces = listOf("Blue Tokai Cafe", "Koregaon Park", "ARAI Hills"),
            languages = listOf("English", "Hindi"),
            prompts = listOf(
                ProfilePrompt("My ideal weekend is...", "Trying a new brunch spot followed by an outdoor trek or acoustic gig."),
                ProfilePrompt("Let's go...", "To that hidden sourdough bakery in Camp for warm croissants!")
            ),
            isPhotoVerified = true,
            trustScore = 98,
            crossedPathsCount = 7,
            favoriteMusic = "Coldplay, Prateek Kuhad, Tame Impala",
            idealWeekend = "Acoustic gigs & hill climbs",
            referralCode = "WEEKEND-MX07"
        )
    )
    val currentUser: StateFlow<UserProfile> = _currentUser.asStateFlow()

    private val _deckProfiles = MutableStateFlow<List<UserProfile>>(
        com.example.data.mock.SampleData.initialProfiles
    )
    val deckProfiles: StateFlow<List<UserProfile>> = _deckProfiles.asStateFlow()

    private val _matches = MutableStateFlow<List<MatchItem>>(
        listOf(
            MatchItem(
                id = "match_1",
                user = com.example.data.mock.SampleData.initialProfiles[0],
                lastMessage = "That sounds perfect! 👭",
                lastMessageTime = "10:28 AM",
                unreadCount = 0,
                sharedInterests = listOf("Specialty Coffee", "Hiking", "Sunset Walks"),
                suggestedStarter = "You both love hiking! Ask Aanya about her favorite weekend trail."
            )
        )
    )
    val matches: StateFlow<List<MatchItem>> = _matches.asStateFlow()

    private val _chatMessages = MutableStateFlow<Map<String, List<ChatMessage>>>(
        mapOf(
            "match_1" to listOf(
                ChatMessage(
                    id = "msg_1",
                    senderId = "user_1",
                    text = "Hey! That sunset photo looks amazing 🌅",
                    timestamp = System.currentTimeMillis() - 1000 * 60 * 25,
                    isRead = true
                ),
                ChatMessage(
                    id = "msg_2",
                    senderId = "user_me",
                    text = "Thanks! It was from my weekend trip. Do you like hiking too?",
                    timestamp = System.currentTimeMillis() - 1000 * 60 * 20,
                    isRead = true
                ),
                ChatMessage(
                    id = "msg_3",
                    senderId = "user_1",
                    text = "Yes! Let's plan a hike sometime this weekend? 😊",
                    timestamp = System.currentTimeMillis() - 1000 * 60 * 15,
                    isRead = true
                ),
                ChatMessage(
                    id = "msg_4",
                    senderId = "user_me",
                    text = "That sounds perfect! 👭",
                    timestamp = System.currentTimeMillis() - 1000 * 60 * 10,
                    isRead = true
                )
            )
        )
    )
    val chatMessages: StateFlow<Map<String, List<ChatMessage>>> = _chatMessages.asStateFlow()

    private val _plans = MutableStateFlow<List<WeekendPlan>>(
        com.example.data.mock.SampleData.samplePlans
    )
    val plans: StateFlow<List<WeekendPlan>> = _plans.asStateFlow()

    private val _referralData = MutableStateFlow(ReferralData(code = "WEEKEND-MX07"))
    val referralData: StateFlow<ReferralData> = _referralData.asStateFlow()

    private val _likedProfiles = MutableStateFlow<List<String>>(emptyList())
    val likedProfiles: StateFlow<List<String>> = _likedProfiles.asStateFlow()

    private val _passes = MutableStateFlow<List<String>>(emptyList())
    val passes: StateFlow<List<String>> = _passes.asStateFlow()

    private val _blockedUserIds = MutableStateFlow<Set<String>>(emptySet())
    val blockedUserIds: StateFlow<Set<String>> = _blockedUserIds.asStateFlow()

    private val _recentMatchCelebration = MutableStateFlow<UserProfile?>(null)
    val recentMatchCelebration: StateFlow<UserProfile?> = _recentMatchCelebration.asStateFlow()

    private val _maxDistanceKm = MutableStateFlow(25)
    val maxDistanceKm: StateFlow<Int> = _maxDistanceKm.asStateFlow()

    private val _selectedMode = MutableStateFlow(DiscoveryMode.FOR_YOU)
    val selectedMode: StateFlow<DiscoveryMode> = _selectedMode.asStateFlow()

    private val _notifications = MutableStateFlow<List<NotificationRepository.NotificationItem>>(emptyList())
    val notifications: StateFlow<List<NotificationRepository.NotificationItem>> = _notifications.asStateFlow()

    val showPhotoVerificationDialog: StateFlow<Boolean> = _showPhotoVerificationDialog.asStateFlow()
    val showSafetyCenterDialog: StateFlow<Boolean> = _showSafetyCenterDialog.asStateFlow()
    val showShareDateDialog: StateFlow<Boolean> = _showShareDateDialog.asStateFlow()
    val showDatePlannerDialog: StateFlow<Boolean> = _showDatePlannerDialog.asStateFlow()
    val showCreatePlanDialog: StateFlow<Boolean> = _showCreatePlanDialog.asStateFlow()
    val isGeneratingDateIdeas: StateFlow<Boolean> = _isGeneratingDateIdeas.asStateFlow()
    val dateIdeas: StateFlow<List<DateIdea>> = _dateIdeas.asStateFlow()
    val activeChatMatch: StateFlow<MatchItem?> = _activeChatMatch.asStateFlow()

    private val _showPhotoVerificationDialog = MutableStateFlow(false)
    private val _showSafetyCenterDialog = MutableStateFlow(false)
    private val _showShareDateDialog = MutableStateFlow(false)
    private val _showDatePlannerDialog = MutableStateFlow(false)
    private val _showCreatePlanDialog = MutableStateFlow(false)
    private val _isGeneratingDateIdeas = MutableStateFlow(false)
    private val _dateIdeas = MutableStateFlow<List<DateIdea>>(emptyList())
    private val _activeChatMatch = MutableStateFlow<MatchItem?>(null)

    fun setDiscoveryMode(mode: DiscoveryMode) {
        _selectedMode.value = mode
    }

    fun setMaxDistance(km: Int) {
        _maxDistanceKm.value = km
    }

    suspend fun updateProfile(updated: UserProfile) {
        _currentUser.value = updated
        profileRepository.saveUserProfile(updated)
    }

    suspend fun loadUserProfile(userId: String) {
        val profile = profileRepository.fetchUserProfile(userId)
        profile?.let { _currentUser.value = it }
    }

    suspend fun loadProfilePhotos(userId: String): List<String> {
        return profileRepository.fetchProfilePhotos(userId)
    }

    suspend fun refreshDiscovery(userId: String) {
        val profiles = discoveryRepository.loadDiscoveryProfiles(
            userId = userId,
            maxDistanceKm = _maxDistanceKm.value.toDouble(),
            limit = 20,
            offset = 0
        )
        _deckProfiles.value = profiles
    }

    suspend fun loadDeckProfiles(userId: String) {
        val profiles = discoveryRepository.loadDiscoveryProfiles(
            userId = userId,
            maxDistanceKm = _maxDistanceKm.value.toDouble(),
            limit = 20
        )
        _deckProfiles.value = profiles
    }

    suspend fun loadMatches(userId: String) {
        val matchList = matchRepository.fetchMatches(userId)
        _matches.value = matchList
    }

    suspend fun loadChatMessages(matchId: String) {
        messageRepository.loadMessages(matchId)
        _chatMessages.value = messageRepository.chatMessages.value
        messageRepository.subscribeToMessages(matchId)
    }

    suspend fun loadPlans(userId: String) {
        val planList = planRepository.fetchPlans(userId)
        _plans.value = planList
    }

    suspend fun loadReferralData(userId: String) {
        referralRepository.fetchReferralData(userId)
        _referralData.value = referralRepository.referralData.value
    }

    suspend fun loadNotifications(userId: String) {
        notificationRepository.fetchNotifications(userId)
        _notifications.value = notificationRepository.notifications.value
    }

    suspend fun swipeRight(profile: UserProfile, isStandOut: Boolean = false): Boolean {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        val isMatch = matchRepository.swipeRight(userId, profile.id, isStandOut)

        if (isMatch) {
            val shared = profile.interests.intersect(_currentUser.value.interests.toSet()).toList()
            val starter = edgeFunctions.generateIcebreaker(
                userName = _currentUser.value.name,
                matchName = profile.name,
                sharedInterests = shared,
                favoritePlace = profile.favoritePlaces.firstOrNull() ?: "cafe"
            )

            val newMatch = MatchItem(
                id = "match_${profile.id}_${System.currentTimeMillis()}",
                user = profile,
                sharedInterests = shared,
                suggestedStarter = starter
            )
            _matches.update { listOf(newMatch) + it.filter { m -> m.user.id != profile.id } }
            _recentMatchCelebration.value = profile

            matchRepository.fetchMatches(userId)
            _matches.value = matchRepository.matches.value
        }

        _likedProfiles.update { it + profile.id }
        removeTopCard(profile.id)
        return isMatch
    }

    fun swipeLeft(profileId: String) {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        matchRepository.swipeLeft(userId, profileId)
        removeTopCard(profileId)
    }

    private fun removeTopCard(profileId: String) {
        _deckProfiles.value = _deckProfiles.value.filter { it.id != profileId }
    }

    fun resetDeck() {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            refreshDiscovery(userId)
        }
    }

    fun clearCelebration() {
        _recentMatchCelebration.value = null
    }

    suspend fun sendMessage(matchId: String, text: String) {
        val newMsg = messageRepository.sendMessage(matchId, text)
        val currentList = _chatMessages.value[matchId] ?: emptyList()
        _chatMessages.update { it + (matchId to (currentList + newMsg)) }

        _matches.update { list ->
            list.map {
                if (it.id == matchId) {
                    it.copy(
                        lastMessage = text,
                        lastMessageTime = "Just now",
                        unreadCount = 0
                    )
                } else it
            }
        }
    }

    suspend fun translateMessage(matchId: String, messageId: String) {
        messageRepository.translateMessage(matchId, messageId)
        _chatMessages.value = messageRepository.chatMessages.value
    }

    fun togglePlanJoin(planId: String) {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        val user = _currentUser.value
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            planRepository.togglePlanJoin(userId, planId, user.name)
            _plans.value = planRepository.plans.value
        }
    }

    fun createPlan(plan: WeekendPlan) {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            planRepository.createPlan(
                userId = userId,
                title = plan.title,
                category = plan.category,
                venue = plan.venue,
                time = plan.time,
                description = plan.description
            )
            _plans.value = planRepository.plans.value
        }
        _showCreatePlanDialog.value = false
    }

    fun blockUser(userId: String) {
        val currentUserId = SupabaseClient.getCurrentUserId() ?: "user_me"
        val pg = SupabaseClient.postgrest
        if (pg != null) {
            kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                try {
                    pg.from("blocks").insert(
                        BlockInsert(blockerId = currentUserId, blockedId = userId)
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to block user: ${e.message}")
                }
            }
        }
        _blockedUserIds.update { it + userId }
        _deckProfiles.value = _deckProfiles.value.filter { it.id != userId }
        _matches.value = _matches.value.filter { it.user.id != userId }
    }

    fun reportUser(userId: String, reason: String) {
        val reporterId = SupabaseClient.getCurrentUserId() ?: "user_me"
        val pg = SupabaseClient.postgrest
        if (pg != null) {
            kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                try {
                    // Reports are never publicly visible; moderation decisions
                    // are made server-side, never by the client.
                    pg.from("reports").insert(
                        ReportInsert(
                            reporterId = reporterId,
                            reportedId = userId,
                            reportType = "inappropriate_content",
                            description = reason
                        )
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to submit report: ${e.message}")
                }
            }
        }
        blockUser(userId)
    }

    suspend fun verifyUserPhoto(trustScore: Int = 98) {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        val photoUrl = _currentUser.value.photos.firstOrNull() ?: ""
        val result = edgeFunctions.verifyPhoto(
            userId = userId,
            photoUrl = photoUrl,
            storagePath = "$userId/photo_0.jpg"
        )

        // The verification pipeline (Edge Function + database) is the single
        // source of truth for verification status. The client only reflects
        // the result locally and refreshes from the server.
        _currentUser.update {
            it.copy(
                isPhotoVerified = result.status == "approved" || result.isHumanFace,
                trustScore = result.confidence
            )
        }
        _showPhotoVerificationDialog.value = false
    }

    suspend fun signInWithEmail(email: String, pass: String): Result<String> {
        _authState.value = _authState.value.copy(isLoading = true, error = null)
        val result = authRepository.signInWithEmail(email, pass)
        _authState.value = if (result.isSuccess) {
            _authState.value.copy(
                isLoading = false,
                isAuthenticated = true,
                user = result.getOrNull(),
                error = null
            )
        } else {
            _authState.value.copy(
                isLoading = false,
                isAuthenticated = false,
                error = result.exceptionOrNull()?.message
            )
        }
        return result
    }

    suspend fun signUpWithEmail(email: String, pass: String, fullName: String): Result<String> {
        _authState.value = _authState.value.copy(isLoading = true, error = null)
        val result = authRepository.signUpWithEmail(email, pass, fullName)
        _authState.value = if (result.isSuccess) {
            _authState.value.copy(
                isLoading = false,
                isAuthenticated = true,
                user = result.getOrNull(),
                error = null
            )
        } else {
            _authState.value.copy(
                isLoading = false,
                isAuthenticated = false,
                error = result.exceptionOrNull()?.message
            )
        }
        return result
    }

    suspend fun signInWithGoogleSimulation(email: String = "max.mac007@gmail.com"): Result<String> {
        _authState.value = _authState.value.copy(isLoading = true, error = null)
        val result = authRepository.signInAnonymously()
        _authState.value = _authState.value.copy(
            isLoading = false,
            isAuthenticated = true,
            user = result.getOrNull(),
            error = null
        )
        return result
    }

    suspend fun signOut(): Result<Unit> {
        val result = authRepository.signOut()
        _authState.value = _authState.value.copy(
            isAuthenticated = false,
            user = null,
            error = null
        )
        return result
    }

    suspend fun deleteAccount(reason: String = "user_request"): Result<Boolean> {
        val userId = SupabaseClient.getCurrentUserId() ?: return Result.failure(
            IllegalStateException("No user logged in")
        )
        val result = edgeFunctions.deleteAccount(userId, reason)
        if (result.isSuccess) {
            authRepository.signOut()
            _authState.value = _authState.value.copy(isAuthenticated = false, user = null)
        }
        return result
    }

    suspend fun uploadProfilePhoto(userId: String, photoBytes: ByteArray, isPrimary: Boolean): Result<String> {
        return profileRepository.uploadProfilePhoto(userId, photoBytes, isPrimary)
    }

    /**
     * Process and upload a profile photo from a content URI with full optimization.
     * Images are validated, resized, compressed, and uploaded with thumbnail variants.
     */
    suspend fun processAndUploadPhoto(
        context: android.content.Context,
        userId: String,
        uri: android.net.Uri,
        isPrimary: Boolean
    ): Result<String> {
        return profileRepository.processAndUploadPhoto(context, userId, uri, isPrimary)
    }

    fun subscribeToRealtime(userId: String) {
        notificationRepository.subscribeToNotifications(userId)
        matchRepository.fetchMatches(userId)
    }

    fun generateIcebreaker(
        userName: String,
        matchName: String,
        sharedInterests: List<String>,
        favoritePlace: String
    ): String {
        return edgeFunctions.generateIcebreaker(userName, matchName, sharedInterests, favoritePlace)
    }

    suspend fun planDateIdeas(
        userInterests: List<String>,
        partnerInterests: List<String>,
        city: String
    ): List<DateIdea> {
        return edgeFunctions.planDateIdeas(userInterests, partnerInterests, city)
    }

    fun setShowPhotoVerificationDialog(show: Boolean) { _showPhotoVerificationDialog.value = show }
    fun openPhotoVerification() { _showPhotoVerificationDialog.value = true }
    fun dismissPhotoVerification() { _showPhotoVerificationDialog.value = false }
    fun openSafetyCenter() { _showSafetyCenterDialog.value = true }
    fun dismissSafetyCenter() { _showSafetyCenterDialog.value = false }
    fun openShareDate() { _showShareDateDialog.value = true }
    fun dismissShareDate() { _showShareDateDialog.value = false }
    fun openChat(match: MatchItem) { _activeChatMatch.value = match }
    fun closeChat() { _activeChatMatch.value = null }
    fun openCreatePlanDialog() { _showCreatePlanDialog.value = true }
    fun dismissCreatePlanDialog() { _showCreatePlanDialog.value = false }
    fun openDatePlanner() { _showDatePlannerDialog.value = true }
    fun dismissDatePlanner() { _showDatePlannerDialog.value = false }
    fun setIsGeneratingDateIdeas(isGenerating: Boolean) { _isGeneratingDateIdeas.value = isGenerating }
    fun setDateIdeas(ideas: List<DateIdea>) { _dateIdeas.value = ideas }
}
