package com.weekend.feature.matches

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.MatchItem
import com.weekend.domain.repository.MatchRepository
import com.weekend.domain.usecase.GetMatchesUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MatchesViewModel(
    private val getMatchesUseCase: GetMatchesUseCase
) : ViewModel() {
    private val _matches = MutableStateFlow<List<MatchItem>>(emptyList())
    val matches: StateFlow<List<MatchItem>> = _matches.asStateFlow()

    init {
        viewModelScope.launch {
            getMatchesUseCase().collect { matchList ->
                _matches.value = matchList
            }
        }
    }
}
