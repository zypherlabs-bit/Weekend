package com.weekend.feature.encounters

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.CrossedPathEvent
import com.weekend.domain.usecase.GetCrossedPathsUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class EncounterViewModel(
    private val getCrossedPathsUseCase: GetCrossedPathsUseCase
) : ViewModel() {
    private val _crossedPaths = MutableStateFlow<List<CrossedPathEvent>>(emptyList())
    val crossedPaths: StateFlow<List<CrossedPathEvent>> = _crossedPaths.asStateFlow()

    init {
        viewModelScope.launch {
            getCrossedPathsUseCase().collect { paths ->
                _crossedPaths.value = paths
            }
        }
    }
}
