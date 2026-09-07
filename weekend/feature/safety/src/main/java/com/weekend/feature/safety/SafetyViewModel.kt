package com.weekend.feature.safety

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class SafetyViewModel(
    private val blockUserUseCase: BlockUserUseCase,
    private val reportUserUseCase: ReportUserUseCase
) : ViewModel() {
    private val _blockedUsers = MutableStateFlow<List<String>>(emptyList())
    val blockedUsers: StateFlow<List<String>> = _blockedUsers.asStateFlow()

    init {
        viewModelScope.launch {
            _blockedUsers.value = emptyList()
        }
    }

    fun blockUser(userId: String) {
        viewModelScope.launch {
            blockUserUseCase(userId)
            _blockedUsers.value = _blockedUsers.value + userId
        }
    }

    fun reportUser(userId: String, reason: String) {
        viewModelScope.launch {
            reportUserUseCase(userId, reason, "")
        }
    }

    fun unblockAllUsers() {
        viewModelScope.launch {
            _blockedUsers.value = emptyList()
        }
    }
}
