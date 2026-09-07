package com.weekend.app.data.remote

import android.content.Context
import android.util.Log
import com.weekend.app.BuildConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.realtime
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Official Supabase client for Weekend.
 * Uses the official Supabase Kotlin SDK for Auth, PostgREST, Storage, and Realtime.
 */
object SupabaseClient {
    private const val TAG = "WeekendSupabase"

    private var client: SupabaseClient? = null

    // Session state
    private val _currentUserId = MutableStateFlow<String?>(null)
    val currentUserId: StateFlow<String?> = _currentUserId.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    /**
     * Initialize the Supabase client.
     * Must be called once at application startup.
     */
    fun initialize(context: Context) {
        if (client != null) return

        val supabaseUrl = BuildConfig.SUPABASE_URL
        val supabaseKey = BuildConfig.SUPABASE_ANON_KEY

        if (supabaseUrl.isBlank() || supabaseUrl.contains("placeholder")) {
            Log.w(TAG, "Supabase URL not configured. Using demo mode.")
            return
        }

        client = createSupabaseClient(
            supabaseUrl = supabaseUrl,
            supabaseKey = supabaseKey
        ) {
            install(Auth) {
                alwaysAutoRefresh = true
                autoLoadFromStorage = true
            }
            install(Postgrest)
            install(Realtime) {
                reconnectDelay = 5.seconds
            }
            install(Storage)
        }

        // Restore session
        restoreSession()
    }

    /**
     * Get the Supabase client instance.
     */
    fun getClient(): SupabaseClient {
        return client ?: throw IllegalStateException(
            "Supabase client not initialized. Call initialize() first."
        )
    }

    /**
     * Check if Supabase is configured and initialized.
     */
    fun isInitialized(): Boolean = client != null

    /**
     * Restore session from storage.
     */
    private fun restoreSession() {
        try {
            val session = client?.auth?.currentSessionOrNull()
            if (session != null) {
                _currentUserId.value = session.user?.id
                _isAuthenticated.value = true
                Log.i(TAG, "Session restored for user: ${session.user?.id}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore session: ${e.message}")
        }
    }

    // ==========================================
    // AUTHENTICATION
    // ==========================================

    /**
     * Sign in with email and password.
     */
    suspend fun signInWithEmail(email: String, password: String): Result<String> {
        return try {
            val supabase = getClient()
            supabase.auth.signInWith(Email) {
                this.email = email
                this.password = password
            }
            val userId = supabase.auth.currentUserOrNull()?.id
            _currentUserId.value = userId
            _isAuthenticated.value = true
            Log.i(TAG, "Sign in successful for user: $userId")
            Result.success(userId ?: "unknown")
        } catch (e: Exception) {
            Log.e(TAG, "Sign in failed: ${e.message}")
            Result.failure(e)
        }
    }

    /**
     * Sign up with email and password.
     */
    suspend fun signUpWithEmail(email: String, password: String): Result<String> {
        return try {
            val supabase = getClient()
            supabase.auth.signUpWith(Email) {
                this.email = email
                this.password = password
            }
            val userId = supabase.auth.currentUserOrNull()?.id
            _currentUserId.value = userId
            _isAuthenticated.value = userId != null
            Log.i(TAG, "Sign up successful for user: $userId")
            Result.success(userId ?: "unknown")
        } catch (e: Exception) {
            Log.e(TAG, "Sign up failed: ${e.message}")
            Result.failure(e)
        }
    }

    /**
     * Sign out the current user.
     */
    suspend fun signOut() {
        try {
            client?.auth?.signOut()
            _currentUserId.value = null
            _isAuthenticated.value = false
            Log.i(TAG, "Sign out successful")
        } catch (e: Exception) {
            Log.e(TAG, "Sign out failed: ${e.message}")
        }
    }

    /**
     * Get the current user ID, or null if not authenticated.
     */
    fun getCurrentUserId(): String? {
        return _currentUserId.value ?: client?.auth?.currentUserOrNull()?.id
    }

    /**
     * Get the current access token.
     */
    fun getAccessToken(): String? {
        return client?.auth?.currentSessionOrNull()?.accessToken
    }

    // ==========================================
    // DATABASE (PostgREST)
    // ==========================================

    /**
     * Get the Postgrest client.
     */
    fun getPostgrest() = getClient().postgrest

    /**
     * Get the Realtime client.
     */
    fun getRealtime() = getClient().realtime

    /**
     * Get the Storage client.
     */
    fun getStorage() = getClient().storage

    /**
     * Get the Auth client.
     */
    fun getAuth() = getClient().auth

    // ==========================================
    // STORAGE
    // ==========================================

    /**
     * Get the public URL for a profile photo.
     */
    fun getProfilePhotoUrl(userId: String, fileName: String): String {
        val supabaseUrl = BuildConfig.SUPABASE_URL
        return "$supabaseUrl/storage/v1/object/public/profiles/$userId/$fileName"
    }
}
