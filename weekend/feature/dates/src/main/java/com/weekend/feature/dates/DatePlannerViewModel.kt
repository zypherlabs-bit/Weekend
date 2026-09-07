package com.weekend.feature.dates

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.DateIdea
import com.weekend.domain.model.WeekendPlan
import com.weekend.domain.usecase.GetPlansUseCase
import com.weekend.domain.usecase.CreatePlanUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class DatePlannerViewModel(
    private val getPlansUseCase: GetPlansUseCase,
    private val createPlanUseCase: CreatePlanUseCase
) : ViewModel() {
    private val _plans = MutableStateFlow<List<WeekendPlan>>(emptyList())
    val plans: StateFlow<List<WeekendPlan>> = _plans.asStateFlow()

    init {
        viewModelScope.launch {
            getPlansUseCase().collect { planList ->
                _plans.value = planList
            }
        }
    }

    fun generateDateIdeas() {
        viewModelScope.launch {
            val ideas = listOf(
                DateIdea(
                    id = "idea_1",
                    title = "Coffee at Blue Tokai",
                    venueType = "Cafe",
                    description = "Try their signature pour-over and sourdough croissants.",
                    estimatedBudget = "₹500",
                    conversationTip = "Ask about their favorite coffee origin."
                ),
                DateIdea(
                    id = "idea_2",
                    title = "Sunset at Koregaon Park",
                    venueType = "Outdoor",
                    description = "Walk along the tree-lined lanes and find a quiet spot.",
                    estimatedBudget = "Free",
                    conversationTip = "Share your favorite weekend memory."
                )
            )
            val plan = WeekendPlan(
                id = "plan_${System.currentTimeMillis()}",
                creatorId = "",
                creatorName = "",
                creatorPhoto = "",
                title = ideas.first().title,
                category = "Coffee",
                venue = ideas.first().venueType,
                time = "Saturday 4:00 PM",
                description = ideas.first().description,
                participants = emptyList(),
                isJoined = false,
                createdAt = System.currentTimeMillis()
            )
            createPlanUseCase(plan)
        }
    }
}
