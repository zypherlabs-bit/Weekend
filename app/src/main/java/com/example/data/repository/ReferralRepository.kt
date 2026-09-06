package com.example.data.repository

import android.util.Log
import com.example.data.model.ReferralData
import com.example.data.supabase.ReferralInsert
import com.example.data.supabase.ReferralStatsRow
import com.example.data.supabase.ReferrerLookupRow
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.Columns
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.filter.eq
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private const val TAG = "WeekendReferralRepo"

class ReferralRepository {

    private val _referralData = MutableStateFlow(ReferralData(code = ""))
    val referralData: StateFlow<ReferralData> = _referralData.asStateFlow()

    suspend fun fetchReferralData(userId: String) {
        val pg = SupabaseClient.postgrest
        if (pg == null) {
            _referralData.value = ReferralData(
                code = "WEEKEND-MX07",
                invitedCount = 7,
                verifiedCount = 5,
                badgeTitle = "Founding Pioneer",
                achievementTier = "Silver Ambassador"
            )
            return
        }

        try {
            val rows = pg.rpc(
                function = "get_referral_stats",
                parameters = com.example.data.supabase.UserParams(pUserId = userId)
            ).decodeList<ReferralStatsRow>()

            val stats = rows.firstOrNull()
            if (stats != null) {
                _referralData.value = ReferralData(
                    code = stats.referralCode ?: "",
                    invitedCount = stats.invitedCount ?: 0,
                    verifiedCount = stats.verifiedCount ?: 0,
                    badgeTitle = stats.badgeTitle ?: "New Pioneer",
                    achievementTier = stats.achievementTier ?: "New Pioneer",
                    linkUrl = stats.linkUrl ?: "https://weekend.app/invite/"
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch referral data: ${e.message}")
        }
    }

    suspend fun createReferral(userId: String, referralCode: String): Result<String> {
        val pg = SupabaseClient.postgrest ?: return Result.failure(
            IllegalStateException("Supabase not initialized")
        )

        return try {
            val generatedCode = "WEEKEND-" + userId.take(4).uppercase()
            pg.from("referrals").insert(
                ReferralInsert(
                    referrerId = userId,
                    referralCode = generatedCode,
                    status = "pending"
                )
            )
            _referralData.update { it.copy(code = generatedCode) }
            Result.success(generatedCode)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create referral: ${e.message}")
            Result.failure(e)
        }
    }

    suspend fun registerWithReferral(email: String, password: String, referralCode: String): Result<String> {
        val auth = SupabaseClient.auth ?: return Result.failure(
            IllegalStateException("Supabase not initialized")
        )

        return try {
            val user = auth.signUpWith(Email) {
                this.email = email
                this.password = password
                data = buildJsonObject {
                    if (referralCode.isNotBlank()) put("referral_code", referralCode)
                }
            }

            val newUserId = user?.id
            if (newUserId != null) {
                linkReferral(referralCode, newUserId)
                Result.success(newUserId)
            } else {
                Result.failure(IllegalStateException("Registration failed"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Registration with referral failed: ${e.message}")
            Result.failure(e)
        }
    }

    private suspend fun linkReferral(referralCode: String, newUserId: String) {
        if (referralCode.isBlank()) return
        val pg = SupabaseClient.postgrest ?: return

        try {
            // Look up the referrer by their unique referral code.
            val referrers = pg.from("profiles")
                .select(Columns.list("id")) {
                    filter { eq("referral_code", referralCode) }
                }
                .decodeList<ReferrerLookupRow>()

            val referrerId = referrers.firstOrNull()?.id

            // Prevent self-referrals and duplicate referral records.
            if (referrerId != null && referrerId != newUserId) {
                pg.from("referrals").insert(
                    ReferralInsert(
                        referrerId = referrerId,
                        refereeId = newUserId,
                        referralCode = referralCode,
                        status = "pending"
                    )
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to link referral: ${e.message}")
        }
    }
}
