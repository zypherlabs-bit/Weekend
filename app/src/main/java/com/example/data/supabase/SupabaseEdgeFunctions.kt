package com.example.data.supabase

import android.util.Log
import com.example.data.model.DateIdea
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.random.Random

private const val TAG = "WeekendSupabaseFunctions"

data class IcebreakerResult(val text: String, val source: String = "fallback")
data class TranslationResult(val translatedText: String, val source: String = "fallback")
data class PhotoVerificationResult(
    val status: String = "pending",
    val confidence: Int = 50,
    val isHumanFace: Boolean = false,
    val riskLevel: String = "low",
    val suspicionReasons: List<String> = emptyList(),
    val detectionSignals: Map<String, Any?> = emptyMap()
)

class SupabaseEdgeFunctions {

    suspend fun generateIcebreaker(
        userName: String,
        matchName: String,
        sharedInterests: List<String>,
        favoritePlace: String
    ): String {
        val functions = SupabaseClient.functions ?: return generateFallbackIcebreaker(matchName, sharedInterests)

        return try {
            val response = functions.invoke(
                function = "icebreaker",
                body = buildJsonObject {
                    put("userName", userName)
                    put("matchName", matchName)
                    put("sharedInterests", buildJsonArray {
                        sharedInterests.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) }
                    })
                    put("favoritePlace", favoritePlace)
                }
            )

            val text = response.bodyAsText()
            val json = Json.parseToJsonElement(text).jsonObject
            json["text"]?.jsonPrimitive?.content
                ?: generateFallbackIcebreaker(matchName, sharedInterests)
        } catch (e: Exception) {
            Log.w(TAG, "Icebreaker call failed: ${e.message}")
            generateFallbackIcebreaker(matchName, sharedInterests)
        }
    }

    suspend fun translateMessage(
        text: String,
        targetLanguage: String = "English"
    ): String {
        val functions = SupabaseClient.functions ?: return "[Translated to $targetLanguage]: $text"

        return try {
            val response = functions.invoke(
                function = "translate-message",
                body = buildJsonObject {
                    put("text", text)
                    put("targetLanguage", targetLanguage)
                }
            )

            val body = Json.parseToJsonElement(response.bodyAsText()).jsonObject
            body["translatedText"]?.jsonPrimitive?.content
                ?: "[Translated to $targetLanguage]: $text"
        } catch (e: Exception) {
            Log.w(TAG, "Translation call failed: ${e.message}")
            "[Translated to $targetLanguage]: $text"
        }
    }

    suspend fun planDateIdeas(
        userInterests: List<String>,
        partnerInterests: List<String>,
        city: String = "Pune"
    ): List<DateIdea> {
        val functions = SupabaseClient.functions ?: return com.example.data.mock.SampleData.curatedDateIdeas

        return try {
            val response = functions.invoke(
                function = "date-ideas",
                body = buildJsonObject {
                    put("userInterests", buildJsonArray {
                        userInterests.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) }
                    })
                    put("partnerInterests", buildJsonArray {
                        partnerInterests.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) }
                    })
                    put("city", city)
                }
            )

            val result = Json.parseToJsonElement(response.bodyAsText()).jsonObject
            val ideas = result["ideas"] as? JsonArray
            if (ideas != null && ideas.isNotEmpty()) {
                ideas.mapNotNull { idea ->
                    val map = idea as? JsonObject ?: return@mapNotNull null
                    DateIdea(
                        title = map["title"]?.jsonPrimitive?.content ?: "Weekend Discovery",
                        venueType = map["venueType"]?.jsonPrimitive?.content ?: "Cozy Hangout",
                        description = map["description"]?.jsonPrimitive?.content
                            ?: "A relaxed activity to get to know each other.",
                        estimatedBudget = map["estimatedBudget"]?.jsonPrimitive?.content ?: "₹₹ (Moderate)",
                        conversationTip = map["conversationTip"]?.jsonPrimitive?.content
                            ?: "Ask about their favorite weekend routine."
                    )
                }
            } else {
                com.example.data.mock.SampleData.curatedDateIdeas
            }
        } catch (e: Exception) {
            Log.w(TAG, "Date ideas call failed: ${e.message}")
            com.example.data.mock.SampleData.curatedDateIdeas
        }
    }

    suspend fun verifyPhoto(
        userId: String,
        photoUrl: String,
        storagePath: String
    ): PhotoVerificationResult {
        val functions = SupabaseClient.functions ?: return PhotoVerificationResult(status = "pending")

        return try {
            val response = functions.invoke(
                function = "photo-verification",
                body = buildJsonObject {
                    put("userId", userId)
                    put("photoUrl", photoUrl)
                    put("storagePath", storagePath)
                }
            )

            val result = Json.parseToJsonElement(response.bodyAsText()).jsonObject
            PhotoVerificationResult(
                status = result["status"]?.jsonPrimitive?.content ?: "pending",
                confidence = result["confidence"]?.jsonPrimitive?.content?.toIntOrNull() ?: 50,
                isHumanFace = result["isHumanFace"]?.jsonPrimitive?.content == "true",
                riskLevel = result["riskLevel"]?.jsonPrimitive?.content ?: "low",
                suspicionReasons = (result["suspicionReasons"] as? JsonArray)
                    ?.mapNotNull { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
                    ?: emptyList(),
                detectionSignals = (result["detectionSignals"] as? JsonObject)
                    ?.mapValues { (_, v) ->
                        (v as? kotlinx.serialization.json.JsonPrimitive)?.content
                    }
                    ?: emptyMap()
            )
        } catch (e: Exception) {
            Log.w(TAG, "Photo verification call failed: ${e.message}")
            PhotoVerificationResult(
                status = "pending",
                confidence = 50,
                suspicionReasons = listOf("Error: ${e.message}")
            )
        }
    }

    suspend fun deleteAccount(
        userId: String,
        reason: String = "user_request"
    ): Result<Boolean> {
        val functions = SupabaseClient.functions ?: return Result.failure(
            IllegalStateException("Supabase functions not initialized")
        )

        return try {
            val response = functions.invoke(
                function = "account-deletion",
                body = buildJsonObject {
                    put("userId", userId)
                    put("reason", reason)
                }
            )

            val result = Json.parseToJsonElement(response.bodyAsText()).jsonObject
            val success = result["success"]?.jsonPrimitive?.content == "true"
            Result.success(success)
        } catch (e: Exception) {
            Log.w(TAG, "Account deletion call failed: ${e.message}")
            Result.failure(e)
        }
    }

    private fun generateFallbackIcebreaker(matchName: String, sharedInterests: List<String>): String {
        return if (sharedInterests.isNotEmpty()) {
            "You both love ${sharedInterests.first()}! Ask $matchName what got them into it or their favorite spot for it."
        } else {
            "Ask $matchName about their ideal weekend adventure or their go-to coffee spot!"
        }
    }

    companion object {
        @Volatile
        private var INSTANCE: SupabaseEdgeFunctions? = null

        fun getInstance(): SupabaseEdgeFunctions {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SupabaseEdgeFunctions().also { INSTANCE = it }
            }
        }
    }
}
