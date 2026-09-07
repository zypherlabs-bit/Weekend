package com.weekend.domain.usecase

import com.weekend.domain.model.ChatMessage
import com.weekend.domain.model.CrossedPathEvent
import com.weekend.domain.model.DiscoveryFilters
import com.weekend.domain.model.UserProfile
import com.weekend.domain.model.WeekendPlan
import com.weekend.domain.repository.ChatRepository
import com.weekend.domain.repository.DiscoveryRepository
import com.weekend.domain.repository.EncounterRepository
import com.weekend.domain.repository.MatchRepository
import com.weekend.domain.repository.PlanRepository
import com.weekend.domain.repository.ProfileRepository
import com.weekend.domain.repository.SafetyRepository

class GetDiscoveryProfilesUseCase(private val discoveryRepository: DiscoveryRepository) {
    operator fun invoke(filters: DiscoveryFilters) = discoveryRepository.getDiscoveryProfiles(filters)
}

class LikeProfileUseCase(private val discoveryRepository: DiscoveryRepository) {
    suspend operator fun invoke(profileId: String, isSuperLike: Boolean) = discoveryRepository.likeProfile(profileId, isSuperLike)
}

class PassProfileUseCase(private val discoveryRepository: DiscoveryRepository) {
    suspend operator fun invoke(profileId: String) = discoveryRepository.passProfile(profileId)
}

class GetMatchesUseCase(private val matchRepository: MatchRepository) {
    operator fun invoke() = matchRepository.getMatches()
}

class GetMessagesUseCase(private val chatRepository: ChatRepository) {
    operator fun invoke(matchId: String) = chatRepository.getMessages(matchId)
}

class BlockUserUseCase(private val safetyRepository: SafetyRepository) {
    suspend operator fun invoke(userId: String) = safetyRepository.blockUser(userId)
}

class ReportUserUseCase(private val safetyRepository: SafetyRepository) {
    suspend operator fun invoke(userId: String, reason: com.weekend.domain.model.ReportReason, details: String) = safetyRepository.reportUser(userId, reason, details)
}

class UpdateProfileUseCase(private val profileRepository: ProfileRepository) {
    suspend operator fun invoke(profile: com.weekend.domain.model.UserProfile) = profileRepository.updateProfile(profile)
}

class GetPlansUseCase(private val planRepository: PlanRepository) {
    operator fun invoke() = planRepository.getPlans()
}

class CreatePlanUseCase(private val planRepository: PlanRepository) {
    suspend operator fun invoke(plan: WeekendPlan) = planRepository.createPlan(plan)
}

class GetCrossedPathsUseCase(private val encounterRepository: EncounterRepository) {
    operator fun invoke() = encounterRepository.getCrossedPaths()
}