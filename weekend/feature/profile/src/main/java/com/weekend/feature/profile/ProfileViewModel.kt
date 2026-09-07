package com.weekend.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.UserProfile
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.domain.usecase.UpdateProfileUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ProfileViewModel(
    private val updateProfileUseCase: UpdateProfileUseCase,
    private val blockUserUseCase: BlockUserUseCase,
    private val reportUserUseCase: ReportUserUseCase
) : ViewModel() {
    private val _currentUser = MutableStateFlow<UserProfile>(
        UserProfile(
            id = "user_me",
            name = "Max",
            age = 26,
            gender = "Man",
            photos = listOf("https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=800&q=80"),
            city = "Pune",
            distanceKm = 0,
            bio = "Tech builder, specialty coffee addict, and spontaneous weekend trekker.",
            occupation = "Software Developer",
            education = "University Graduate",
            relationshipIntent = "Dating & Weekend Plans",
            interests = listOf("Specialty Coffee", "Hiking", "Indie Music", "Cycling", "Travel", "F1"),
            favoritePlaces = listOf("Blue Tokai Cafe", "Koregaon Park", "ARAI Hills"),
            languages = listOf("English", "Hindi"),
            prompts = emptyList(),
            isPhotoVerified = true,
            trustScore = 98,
            crossedPathsCount = 7,
            favoriteMusic = "Coldplay, Prateek Kuhad, Tame Impala",
            idealWeekend = "Acoustic gigs & hill climbs",
            referralCode = "WEEKEND-MX07",
            openingQuestion = "What's your perfect Sunday?",
            weekendStatus = "Free for coffee",
            voiceIntroText = null,
            voiceDurationSec = 14,
            crossedPathLocation = "Koregaon Park & Blue Tokai Cafe",
            riskLevel = "Low Risk · Verified"
        )
    )
    val currentUser: StateFlow<UserProfile> = _currentUser.asStateFlow()

    private val _maxDistanceKm = MutableStateFlow(25)
    val maxDistanceKm: StateFlow<Int> = _maxDistanceKm.asStateFlow()

    fun updateProfile(updated: UserProfile) {
        viewModelScope.launch {
            updateProfileUseCase(updated)
            _currentUser.value = updated
        }
    }

    fun updateMaxDistance(km: Int) {
        _maxDistanceKm.value = km
    }

    fun blockUser(userId: String) {
        viewModelScope.launch {
            blockUserUseCase(userId)
        }
    }

    fun reportUser(userId: String, reason: String) {
        viewModelScope.launch {
            reportUserUseCase(userId, reason, "")
        }
    }
}
