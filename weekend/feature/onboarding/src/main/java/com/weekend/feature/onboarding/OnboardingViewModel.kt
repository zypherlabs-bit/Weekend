package com.weekend.feature.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class OnboardingViewModel : ViewModel() {
    private val _onboardingState = MutableStateFlow(false)
    val onboardingState: StateFlow<Boolean> = _onboardingState.asStateFlow()

    fun completeOnboarding(name: String, age: Int) {
        viewModelScope.launch {
            _onboardingState.value = true
        }
    }
}
