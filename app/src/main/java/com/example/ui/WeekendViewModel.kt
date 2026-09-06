package com.example.ui

import android.app.Application
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.model.ChatMessage
import com.example.data.model.DateIdea
import com.example.data.model.DiscoveryMode
import com.example.data.model.MatchItem
import com.example.data.model.ReferralData
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan
import com.example.data.repository.AuthState
import com.example.data.repository.NotificationRepository
import com.example.data.repository.WeekendRepository
import com.example.data.supabase.SupabaseClient
import com.example.data.supabase.SupabaseEdgeFunctions
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.UUID

class WeekendViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = WeekendRepository(application.applicationContext)

    val currentUser: StateFlow<UserProfile> = repository.currentUser
    val deckProfiles: StateFlow<List<UserProfile>> = repository.deckProfiles
    val matches: StateFlow<List<MatchItem>> = repository.matches
    val chatMessages: StateFlow<Map<String, List<ChatMessage>>> = repository.chatMessages
    val plans: StateFlow<List<WeekendPlan>> = repository.plans
    val referralData: StateFlow<ReferralData> = repository.referralData
    val recentMatchCelebration: StateFlow<UserProfile?> = repository.recentMatchCelebration
    val selectedMode: StateFlow<DiscoveryMode> = repository.selectedMode
    val maxDistanceKm: StateFlow<Int> = repository.maxDistanceKm
    val likedProfiles: StateFlow<List<String>> = repository.likedProfiles
    val blockedUserIds: StateFlow<Set<String>> = repository.blockedUserIds
    val notifications: StateFlow<List<NotificationRepository.NotificationItem>> = repository.notifications

    private val _activeChatMatch = MutableStateFlow<MatchItem?>(null)
    val activeChatMatch: StateFlow<MatchItem?> = _activeChatMatch.asStateFlow()

    val showPhotoVerificationDialog: StateFlow<Boolean> = repository.showPhotoVerificationDialog
    val showSafetyCenterDialog: StateFlow<Boolean> = repository.showSafetyCenterDialog
    val showShareDateDialog: StateFlow<Boolean> = repository.showShareDateDialog
    val showDatePlannerDialog: StateFlow<Boolean> = repository.showDatePlannerDialog
    val showCreatePlanDialog: StateFlow<Boolean> = repository.showCreatePlanDialog
    val isGeneratingDateIdeas: StateFlow<Boolean> = repository.isGeneratingDateIdeas
    val dateIdeas: StateFlow<List<DateIdea>> = repository.dateIdeas

    private val _authState = MutableStateFlow(
        AuthState(
            isAuthenticated = SupabaseClient.isReady(),
            isLoading = false
        )
    )
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    val isAuthenticated: StateFlow<Boolean> = authState.map { it.isAuthenticated }
        .stateIn(viewModelScope, SharingStarted.Eagerly, true)
    val isAuthLoading: StateFlow<Boolean> = authState.map { it.isLoading }
        .stateIn(viewModelScope, SharingStarted.Eagerly, false)
    val authError: StateFlow<String?> = authState.map { it.error }
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    init {
        viewModelScope.launch {
            initSupabase()
            loadInitialData()
        }
    }

    private suspend fun initSupabase() {
        SupabaseClient.init(getApplication())
        _authState.value = AuthState(
            isAuthenticated = SupabaseClient.isReady(),
            isLoading = false
        )
    }

    private suspend fun loadInitialData() {
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        repository.loadUserProfile(userId)
        repository.refreshDiscovery(userId)
        repository.loadMatches(userId)
        repository.loadPlans(userId)
        repository.loadReferralData(userId)
        repository.loadNotifications(userId)
    }

    fun selectDiscoveryMode(mode: DiscoveryMode) {
        repository.setDiscoveryMode(mode)
    }

    fun updateMaxDistance(km: Int) {
        repository.setMaxDistance(km)
        val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
        viewModelScope.launch {
            repository.refreshDiscovery(userId)
        }
    }

    fun swipeRight(profile: UserProfile, isStandOut: Boolean = false) {
        viewModelScope.launch {
            repository.swipeRight(profile, isStandOut)
        }
    }

    fun swipeLeft(profileId: String) {
        repository.swipeLeft(profileId)
    }

    fun dismissCelebration() {
        repository.clearCelebration()
    }

    fun openChat(match: MatchItem) {
        _activeChatMatch.value = match
    }

    fun closeChat() {
        _activeChatMatch.value = null
    }

    fun sendChatMessage(matchId: String, text: String) {
        if (text.isBlank()) return
        viewModelScope.launch {
            repository.sendMessage(matchId, text.trim())
        }
    }

    fun translateChatMessage(matchId: String, messageId: String) {
        viewModelScope.launch {
            repository.translateMessage(matchId, messageId)
        }
    }

    fun generateDateIdeasForActiveMatch() {
        val match = _activeChatMatch.value ?: return
        viewModelScope.launch {
            val ideas = repository.planDateIdeas(
                userInterests = currentUser.value.interests,
                partnerInterests = match.user.interests,
                city = currentUser.value.city
            )
            repository.setDateIdeas(ideas)
            repository.setShowDatePlannerDialog(true)
        }
    }

    fun dismissDatePlanner() {
        repository.dismissDatePlanner()
    }

    fun toggleJoinPlan(planId: String) {
        repository.togglePlanJoin(planId)
    }

    fun openCreatePlanDialog() {
        repository.setShowCreatePlanDialog(true)
    }

    fun dismissCreatePlanDialog() {
        repository.setShowCreatePlanDialog(false)
    }

    fun createPlan(
        title: String,
        category: String,
        venue: String,
        time: String,
        description: String
    ) {
        if (title.isBlank()) return
        val user = currentUser.value
        val newPlan = WeekendPlan(
            id = "plan_${UUID.randomUUID()}",
            creatorId = user.id,
            creatorName = user.name,
            creatorPhoto = user.photos.firstOrNull() ?: "",
            title = title.trim(),
            category = category,
            venue = venue.trim(),
            time = time.trim(),
            description = description.trim(),
            participants = listOf(user.name),
            isJoined = true
        )
        repository.createPlan(newPlan)
        Toast.makeText(getApplication(), "Weekend Plan published!", Toast.LENGTH_SHORT).show()
    }

    fun openPhotoVerification() {
        repository.setShowPhotoVerificationDialog(true)
    }

    fun dismissPhotoVerification() {
        repository.setShowPhotoVerificationDialog(false)
    }

    fun completePhotoVerification(trustScore: Int = 98) {
        viewModelScope.launch {
            repository.verifyUserPhoto(trustScore)
        }
        Toast.makeText(getApplication(), "Photo verified! Trust score: $trustScore%", Toast.LENGTH_LONG).show()
    }

    fun openSafetyCenter() {
        repository.setShowSafetyCenterDialog(true)
    }

    fun dismissSafetyCenter() {
        repository.setShowSafetyCenterDialog(false)
    }

    fun openShareDate() {
        repository.setShowShareDateDialog(true)
    }

    fun dismissShareDate() {
        repository.setShowShareDateDialog(false)
    }

    fun shareDateDetails(context: Context, matchName: String, venue: String, dateTime: String) {
        val shareText = """
            Weekend Safety Alert: Share My Date
            I'm going on a meetup with $matchName!
            📍 Venue: $venue
            ⏰ Date & Time: $dateTime
            Shared safely via Weekend App.
        """.trimIndent()
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "My Weekend Meetup Details")
            putExtra(Intent.EXTRA_TEXT, shareText)
        }
        val chooser = Intent.createChooser(intent, "Share date with trusted contact")
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    }

    fun shareReferralInvite(context: Context) {
        val code = referralData.value.code
        val text = """
            Hey! Join me on Weekend - the modern app to meet people nearby and make real weekend plans.
            It's 100% free with no paywalls or subscriptions!
            Use my invite code: $code
            Download: https://weekend.app/invite/$code
        """.trimIndent()
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "Join Weekend")
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(intent, "Share invite via")
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    }

    fun blockUser(userId: String) {
        repository.blockUser(userId)
        _activeChatMatch.value = null
        Toast.makeText(getApplication(), "User blocked and removed.", Toast.LENGTH_SHORT).show()
    }

    fun reportUser(userId: String, reason: String) {
        repository.reportUser(userId, reason)
        _activeChatMatch.value = null
        Toast.makeText(getApplication(), "Report submitted. Thank you for keeping Weekend safe.", Toast.LENGTH_SHORT).show()
    }

    fun resetDeck() {
        repository.resetDeck()
    }

    fun signInWithGoogleSimulation(email: String = "max.mac007@gmail.com") {
        viewModelScope.launch {
            _authState.value = AuthState(
                isAuthenticated = true,
                isLoading = true,
                error = null
            )
            repository.signInWithGoogleSimulation(email)
            _authState.value = AuthState(
                isAuthenticated = true,
                isLoading = false,
                error = null
            )
            val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
            loadInitialData()
            Toast.makeText(getApplication(), "Signed in as $email", Toast.LENGTH_SHORT).show()
        }
    }

    fun signInWithEmail(email: String, pass: String) {
        viewModelScope.launch {
            val result = repository.signInWithEmail(email, pass)
            if (result.isSuccess) {
                val userId = SupabaseClient.getCurrentUserId() ?: "user_me"
                loadInitialData()
            }
            Toast.makeText(getApplication(), "Signed in successfully!", Toast.LENGTH_SHORT).show()
        }
    }

    fun signOut() {
        viewModelScope.launch {
            repository.signOut()
            _authState.value = AuthState(
                isAuthenticated = false,
                isLoading = false,
                error = null
            )
            Toast.makeText(getApplication(), "Signed out", Toast.LENGTH_SHORT).show()
        }
    }

    fun deleteAccount() {
        viewModelScope.launch {
            val userId = SupabaseClient.getCurrentUserId()
            if (userId != null) {
                val result = repository.deleteAccount("user_request")
                if (result.isSuccess) {
                    _authState.value = AuthState(
                        isAuthenticated = false,
                        isLoading = false,
                        error = null
                    )
                    Toast.makeText(getApplication(), "Account deleted permanently", Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(
                        getApplication(),
                        "Failed to delete account: ${result.exceptionOrNull()?.message}",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }
}
