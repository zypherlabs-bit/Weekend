package com.example.data.repository

import android.util.Log
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan
import com.example.data.supabase.PlanInsert
import com.example.data.supabase.PlanParticipantInsert
import com.example.data.supabase.PlanParticipantRow
import com.example.data.supabase.PlanRow
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.isIn
import io.github.jan.supabase.postgrest.query.filter.eq
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID

private const val TAG = "WeekendPlanRepo"

class PlanRepository {

    private val _plans = MutableStateFlow<List<WeekendPlan>>(emptyList())
    val plans: StateFlow<List<WeekendPlan>> = _plans.asStateFlow()

    suspend fun fetchPlans(userId: String): List<WeekendPlan> {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            val demoPlans = com.example.data.mock.SampleData.samplePlans
            _plans.value = demoPlans
            return demoPlans
        }

        return try {
            val planRows = pg.from("plans")
                .select(
                    Columns.raw(
                        """
                        id, creator_id, title, category, venue, time, description,
                        privacy_level, created_at, updated_at
                        """.trimIndent()
                    )
                ) {
                    order("created_at", Order.DESCENDING)
                }
                .decodeList<PlanRow>()

            val participantRows = pg.from("plan_participants")
                .select(Columns.list("plan_id, user_id"))
                .decodeList<PlanParticipantRow>()

            val participantMap = participantRows
                .groupBy { it.planId ?: "" }
                .mapValues { (_, list) -> list.mapNotNull { it.userId } }

            val creatorMap = fetchPlanCreators(planRows.mapNotNull { it.creatorId })

            val planList = planRows.map { row ->
                mapRowToPlan(
                    row = row,
                    creator = creatorMap[row.creatorId ?: ""],
                    participants = participantMap[row.id ?: ""] ?: emptyList()
                )
            }

            _plans.value = planList
            planList
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch plans: ${e.message}")
            emptyList()
        }
    }

    private suspend fun fetchPlanCreators(creatorIds: List<String>): Map<String, UserProfile> {
        val pg = SupabaseClient.postgrest ?: return emptyMap()
        if (creatorIds.isEmpty()) return emptyMap()
        return try {
            val rows = pg.from("profiles")
                .select(Columns.list("id, display_name")) {
                    filter { isIn("id", creatorIds) }
                }
                .decodeList<CreatorRow>()
            rows.associate {
                it.id to UserProfile(
                    id = it.id,
                    name = it.displayName ?: "Weekend User",
                    age = 25,
                    gender = "Unknown",
                    photos = emptyList(),
                    city = "",
                    distanceKm = 0,
                    bio = "",
                    occupation = "",
                    education = "",
                    relationshipIntent = "Dating",
                    interests = emptyList(),
                    favoritePlaces = emptyList(),
                    languages = emptyList(),
                    prompts = emptyList()
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch plan creators: ${e.message}")
            emptyMap()
        }
    }

    suspend fun createPlan(
        userId: String,
        title: String,
        category: String,
        venue: String,
        time: String,
        description: String
    ): WeekendPlan? {
        val pg = SupabaseClient.postgrest ?: return null

        return try {
            val planId = UUID.randomUUID().toString()

            val creatorName = fetchPlanCreators(listOf(userId))[userId]?.name ?: "Weekend User"

            pg.from("plans").insert(
                PlanInsert(
                    id = planId,
                    creatorId = userId,
                    title = title,
                    category = category,
                    venue = venue,
                    time = time,
                    description = description,
                    privacyLevel = "public"
                )
            )

            pg.from("plan_participants").insert(
                PlanParticipantInsert(planId = planId, userId = userId)
            )

            val newPlan = WeekendPlan(
                id = "plan_$planId",
                creatorId = userId,
                creatorName = creatorName,
                creatorPhoto = "",
                title = title,
                category = category,
                venue = venue,
                time = time,
                description = description,
                participants = listOf(creatorName),
                isJoined = true
            )

            _plans.update { listOf(newPlan) + it }
            newPlan
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create plan: ${e.message}")
            null
        }
    }

    suspend fun togglePlanJoin(userId: String, planId: String, userName: String) {
        val pg = SupabaseClient.postgrest ?: return

        val currentPlan = _plans.value.find { it.id == planId } ?: return

        try {
            if (currentPlan.isJoined) {
                pg.from("plan_participants").delete {
                    filter {
                        eq("plan_id", planId)
                        eq("user_id", userId)
                    }
                }
            } else {
                pg.from("plan_participants").insert(
                    PlanParticipantInsert(planId = planId, userId = userId)
                )
            }

            _plans.update { list ->
                list.map {
                    if (it.id == planId) {
                        val joined = !it.isJoined
                        val newParticipants = if (joined) {
                            it.participants + userName
                        } else {
                            it.participants.filter { name -> name != userName }
                        }
                        it.copy(isJoined = joined, participants = newParticipants)
                    } else it
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to toggle plan join: ${e.message}")
        }
    }

    private fun mapRowToPlan(
        row: PlanRow,
        creator: UserProfile?,
        participants: List<String>
    ): WeekendPlan {
        return WeekendPlan(
            id = "plan_${row.id ?: ""}",
            creatorId = row.creatorId ?: "",
            creatorName = creator?.name ?: "Weekend User",
            creatorPhoto = creator?.photos?.firstOrNull() ?: "",
            title = row.title ?: "",
            category = row.category ?: "Coffee",
            venue = row.venue ?: "",
            time = row.time ?: "",
            description = row.description ?: "",
            participants = participants,
            isJoined = true
        )
    }
}

@kotlinx.serialization.Serializable
private data class CreatorRow(
    val id: String,
    @kotlinx.serialization.SerialName("display_name") val displayName: String? = null
)
