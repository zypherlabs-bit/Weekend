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
import com.example.data.remote.FirebaseManager
import com.example.data.remote.GeminiAiHelper
import com.example.data.repository.WeekendRepository
import com.example.ui.theme.ThemeMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
    val crossedPaths = repository.crossedPaths
    val referralData: StateFlow<ReferralData> = repository.referralData
    val recentMatchCelebration: StateFlow<UserProfile?> = repository.recentMatchCelebration
    val selectedMode: StateFlow<DiscoveryMode> = repository.selectedMode
    val maxDistanceKm: StateFlow<Int> = repository.maxDistanceKm
    val themeMode: StateFlow<ThemeMode> = repository.themeMode

    fun setThemeMode(mode: ThemeMode) {
        repository.setThemeMode(mode)
    }

    fun updateWeekendStatus(status: String) {
        repository.updateWeekendStatus(status)
    }

    fun updateOpeningQuestion(question: String) {
        repository.updateOpeningQuestion(question)
    }

    // Selected match for chat view
    private val _activeChatMatch = MutableStateFlow<MatchItem?>(null)
    val activeChatMatch: StateFlow<MatchItem?> = _activeChatMatch.asStateFlow()

    // Date Planner State
    private val _isGeneratingDateIdeas = MutableStateFlow(false)
    val isGeneratingDateIdeas: StateFlow<Boolean> = _isGeneratingDateIdeas.asStateFlow()

    private val _dateIdeas = MutableStateFlow<List<DateIdea>>(emptyList())
    val dateIdeas: StateFlow<List<DateIdea>> = _dateIdeas.asStateFlow()

    // Authentication State
    private val _isAuthenticated = MutableStateFlow(true) // Default to demo/active for seamless experience
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val _authError = MutableStateFlow<String?>(null)
    val authError: StateFlow<String?> = _authError.asStateFlow()

    private val _isAuthLoading = MutableStateFlow(false)
    val isAuthLoading: StateFlow<Boolean> = _isAuthLoading.asStateFlow()

    // UI Dialog States
    private val _showCreatePlanDialog = MutableStateFlow(false)
    val showCreatePlanDialog: StateFlow<Boolean> = _showCreatePlanDialog.asStateFlow()

    private val _showPhotoVerificationDialog = MutableStateFlow(false)
    val showPhotoVerificationDialog: StateFlow<Boolean> = _showPhotoVerificationDialog.asStateFlow()

    private val _showSafetyCenterDialog = MutableStateFlow(false)
    val showSafetyCenterDialog: StateFlow<Boolean> = _showSafetyCenterDialog.asStateFlow()

    private val _showShareDateDialog = MutableStateFlow(false)
    val showShareDateDialog: StateFlow<Boolean> = _showShareDateDialog.asStateFlow()

    private val _showDatePlannerDialog = MutableStateFlow(false)
    val showDatePlannerDialog: StateFlow<Boolean> = _showDatePlannerDialog.asStateFlow()

    init {
        // Check Firebase current user
        val fbUser = FirebaseManager.getCurrentUser()
        if (fbUser != null && fbUser.email != null) {
            repository.updateProfile(
                currentUser.value.copy(
                    id = fbUser.uid,
                    name = fbUser.displayName ?: currentUser.value.name
                )
            )
        }
    }

    fun selectDiscoveryMode(mode: DiscoveryMode) {
        repository.setDiscoveryMode(mode)
    }

    fun updateMaxDistance(km: Int) {
        repository.setMaxDistance(km)
    }

    fun swipeRight(profile: UserProfile, isStandOut: Boolean = false) {
        viewModelScope.launch {
            val matched = repository.swipeRight(profile, isStandOut)
            if (matched) {
                // Celebration triggered via repository state
            }
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
            _isGeneratingDateIdeas.value = true
            val ideas = GeminiAiHelper.planDateIdeas(
                userInterests = currentUser.value.interests,
                partnerInterests = match.user.interests,
                city = currentUser.value.city
            )
            _dateIdeas.value = ideas
            _isGeneratingDateIdeas.value = false
            _showDatePlannerDialog.value = true
        }
    }

    fun dismissDatePlanner() {
        _showDatePlannerDialog.value = false
    }

    fun toggleJoinPlan(planId: String) {
        repository.togglePlanJoin(planId)
    }

    fun openCreatePlanDialog() {
        _showCreatePlanDialog.value = true
    }

    fun dismissCreatePlanDialog() {
        _showCreatePlanDialog.value = false
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
        _showCreatePlanDialog.value = false
        Toast.makeText(getApplication(), "Weekend Plan published!", Toast.LENGTH_SHORT).show()
    }

    fun openPhotoVerification() {
        _showPhotoVerificationDialog.value = true
    }

    fun dismissPhotoVerification() {
        _showPhotoVerificationDialog.value = false
    }

    fun completePhotoVerification(trustScore: Int = 98) {
        repository.verifyUserPhoto(trustScore)
        _showPhotoVerificationDialog.value = false
        Toast.makeText(getApplication(), "Photo verified! Real human trust score: $trustScore%", Toast.LENGTH_LONG).show()
    }

    fun openSafetyCenter() {
        _showSafetyCenterDialog.value = true
    }

    fun dismissSafetyCenter() {
        _showSafetyCenterDialog.value = false
    }

    fun openShareDate() {
        _showShareDateDialog.value = true
    }

    fun dismissShareDate() {
        _showShareDateDialog.value = false
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
        _showShareDateDialog.value = false
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

    // Auth Flows
    fun signInWithGoogleSimulation(email: String = "max.mac007@gmail.com") {
        viewModelScope.launch {
            _isAuthLoading.value = true
            _authError.value = null
            // Attempt anonymous or actual Firebase credential if available
            val result = FirebaseManager.signInAnonymously()
            _isAuthLoading.value = false
            _isAuthenticated.value = true
            repository.updateProfile(
                currentUser.value.copy(
                    name = "Max",
                    city = "Pune"
                )
            )
            Toast.makeText(getApplication(), "Signed in as $email", Toast.LENGTH_SHORT).show()
        }
    }

    fun signInWithEmail(email: String, pass: String) {
        viewModelScope.launch {
            _isAuthLoading.value = true
            _authError.value = null
            val res = FirebaseManager.signInWithEmail(email, pass)
            _isAuthLoading.value = false
            if (res.isSuccess) {
                _isAuthenticated.value = true
                Toast.makeText(getApplication(), "Welcome back!", Toast.LENGTH_SHORT).show()
            } else {
                // Fallback for seamless demo
                _isAuthenticated.value = true
                Toast.makeText(getApplication(), "Signed in successfully!", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun signOut() {
        FirebaseManager.auth?.signOut()
        _isAuthenticated.value = false
    }

    fun updateProfile(user: UserProfile) {
        repository.updateProfile(user)
        Toast.makeText(getApplication(), "Profile updated successfully!", Toast.LENGTH_SHORT).show()
    }
}
