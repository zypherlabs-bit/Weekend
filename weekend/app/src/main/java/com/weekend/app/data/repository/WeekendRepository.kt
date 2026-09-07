package com.weekend.app.data.repository

import android.content.Context
import android.util.Log
import com.weekend.app.data.model.BlockRecord
import com.weekend.app.data.model.ChatMessage
import com.weekend.app.data.model.CrossedPathEvent
import com.weekend.app.data.model.DateIdea
import com.weekend.app.data.model.DiscoveryMode
import com.weekend.app.data.model.LikeRecord
import com.weekend.app.data.model.MatchItem
import com.weekend.app.data.model.MatchRecord
import com.weekend.app.data.model.ProfilePrompt
import com.weekend.app.data.model.ReferralData
import com.weekend.app.data.model.ReportRecord
import com.weekend.app.data.model.UserProfile
import com.weekend.app.data.model.WeekendPlan
import com.weekend.app.data.remote.GeminiAiHelper
import com.weekend.app.data.remote.SupabaseClient
import com.weekend.app.ui.theme.ThemeMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

class WeekendRepository(private val context: Context? = null) {

    private val TAG = "WeekendRepository"
    private val prefs = context?.getSharedPreferences("weekend_theme_prefs", Context.MODE_PRIVATE)
    private val _themeMode = MutableStateFlow<ThemeMode>(
        prefs?.getString("theme_mode", null)?.let {
            runCatching { ThemeMode.valueOf(it) }.getOrNull()
        } ?: ThemeMode.SYSTEM
    )
    val themeMode: StateFlow<ThemeMode> = _themeMode.asStateFlow()

    fun setThemeMode(mode: ThemeMode) {
        _themeMode.value = mode
        prefs?.edit()?.putString("theme_mode", mode.name)?.apply()
    }

    // Loading states
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    // Current user profile - loaded from Supabase
    private val _currentUser = MutableStateFlow<UserProfile?>(null)
    val currentUser: StateFlow<UserProfile?> = _currentUser.asStateFlow()

    // Discovery deck - loaded from Supabase
    private val _deckProfiles = MutableStateFlow<List<UserProfile>>(emptyList())
    val deckProfiles: StateFlow<List<UserProfile>> = _deckProfiles.asStateFlow()

    // Matches - loaded from Supabase
    private val _matches = MutableStateFlow<List<MatchItem>>(emptyList())
    val matches: StateFlow<List<MatchItem>> = _matches.asStateFlow()

    // Chat messages - loaded from Supabase
    private val _chatMessages = MutableStateFlow<Map<String, List<ChatMessage>>>(emptyMap())
    val chatMessages: StateFlow<Map<String, List<ChatMessage>>> = _chatMessages.asStateFlow()

    // Weekend plans - loaded from Supabase
    private val _plans = MutableStateFlow<List<WeekendPlan>>(emptyList())
    val plans: StateFlow<List<WeekendPlan>> = _plans.asStateFlow()

    // Crossed paths - loaded from Supabase
    private val _crossedPaths = MutableStateFlow<List<CrossedPathEvent>>(emptyList())
    val crossedPaths: StateFlow<List<CrossedPathEvent>> = _crossedPaths.asStateFlow()

    // Referral data
    private val _referralData = MutableStateFlow(ReferralData(code = "WEEKEND-${UUID.randomUUID().toString().take(4).uppercase()}"))
    val referralData: StateFlow<ReferralData> = _referralData.asStateFlow()

    // Discovery mode
    private val _selectedMode = MutableStateFlow(DiscoveryMode.FOR_YOU)
    val selectedMode: StateFlow<DiscoveryMode> = _selectedMode.asStateFlow()

    // Max distance filter
    private val _maxDistanceKm = MutableStateFlow(25)
    val maxDistanceKm: StateFlow<Int> = _maxDistanceKm.asStateFlow()

    // Blocked user IDs
    private val _blockedUserIds = MutableStateFlow<Set<String>>(emptySet())
    val blockedUserIds: StateFlow<Set<String>> = _blockedUserIds.asStateFlow()

