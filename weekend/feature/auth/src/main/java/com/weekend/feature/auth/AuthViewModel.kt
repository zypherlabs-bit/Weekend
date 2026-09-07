package com.weekend.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.usecase.GetDiscoveryProfilesUseCase
import com.weekend.domain.usecase.SendMessageUseCase
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.domain.usecase.LikeProfileUseCase
import com.weekend.domain.usecase.PassProfileUseCase
import com.weekend.domain.usecase.GetMatchesUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthViewModel : ViewModel() {
    private val _authState = MutableStateFlow(false)
    val authState: StateFlow<Boolean> = _authState.asStateFlow()

    fun signInWithEmail(email: String, password: String) {
        viewModelScope.launch {
            _authState.value = true
        }
    }

    fun signInWithGoogle() {
        viewModelScope.launch {
            _authState.value = true
        }
    }

    fun signInWithPhone() {
        viewModelScope.launch {
            _authState.value = true
        }
    }
}
