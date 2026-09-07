package com.weekend.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.ThemeMode
import com.weekend.domain.repository.SettingsRepository
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class SettingsViewModel(
    private val settingsRepository: SettingsRepository,
    private val blockUserUseCase: BlockUserUseCase,
    private val reportUserUseCase: ReportUserUseCase
) : ViewModel() {
    val themeMode: StateFlow<ThemeMode> = settingsRepository.getThemeMode()

    fun setThemeMode(mode: ThemeMode) {
        viewModelScope.launch {
            settingsRepository.setThemeMode(mode)
        }
    }

    fun signOut() {
        viewModelScope.launch {
            settingsRepository.clearUserData()
        }
    }
}