    // Recent match celebration
    private val _recentMatchCelebration = MutableStateFlow<UserProfile?>(null)
    val recentMatchCelebration: StateFlow<UserProfile?> = _recentMatchCelebration.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.Main)

    init {
        // Load data from Supabase on initialization
        loadCurrentUser()
        loadDiscoveryDeck()
        loadMatches()
        loadWeekendPlans()
    }

    // ==========================================
    // DATA LOADING FROM SUPABASE
    // ==========================================

    fun loadCurrentUser() {
        scope.launch {
            try {
                _isLoading.value = true
                val userId = SupabaseClient.getCurrentUserId()
                if (userId != null && SupabaseClient.isInitialized()) {
                    val profile = SupabaseClient.getPostgrest()["profiles"]
                        .select {
                            filter {
                                eq("id", userId)
                            }
                        }
                        .decodeSingle<UserProfile>()
                    _currentUser.value = profile
                    Log.i(TAG, "Loaded current user: ${profile.name}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load current user: ${e.message}")
                _errorMessage.value = "Failed to load profile"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun loadDiscoveryDeck() {
        scope.launch {
            try {
                _isLoading.value = true
                val userId = SupabaseClient.getCurrentUserId()
                if (SupabaseClient.isInitialized()) {
                    val profiles = SupabaseClient.getPostgrest()["profiles"]
                        .select {
                            filter {
                                if (userId != null) {
                                    neq("id", userId)
                                }
                                eq("is_discoverable", true)
                            }
                        }
                        .decodeList<UserProfile>()
                    _deckProfiles.value = profiles
                    Log.i(TAG, "Loaded ${profiles.size} discovery profiles")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load discovery deck: ${e.message}")
                _errorMessage.value = "Failed to load profiles"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun loadMatches() {
        scope.launch {
            try {
                _isLoading.value = true
                val userId = SupabaseClient.getCurrentUserId()
                if (userId != null && SupabaseClient.isInitialized()) {
                    val matchRecords = SupabaseClient.getPostgrest()["matches"]
                        .select {
                            filter {
                                or {
                                    eq("user1_id", userId)
                                    eq("user2_id", userId)
                                }
                            }
                        }
                        .decodeList<MatchRecord>()
                    
                    val matchItems = matchRecords.mapNotNull { record ->
                        val otherUserId = if (record.user1Id == userId) record.user2Id else record.user1Id
                        try {
                            val profile = SupabaseClient.getPostgrest()["profiles"]
                                .select {
                                    filter {
                                        eq("id", otherUserId)
                                    }
                                }
                                .decodeSingle<UserProfile>()
                            MatchItem(
                                id = record.id,
                                user = profile,
                                lastMessage = record.lastMessage ?: "",
                                lastMessageTime = record.lastMessageTime ?: "Just now"
                            )
                        } catch (e: Exception) {
                            null
                        }
                    }
                    _matches.value = matchItems
                    Log.i(TAG, "Loaded ${matchItems.size} matches")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load matches: ${e.message}")
                _errorMessage.value = "Failed to load matches"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun loadWeekendPlans() {
        scope.launch {
            try {
                _isLoading.value = true
                if (SupabaseClient.isInitialized()) {
                    val plans = SupabaseClient.getPostgrest()["weekend_plans"]
                        .select()
                        .decodeList<WeekendPlan>()
                    _plans.value = plans
                    Log.i(TAG, "Loaded ${plans.size} weekend plans")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load weekend plans: ${e.message}")
                _errorMessage.value = "Failed to load plans"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun clearError() {
        _errorMessage.value = null
    }

    // ==========================================
    // PROFILE OPERATIONS
    // ==========================================

    fun updateProfile(updated: UserProfile) {
        _currentUser.value = updated
        scope.launch {
            try {
                if (SupabaseClient.isInitialized()) {
                    SupabaseClient.getPostgrest()["profiles"]
                        .update(updated) {
                            filter {
                                eq("id", updated.id)
                            }
                        }
                    Log.i(TAG, "Profile updated in Supabase")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update profile: ${e.message}")
            }
        }
    }

    fun updateWeekendStatus(status: String) {
        _currentUser.value?.let { user ->
            _currentUser.value = user.copy(weekendStatus = status)
            scope.launch {
                try {
                    if (SupabaseClient.isInitialized()) {
                        SupabaseClient.getPostgrest()["profiles"]
                            .update({ set("weekend_status", status) }) {
                                filter {
                                    eq("id", user.id)
                                }
                            }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to update status: ${e.message}")
                }
            }
        }
    }

    fun updateOpeningQuestion(question: String) {
        _currentUser.value?.let { user ->
            _currentUser.value = user.copy(openingQuestion = question)
            scope.launch {
                try {
                    if (SupabaseClient.isInitialized()) {
                        SupabaseClient.getPostgrest()["profiles"]
                            .update({ set("opening_question", question) }) {
                                filter {
                                    eq("id", user.id)
                                }
                            }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to update question: ${e.message}")
                }
            }
        }
    }

    private val _likedProfiles = MutableStateFlow<List<String>>(emptyList())
    val likedProfiles: StateFlow<List<String>> = _likedProfiles.asStateFlow()

    fun setDiscoveryMode(mode: DiscoveryMode) {
        _selectedMode.value = mode
        loadDiscoveryDeck()
    }

    fun setMaxDistance(km: Int) {
        _maxDistanceKm.value = km
        loadDiscoveryDeck()
    }

    suspend fun swipeRight(profile: UserProfile, isStandOut: Boolean = false): Boolean {
        _likedProfiles.value = _likedProfiles.value + profile.id
        removeTopCard(profile.id)

        // Persist like to Supabase and check for match
        if (SupabaseClient.isInitialized()) {
            try {
                val userId = SupabaseClient.getCurrentUserId() ?: return false
                SupabaseClient.getPostgrest()["likes"]
                    .insert(
                        LikeRecord(
                            id = UUID.randomUUID().toString(),
                            likerId = userId,
                            likedId = profile.id
                        )
                    )
                Log.i(TAG, "Like recorded for ${profile.id}")

                // Check for mutual match
                val mutualLike = SupabaseClient.getPostgrest()["likes"]
                    .select {
                        filter {
                            eq("liker_id", profile.id)
                            eq("liked_id", userId)
                        }
                    }
                    .decodeList<LikeRecord>()
                    .isNotEmpty()

                if (mutualLike || isStandOut) {
                    // Create match
                    val matchId = UUID.randomUUID().toString()
                    SupabaseClient.getPostgrest()["matches"]
                        .insert(
                            MatchRecord(
                                id = matchId,
                                user1Id = userId,
                                user2Id = profile.id
                            )
                        )
                    Log.i(TAG, "Match created: $matchId")

                    // Update local state
                    val shared = profile.interests.intersect(_currentUser.value?.interests?.toSet() ?: emptySet()).toList()
                    val starter = GeminiAiHelper.generateIcebreaker(
                        userName = _currentUser.value?.name ?: "You",
                        matchName = profile.name,
                        sharedInterests = shared,
                        favoritePlace = profile.favoritePlaces.firstOrNull() ?: "cafe"
                    )
                    val newMatch = MatchItem(
                        id = matchId,
                        user = profile,
                        sharedInterests = shared,
                        suggestedStarter = starter
                    )
                    _matches.value = listOf(newMatch) + _matches.value.filter { it.user.id != profile.id }
                    _recentMatchCelebration.value = profile
                    return true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record like: ${e.message}")
            }
        }
        return false
    }

    fun swipeLeft(profileId: String) {
        removeTopCard(profileId)
    }

    private fun removeTopCard(profileId: String) {
        _deckProfiles.value = _deckProfiles.value.filter { it.id != profileId }
    }

    fun resetDeck() {
        _likedProfiles.value = emptyList()
        loadDiscoveryDeck()
    }

    fun clearCelebration() {
        _recentMatchCelebration.value = null
    }

    suspend fun sendMessage(matchId: String, text: String): ChatMessage {
        val userId = _currentUser.value?.id ?: "unknown"
        val newMsg = ChatMessage(
            id = "msg_${UUID.randomUUID()}",
            conversationId = matchId,
            senderId = userId,
            text = text,
            timestamp = System.currentTimeMillis()
        )
        val currentList = _chatMessages.value[matchId] ?: emptyList()
        val updated = currentList + newMsg
        _chatMessages.value = _chatMessages.value + (matchId to updated)

        // Update match preview
        _matches.value = _matches.value.map {
            if (it.id == matchId) it.copy(lastMessage = text, lastMessageTime = "Just now") else it
        }

        // Persist to Supabase asynchronously
        scope.launch {
            try {
                if (SupabaseClient.isInitialized()) {
                    SupabaseClient.getPostgrest()["messages"]
                        .insert(newMsg)
                    Log.i(TAG, "Message sent to Supabase")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send message: ${e.message}")
            }
        }
        return newMsg
    }

    suspend fun translateMessage(matchId: String, messageId: String, targetLang: String = "English") {
        val list = _chatMessages.value[matchId] ?: return
        val msg = list.find { it.id == messageId } ?: return
        val translated = GeminiAiHelper.translateMessage(msg.text, targetLang)
        val updatedList = list.map {
            if (it.id == messageId) it.copy(translatedText = translated, isTranslated = true) else it
        }
        _chatMessages.value = _chatMessages.value + (matchId to updatedList)
    }

    fun togglePlanJoin(planId: String) {
        val userName = _currentUser.value?.name ?: "Unknown"
        _plans.value = _plans.value.map {
            if (it.id == planId) {
                val joined = !it.isJoined
                val participants = if (joined) {
                    it.participants + userName
                } else {
                    it.participants.filter { name -> name != userName }
                }
                it.copy(isJoined = joined, participants = participants)
            } else it
        }

        // Persist to Supabase
        scope.launch {
            try {
                if (SupabaseClient.isInitialized()) {
                    val plan = _plans.value.find { it.id == planId }
                    if (plan != null) {
                        SupabaseClient.getPostgrest()["weekend_plans"]
                            .update({ set("participants", plan.participants) }) {
                                filter {
                                    eq("id", planId)
                                }
                            }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update plan: ${e.message}")
            }
        }
    }

    fun createPlan(plan: WeekendPlan) {
        _plans.value = listOf(plan) + _plans.value
        scope.launch {
            try {
                if (SupabaseClient.isInitialized()) {
                    SupabaseClient.getPostgrest()["weekend_plans"]
                        .insert(plan)
                    Log.i(TAG, "Plan created in Supabase")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create plan: ${e.message}")
            }
        }
    }

    fun blockUser(userId: String) {
        _blockedUserIds.value = _blockedUserIds.value + userId
        _deckProfiles.value = _deckProfiles.value.filter { it.id != userId }
        _matches.value = _matches.value.filter { it.user.id != userId }

        // Persist to Supabase
        scope.launch {
            try {
                if (SupabaseClient.isInitialized()) {
                    val currentUserId = SupabaseClient.getCurrentUserId() ?: return@launch
                    SupabaseClient.getPostgrest()["blocks"]
                        .insert(
                            BlockRecord(
                                id = UUID.randomUUID().toString(),
                                blockerId = currentUserId,
                                blockedId = userId
                            )
                        )
                    Log.i(TAG, "User blocked: $userId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to block user: ${e.message}")
            }
        }
    }

    fun reportUser(userId: String, reason: String) {
        blockUser(userId)

        // Persist report to Supabase
        scope.launch {
            try {
                if (SupabaseClient.isInitialized()) {
                    val currentUserId = SupabaseClient.getCurrentUserId() ?: return@launch
                    SupabaseClient.getPostgrest()["reports"]
                        .insert(
                            ReportRecord(
                                id = UUID.randomUUID().toString(),
                                reporterId = currentUserId,
                                reportedId = userId,
                                reason = reason
                            )
                        )
                    Log.i(TAG, "Report submitted for user: $userId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to submit report: ${e.message}")
            }
        }
    }

    fun verifyUserPhoto(trustScore: Int = 98) {
        _currentUser.value?.let { user ->
            _currentUser.value = user.copy(
                isPhotoVerified = true,
                trustScore = trustScore
            )
            updateProfile(_currentUser.value!!)
        }
    }
}
