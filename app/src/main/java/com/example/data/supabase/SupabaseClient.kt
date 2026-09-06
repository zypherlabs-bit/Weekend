package com.example.data.supabase

import android.content.Context
import android.util.Log
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.realtime
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val TAG = "WeekendSupabase"

/**
 * Central Supabase client for Weekend.
 *
 * Initialized from BuildConfig fields injected by the secrets-gradle-plugin
 * from the local (git-ignored) .env file: SUPABASE_URL / SUPABASE_ANON_KEY.
 *
 * If Supabase is not configured or initialization fails, the app degrades to
 * offline/demo mode instead of crashing (see isReady()).
 */
object SupabaseClient {
    private var _initialized = MutableStateFlow(false)
    val initialized: StateFlow<Boolean> = _initialized.asStateFlow()

    private var _client: io.github.jan.supabase.SupabaseClient? = null
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val client: io.github.jan.supabase.SupabaseClient? get() = _client
    val auth get() = _client?.auth
    val postgrest get() = _client?.postgrest
    val realtime get() = _client?.realtime
    val storage get() = _client?.storage
    val functions get() = _client?.functions

    fun init(context: Context): Boolean {
        return try {
            val url = getEnvField("SUPABASE_URL")
            val anonKey = getEnvField("SUPABASE_ANON_KEY")

            if (url.isNullOrEmpty() || anonKey.isNullOrEmpty() ||
                url == "https://your-project-ref.supabase.co" ||
                anonKey == "public-anon-key-here") {
                Log.w(TAG, "Supabase URL or anon key not configured. Running in offline/demo mode.")
                _initialized.value = false
                return false
            }

            if (_client != null) {
                Log.d(TAG, "Supabase already initialized")
                return true
            }

            val created = createSupabaseClient(
                supabaseUrl = url,
                supabaseKey = anonKey,
            ) {
                install(Auth)
                install(Postgrest)
                install(Realtime)
                install(Storage)
                install(Functions)
            }

            _client = created
            _initialized.value = true
            Log.i(TAG, "Supabase initialized successfully")

            ioScope.launch {
                observeAuthChanges()
            }

            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Supabase: ${e.message}")
            _initialized.value = false
            false
        }
    }

    private fun getEnvField(fieldName: String): String? {
        return try {
            val buildConfigClass = Class.forName("com.example.BuildConfig")
            val field = buildConfigClass.getField(fieldName)
            field.get(null) as String
        } catch (e: Exception) {
            Log.w(TAG, "BuildConfig field $fieldName not found: ${e.message}")
            null
        }
    }

    private suspend fun observeAuthChanges() {
        val authInstance = auth ?: return
        try {
            authInstance.sessionStatus.collect { status ->
                when (status) {
                    is io.github.jan.supabase.auth.status.SessionStatus.Authenticated ->
                        Log.d(TAG, "Auth session active")
                    is io.github.jan.supabase.auth.status.SessionStatus.NotAuthenticated ->
                        Log.d(TAG, "Auth session cleared - user logged out")
                    is io.github.jan.supabase.auth.status.SessionStatus.RefreshFailure ->
                        Log.w(TAG, "Session refresh failed - user must re-authenticate")
                    is io.github.jan.supabase.auth.status.SessionStatus.Initializing ->
                        Log.d(TAG, "Auth session initializing")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Auth session observer error: ${e.message}")
        }
    }

    fun isReady(): Boolean = _client != null && _initialized.value

    fun getCurrentUserId(): String? {
        val a = auth ?: return null
        return try {
            a.currentUserOrNull()?.id
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get current user ID: ${e.message}")
            null
        }
    }

    suspend fun signOut() {
        val a = auth ?: return
        try {
            a.signOut()
        } catch (e: Exception) {
            Log.w(TAG, "Sign out failed: ${e.message}")
        }
    }

    suspend fun getCurrentSession() = auth?.currentSessionOrNull()

    suspend fun getCurrentUser() = auth?.currentUserOrNull()
}

