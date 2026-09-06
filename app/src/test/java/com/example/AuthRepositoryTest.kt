package com.example

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.data.repository.AuthRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class AuthRepositoryTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `auth state starts in demo mode when supabase not configured`() {
        val repo = AuthRepository(context)
        val state = runTest { repo.authState.first() }
        // No .env credentials in test environment -> offline/demo mode.
        assertTrue(state.isAuthenticated)
        assertEquals(null, state.error)
    }

    @Test
    fun `sign in anonymously returns demo success when supabase not configured`() = runTest {
        val repo = AuthRepository(context)
        val result = repo.signInAnonymously()
        assertTrue(result.isSuccess)
    }

    @Test
    fun `sign in with email returns demo success when supabase not configured`() = runTest {
        val repo = AuthRepository(context)
        val result = repo.signInWithEmail("demo@test.com", "password")
        assertTrue(result.isSuccess)
    }

    @Test
    fun `sign up with email returns demo success when supabase not configured`() = runTest {
        val repo = AuthRepository(context)
        val result = repo.signUpWithEmail("newuser@test.com", "password123", "Test User")
        assertTrue(result.isSuccess)
    }

    @Test
    fun `sign out clears authentication state`() = runTest {
        val repo = AuthRepository(context)
        repo.signInAnonymously()
        repo.signOut()
        val state = repo.authState.first()
        assertFalse(state.isAuthenticated)
    }
}

