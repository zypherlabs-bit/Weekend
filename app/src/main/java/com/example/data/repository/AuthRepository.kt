package com.example.data.repository

import android.content.Context
import android.util.Log
import com.example.data.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.IDToken
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.user.UserInfo
import io.github.jan.supabase.auth.user.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private const val TAG = "WeekendAuth"

data class AuthState(
    val isAuthenticated: Boolean = false,
    val isLoading: Boolean = false,
    val user: UserInfo? = null,
    val session: UserSession? = null,
    val error: String? = null,
    val emailVerified: Boolean = false
)

class AuthRepository(private val context: Context? = null) {

    private val _authState = MutableStateFlow(
        AuthState(isLoading = true)
    )
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    init {
        checkCurrentSession()
    }

    private fun checkCurrentSession() {
        val clientReady = SupabaseClient.isReady()
        if (!clientReady) {
            // Offline/demo mode: Supabase not configured (no .env credentials).
            Log.w(TAG, "Supabase not ready - running in demo mode")
            _authState.value = AuthState(
                isLoading = false,
                isAuthenticated = true,
                emailVerified = true
            )
            return
        }

        try {
            val auth = SupabaseClient.auth
            val session = auth?.currentSessionOrNull()
            val currentUser = auth?.currentUserOrNull()

            if (currentUser != null && session != null) {
                _authState.value = AuthState(
                    isAuthenticated = true,
                    isLoading = false,
                    user = currentUser,
                    session = session,
                    emailVerified = currentUser.emailConfirmedAt != null,
                    error = null
                )
            } else {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = false,
                    user = null,
                    session = null
                )
            }
        } catch (e: Exception) {
            // Security: a failed session check must NEVER be treated as
            // authenticated. Force the user back to the login screen.
            Log.w(TAG, "Failed to check session: ${e.message}")
            _authState.value = AuthState(
                isLoading = false,
                isAuthenticated = false,
                user = null,
                session = null,
                error = "Could not restore session. Please sign in again."
            )
        }
    }

    suspend fun signUpWithEmail(email: String, pass: String, fullName: String): Result<String> {
        val auth = SupabaseClient.auth
        if (auth == null) {
            return Result.success("demo_user")
        }
        _authState.update { it.copy(isLoading = true, error = null) }
        return try {
            val user = auth.signUpWith(Email) {
                this.email = email
                this.password = pass
                data = buildJsonObject {
                    put("full_name", fullName)
                }
            }

            if (user != null) {
                _authState.value = AuthState(
                    isLoading = false,
                    // With "Confirm email" enabled, the user is NOT signed in
                    // after signup until they verify their address.
                    isAuthenticated = user.emailConfirmedAt != null,
                    user = user,
                    emailVerified = user.emailConfirmedAt != null,
                    error = null
                )
                Result.success(user.id)
            } else {
                // Confirm email disabled: supabase signs the user in directly.
                val sessionUser = auth.currentUserOrNull()
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = sessionUser != null,
                    user = sessionUser,
                    emailVerified = sessionUser?.emailConfirmedAt != null,
                    error = null
                )
                Result.success(sessionUser?.id ?: "demo_user")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Sign up failed: ${e.message}")
            _authState.value = AuthState(
                isLoading = false,
                isAuthenticated = false,
                error = e.message ?: "Sign up failed"
            )
            Result.failure(e)
        }
    }

    suspend fun signInWithEmail(email: String, pass: String): Result<String> {
        val auth = SupabaseClient.auth
        if (auth == null) {
            return Result.success("demo_user")
        }
        _authState.update { it.copy(isLoading = true, error = null) }
        return try {
            auth.signInWith(Email) {
                this.email = email
                this.password = pass
            }
            val user = auth.currentUserOrNull()
            if (user != null) {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = true,
                    user = user,
                    session = auth.currentSessionOrNull(),
                    emailVerified = user.emailConfirmedAt != null,
                    error = null
                )
                Result.success(user.id)
            } else {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = false,
                    error = "Sign in failed - no user returned"
                )
                Result.failure(IllegalStateException("Sign in failed - no user returned"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Sign in failed: ${e.message}")
            _authState.value = AuthState(
                isLoading = false,
                isAuthenticated = false,
                error = e.message ?: "Sign in failed"
            )
            Result.failure(e)
        }
    }

    suspend fun signInAnonymously(): Result<String> {
        val auth = SupabaseClient.auth
        if (auth == null) {
            return Result.success("demo_user")
        }
        _authState.update { it.copy(isLoading = true, error = null) }
        return try {
            val user = auth.signInAnonymously()
            if (user != null) {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = true,
                    user = user,
                    session = auth.currentSessionOrNull(),
                    emailVerified = true,
                    error = null
                )
                Result.success(user.id)
            } else {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = false,
                    error = "Anonymous sign in failed - no user returned"
                )
                Result.failure(IllegalStateException("Anonymous sign in failed"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Anonymous sign in failed: ${e.message}")
            _authState.value = AuthState(
                isLoading = false,
                isAuthenticated = false,
                error = e.message ?: "Anonymous sign in failed"
            )
            Result.failure(e)
        }
    }

    suspend fun signInWithGoogle(idToken: String, nonce: String? = null): Result<String> {
        val auth = SupabaseClient.auth
        if (auth == null) {
            return Result.success("demo_user")
        }
        _authState.update { it.copy(isLoading = true, error = null) }
        return try {
            auth.signInWith(IDToken) {
                this.idToken = idToken
                provider = Google
                if (nonce != null) this.nonce = nonce
            }
            val user = auth.currentUserOrNull()
            if (user != null) {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = true,
                    user = user,
                    session = auth.currentSessionOrNull(),
                    emailVerified = user.emailConfirmedAt != null,
                    error = null
                )
                Result.success(user.id)
            } else {
                _authState.value = AuthState(
                    isLoading = false,
                    isAuthenticated = false,
                    error = "Google sign in failed - no user returned"
                )
                Result.failure(IllegalStateException("Google sign in failed"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Google sign in failed: ${e.message}")
            _authState.value = AuthState(
                isLoading = false,
                isAuthenticated = false,
                error = e.message ?: "Google sign in failed"
            )
            Result.failure(e)
        }
    }

    suspend fun sendPasswordReset(email: String): Result<Unit> {
        val auth = SupabaseClient.auth
        if (auth == null) {
            return Result.success(Unit)
        }
        return try {
            auth.resetPasswordForEmail(email)
            Result.success(Unit)
        } catch (e: Exception) {
            Log.w(TAG, "Password reset failed: ${e.message}")
            Result.failure(e)
        }
    }

    suspend fun updatePassword(newPassword: String): Result<Unit> {
        val auth = SupabaseClient.auth
        if (auth == null) {
            return Result.success(Unit)
        }
        return try {
            auth.updateUser {
                this.password = newPassword
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Log.w(TAG, "Password update failed: ${e.message}")
            Result.failure(e)
        }
    }

    suspend fun signOut(): Result<Unit> {
        val auth = SupabaseClient.auth
        _authState.value = AuthState(
            isLoading = false,
            isAuthenticated = false,
            user = null,
            session = null
        )
        if (auth == null) return Result.success(Unit)
        return try {
            auth.signOut()
            Result.success(Unit)
        } catch (e: Exception) {
            Log.w(TAG, "Sign out failed: ${e.message}")
            Result.success(Unit)
        }
    }

    fun isReady(): Boolean = SupabaseClient.isReady()
}
