package com.weekend.app.data.remote

import android.util.Log
import com.weekend.app.BuildConfig
import com.weekend.app.data.model.DateIdea
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object GeminiAiHelper {
    private const val TAG = "WeekendGemini"
    // Using supported modern model as specified in gemini-api skill
    private const val MODEL_NAME = "gemini-3.5-flash"
    private const val BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private fun getApiKey(): String {
        return BuildConfig.GEMINI_API_KEY
    }

    suspend fun generateIcebreaker(
        userName: String,
        matchName: String,
        sharedInterests: List<String>,
        favoritePlace: String
    ): String = withContext(Dispatchers.IO) {
        val apiKey = getApiKey()
        if (apiKey.isBlank() || apiKey == "MY_GEMINI_API_KEY") {
            // Intelligent fallback when API key is placeholder
            return@withContext if (sharedInterests.isNotEmpty()) {
                "You both love ${sharedInterests.first()}! Ask $matchName what got them into it or their favorite spot for it."
            } else {
                "Ask $matchName about their ideal weekend adventure or their go-to coffee spot!"
            }
        }

        try {
            val prompt = """
                Generate ONE short, friendly, fun, natural conversation starter (max 2 sentences) for a dating/social app called Weekend.
                User 1: $userName
                User 2: $matchName
                Shared Interests: ${sharedInterests.joinToString(", ")}
                Favorite Place: $favoritePlace
                Make it specific and engaging without being cheesy.
            """.trimIndent()

            val jsonBody = JSONObject().apply {
                val contents = JSONArray().apply {
                    put(JSONObject().apply {
                        put("parts", JSONArray().apply {
                            put(JSONObject().apply {
                                put("text", prompt)
                            })
                        })
                    })
                }
                put("contents", contents)
            }

            val request = Request.Builder()
                .url("$BASE_URL/$MODEL_NAME:generateContent?key=$apiKey")
                .post(jsonBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val resText = response.body?.string() ?: ""
            if (!response.isSuccessful) {
                Log.w(TAG, "Gemini call failed with code ${response.code}: $resText")
                return@withContext "You both like ${sharedInterests.firstOrNull() ?: "making weekend plans"}! Ask them what they're up to this Saturday."
            }

            val jsonRes = JSONObject(resText)
            val text = jsonRes.getJSONArray("candidates")
                .getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .getString("text")

            text.trim().trim('"')
        } catch (e: Exception) {
            Log.w(TAG, "Error generating icebreaker: ${e.message}")
            "You both like ${sharedInterests.firstOrNull() ?: "hanging out"}! Ask $matchName about their favorite weekend spot."
        }
    }

    suspend fun translateMessage(text: String, targetLanguage: String = "English"): String = withContext(Dispatchers.IO) {
        val apiKey = getApiKey()
        if (apiKey.isBlank() || apiKey == "MY_GEMINI_API_KEY") {
            return@withContext "[Translated to $targetLanguage]: $text"
        }

        try {
            val prompt = "Translate the following chat message accurately to $targetLanguage. Output ONLY the translated text without extra comments:\n\n$text"
            val jsonBody = JSONObject().apply {
                val contents = JSONArray().apply {
                    put(JSONObject().apply {
                        put("parts", JSONArray().apply {
                            put(JSONObject().apply {
                                put("text", prompt)
                            })
                        })
                    })
                }
                put("contents", contents)
            }

            val request = Request.Builder()
                .url("$BASE_URL/$MODEL_NAME:generateContent?key=$apiKey")
                .post(jsonBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val resText = response.body?.string() ?: ""
            val jsonRes = JSONObject(resText)
            val translated = jsonRes.getJSONArray("candidates")
                .getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .getString("text")

            translated.trim().trim('"')
        } catch (e: Exception) {
            "[Translated]: $text"
        }
    }

    suspend fun planDateIdeas(
        userInterests: List<String>,
        partnerInterests: List<String>,
        city: String = "Pune"
    ): List<DateIdea> = withContext(Dispatchers.IO) {
        val apiKey = getApiKey()
        if (apiKey.isBlank() || apiKey == "MY_GEMINI_API_KEY") {
            return@withContext getDefaultDateIdeas()
        }

        try {
            val prompt = """
                Act as the 'Weekend' App Smart Date Planner.
                City: $city
                Shared Interests: ${(userInterests + partnerInterests).distinct().joinToString(", ")}
                Generate 3 creative, real-world date suggestions suitable for young adults.
                Return ONLY valid JSON array of objects with keys:
                "title", "venueType", "description", "estimatedBudget", "conversationTip".
            """.trimIndent()

            val jsonBody = JSONObject().apply {
                val contents = JSONArray().apply {
                    put(JSONObject().apply {
                        put("parts", JSONArray().apply {
                            put(JSONObject().apply {
                                put("text", prompt)
                            })
                        })
                    })
                }
                put("contents", contents)
            }

            val request = Request.Builder()
                .url("$BASE_URL/$MODEL_NAME:generateContent?key=$apiKey")
                .post(jsonBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val resText = response.body?.string() ?: ""
            val jsonRes = JSONObject(resText)
            var rawContent = jsonRes.getJSONArray("candidates")
                .getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .getString("text")

            if (rawContent.contains("```json")) {
                rawContent = rawContent.substringAfter("```json").substringBefore("```").trim()
            } else if (rawContent.contains("```")) {
                rawContent = rawContent.substringAfter("```").substringBefore("```").trim()
            }

            val array = JSONArray(rawContent)
            val list = mutableListOf<DateIdea>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                list.add(
                    DateIdea(
                        title = obj.optString("title", "Weekend Discovery"),
                        venueType = obj.optString("venueType", "Cozy Hangout"),
                        description = obj.optString("description", "A relaxed activity to get to know each other."),
                        estimatedBudget = obj.optString("estimatedBudget", "₹₹ (Moderate)"),
                        conversationTip = obj.optString("conversationTip", "Ask about their favorite weekend routine.")
                    )
                )
            }
            if (list.isNotEmpty()) list else getDefaultDateIdeas()
        } catch (e: Exception) {
            Log.w(TAG, "Error generating date ideas: ${e.message}")
            getDefaultDateIdeas()
        }
    }

    private fun getDefaultDateIdeas(): List<DateIdea> = listOf(
        DateIdea(
            title = "Specialty Coffee Crawl & Gallery Walk",
            venueType = "Cafe + Contemporary Art",
            description = "Meet at a cozy independent roaster for artisan pour-overs, then take a stroll through the local art gallery.",
            estimatedBudget = "₹₹ (Moderate)",
            conversationTip = "Ask them about the last piece of art or music that gave them chills."
        ),
        DateIdea(
            title = "Sunset Hilltop & Chai",
            venueType = "Outdoor Nature",
            description = "A gentle golden-hour walk up the hill with panoramic city views, concluding with authentic clay-cup chai.",
            estimatedBudget = "₹ (Casual)",
            conversationTip = "Talk about dream travel destinations and funniest weekend misadventures."
        ),
        DateIdea(
            title = "Pottery Workshop or Board Game Cafe",
            venueType = "Interactive & Playful",
            description = "Skip awkward small talk and make something with your hands or team up in a cooperative strategy game.",
            estimatedBudget = "₹₹ (Moderate)",
            conversationTip = "Find out how competitive they get during board games!"
        )
    )
}
