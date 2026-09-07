package com.example.data.repository

import android.content.Context
import com.example.data.mock.SampleData
import com.example.data.model.ChatMessage
import com.example.data.model.CrossedPathEvent
import com.example.data.model.DateIdea
import com.example.data.model.DiscoveryMode
import com.example.data.model.MatchItem
import com.example.data.model.ProfilePrompt
import com.example.data.model.ReferralData
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan
import com.example.data.remote.FirebaseManager
import com.example.data.remote.GeminiAiHelper
import com.example.data.remote.SupabaseManager
import com.example.ui.theme.ThemeMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

class WeekendRepository(private val context: Context? = null) {

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

    private val _deckProfiles = MutableStateFlow<List<UserProfile>>(SampleData.initialProfiles)
    val deckProfiles: StateFlow<List<UserProfile>> = _deckProfiles.asStateFlow()

    private val _matches = MutableStateFlow<List<MatchItem>>(
        listOf(
            MatchItem(
                id = "match_1",
                user = SampleData.initialProfiles[0], // Aanya
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

    private val _plans = MutableStateFlow<List<WeekendPlan>>(SampleData.samplePlans)
    val plans: StateFlow<List<WeekendPlan>> = _plans.asStateFlow()

    private val _crossedPaths = MutableStateFlow<List<CrossedPathEvent>>(SampleData.sampleCrossedPaths)
    val crossedPaths: StateFlow<List<CrossedPathEvent>> = _crossedPaths.asStateFlow()

    private val _referralData = MutableStateFlow(ReferralData(code = "WEEKEND-MX07"))
    val referralData: StateFlow<ReferralData> = _referralData.asStateFlow()

    private val _likedProfiles = MutableStateFlow<List<String>>(emptyList())
    val likedProfiles: StateFlow<List<String>> = _likedProfiles.asStateFlow()

    private val _blockedUserIds = MutableStateFlow<Set<String>>(emptySet())
    val blockedUserIds: StateFlow<Set<String>> = _blockedUserIds.asStateFlow()

    private val _recentMatchCelebration = MutableStateFlow<UserProfile?>(null)
    val recentMatchCelebration: StateFlow<UserProfile?> = _recentMatchCelebration.asStateFlow()

    // Preferences & Filters
    private val _maxDistanceKm = MutableStateFlow(25)
    val maxDistanceKm: StateFlow<Int> = _maxDistanceKm.asStateFlow()

    private val _selectedMode = MutableStateFlow(DiscoveryMode.FOR_YOU)
    val selectedMode: StateFlow<DiscoveryMode> = _selectedMode.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.IO)

    fun setDiscoveryMode(mode: DiscoveryMode) {
        _selectedMode.value = mode
        reorderDeck(mode, _maxDistanceKm.value)
    }

    fun setMaxDistance(km: Int) {
        _maxDistanceKm.value = km
        reorderDeck(_selectedMode.value, km)
    }

    private fun reorderDeck(mode: DiscoveryMode, maxDistance: Int) {
        val base = SampleData.initialProfiles.filter { it.id !in _blockedUserIds.value && it.id !in _likedProfiles.value }
        val filtered = base.filter { it.distanceKm <= maxDistance }
        _deckProfiles.value = when (mode) {
            DiscoveryMode.NEARBY -> filtered.sortedBy { it.distanceKm }
            DiscoveryMode.INTERESTS -> filtered.sortedByDescending { it.interests.intersect(_currentUser.value.interests.toSet()).size }
            else -> filtered
        }
    }

    fun updateWeekendStatus(status: String) {
        _currentUser.value = _currentUser.value.copy(weekendStatus = status)
        scope.launch {
            SupabaseManager.saveProfile(_currentUser.value)
        }
    }

    fun updateOpeningQuestion(question: String) {
        _currentUser.value = _currentUser.value.copy(openingQuestion = question)
        scope.launch {
            SupabaseManager.saveProfile(_currentUser.value)
        }
    }

    fun updateProfile(updated: UserProfile) {
        _currentUser.value = updated
        scope.launch {
            SupabaseManager.saveProfile(updated)
            FirebaseManager.saveUserProfile(updated)
        }
    }

    suspend fun swipeRight(profile: UserProfile, isStandOut: Boolean = false): Boolean {
        _likedProfiles.value = _likedProfiles.value + profile.id
        removeTopCard(profile.id)

        // Asynchronously persist swipe to Supabase
        scope.launch {
            SupabaseManager.recordSwipe(_currentUser.value.id, profile.id, isLike = true)
        }

        // For demo & genuine reciprocity, profiles like Ananya, Rohan, or Elena match!
        val isMutualMatch = isStandOut || profile.id == "user_1" || profile.id == "user_3" || profile.id == "user_5"
        if (isMutualMatch) {
            val shared = profile.interests.intersect(_currentUser.value.interests.toSet()).toList()
            val starter = GeminiAiHelper.generateIcebreaker(
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
            _matches.value = listOf(newMatch) + _matches.value.filter { it.user.id != profile.id }
            _recentMatchCelebration.value = profile
            return true
        }
        return false
    }

    fun swipeLeft(profileId: String) {
        removeTopCard(profileId)
        scope.launch {
            SupabaseManager.recordSwipe(_currentUser.value.id, profileId, isLike = false)
        }
    }

    private fun removeTopCard(profileId: String) {
        _deckProfiles.value = _deckProfiles.value.filter { it.id != profileId }
    }

    fun resetDeck() {
        _likedProfiles.value = emptyList()
        reorderDeck(_selectedMode.value, _maxDistanceKm.value)
    }

    fun clearCelebration() {
        _recentMatchCelebration.value = null
    }

    suspend fun sendMessage(matchId: String, text: String): ChatMessage {
        val newMsg = ChatMessage(
            id = "msg_${UUID.randomUUID()}",
            senderId = _currentUser.value.id,
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

        // Persist to Supabase and Firestore asynchronously
        scope.launch {
            SupabaseManager.sendChatMessage(matchId, newMsg)
            FirebaseManager.sendChatMessage(matchId, newMsg)

            // Simulate incoming response from matched person after brief delay
            kotlinx.coroutines.delay(1200)
            val match = _matches.value.find { it.id == matchId }
            if (match != null) {
                val replies = listOf(
                    "That sounds amazing! Are you free this Saturday afternoon? ☕",
                    "Haha completely agree! Have you been to that cafe before? 😊",
                    "I love that idea! Let's make it our weekend plan 🎉",
                    "Sounds like a plan! Looking forward to it ✨",
                    "Yes, definitely! What time works best for you?"
                )
                val replyText = replies.random()
                val replyMsg = ChatMessage(
                    id = "msg_${UUID.randomUUID()}",
                    senderId = match.user.id,
                    text = replyText,
                    timestamp = System.currentTimeMillis(),
                    isRead = true
                )
                val updatedChat = (_chatMessages.value[matchId] ?: emptyList()) + replyMsg
                _chatMessages.value = _chatMessages.value + (matchId to updatedChat)
                _matches.value = _matches.value.map {
                    if (it.id == matchId) it.copy(lastMessage = replyText, lastMessageTime = "Just now") else it
                }
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
        _plans.value = _plans.value.map {
            if (it.id == planId) {
                val joined = !it.isJoined
                val participants = if (joined) {
                    it.participants + _currentUser.value.name
                } else {
                    it.participants.filter { name -> name != _currentUser.value.name }
                }
                it.copy(isJoined = joined, participants = participants)
            } else it
        }
    }

    fun createPlan(plan: WeekendPlan) {
        _plans.value = listOf(plan) + _plans.value
        scope.launch {
            SupabaseManager.createWeekendPlan(plan)
        }
    }

    fun blockUser(userId: String) {
        _blockedUserIds.value = _blockedUserIds.value + userId
        _deckProfiles.value = _deckProfiles.value.filter { it.id != userId }
        _matches.value = _matches.value.filter { it.user.id != userId }
    }

    fun reportUser(userId: String, reason: String) {
        blockUser(userId)
    }

    fun verifyUserPhoto(trustScore: Int = 98) {
        _currentUser.value = _currentUser.value.copy(
            isPhotoVerified = true,
            trustScore = trustScore
        )
    }
}
