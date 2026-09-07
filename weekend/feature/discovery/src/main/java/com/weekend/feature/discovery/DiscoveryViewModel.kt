package com.weekend.feature.discovery

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.UserProfile
import com.weekend.domain.repository.DiscoveryRepository
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.GetDiscoveryProfilesUseCase
import com.weekend.domain.usecase.LikeProfileUseCase
import com.weekend.domain.usecase.PassProfileUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class DiscoveryViewModel(
    private val repository: DiscoveryRepository,
    private val getDiscoveryProfilesUseCase: GetDiscoveryProfilesUseCase,
    private val likeProfileUseCase: LikeProfileUseCase,
    private val passProfileUseCase: PassProfileUseCase,
    private val blockUserUseCase: BlockUserUseCase,
    private val reportUserUseCase: ReportUserUseCase
) : ViewModel() {
    private val _deckProfiles = MutableStateFlow<List<UserProfile>>(emptyList())
    val deckProfiles: StateFlow<List<UserProfile>> = _deckProfiles.asStateFlow()

    init {
        viewModelScope.launch {
            getDiscoveryProfilesUseCase().collect { profiles ->
                _deckProfiles.value = profiles
            }
        }
    }

    fun swipeRight(profile: UserProfile, isStandOut: Boolean = false) {
        viewModelScope.launch {
            likeProfileUseCase(profile.id, isSuperLike = isStandOut)
            _deckProfiles.value = _deckProfiles.value.filter { it.id != profile.id }
        }
    }

    fun swipeLeft(profileId: String) {
        viewModelScope.launch {
            passProfileUseCase(profileId)
            _deckProfiles.value = _deckProfiles.value.filter { it.id != profileId }
        }
    }

    fun resetDeck() {
        viewModelScope.launch {
            _deckProfiles.value = emptyList()
        }
    }

    fun blockUser(userId: String) {
        viewModelScope.launch {
            blockUserUseCase(userId)
            _deckProfiles.value = _deckProfiles.value.filter { it.id != userId }
        }
    }

    fun reportUser(userId: String, reason: String) {
        viewModelScope.launch {
            reportUserUseCase(userId, reason, "")
        }
    }
}
