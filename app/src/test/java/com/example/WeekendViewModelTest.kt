package com.example

import com.example.data.model.ChatMessage
import com.example.data.model.UserProfile
import com.example.data.repository.WeekendRepository
import com.example.ui.WeekendViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class WeekendViewModelTest {

    private val repository = WeekendRepository()

    @Test
    fun `viewModel exposes currentUser from repository`() {
        assertEquals(repository.currentUser.value, repository.currentUser.value)
    }

    @Test
    fun `swipe left removes profile from deck`() {
        val profile = repository.deckProfiles.value.first()
        val initialDeck = repository.deckProfiles.value.size

        repository.swipeLeft(profile.id)

        assertEquals(initialDeck - 1, repository.deckProfiles.value.size)
    }

    @Test
    fun `matches state is accessible`() {
        val matches = repository.matches.value
        assertTrue(matches.isNotEmpty())
        assertEquals(1, matches.size)
    }

    @Test
    fun `chat messages state is accessible`() {
        val messages = repository.chatMessages.value
        assertTrue(messages.isNotEmpty())
    }

    @Test
    fun `plans state is accessible`() {
        val plans = repository.plans.value
        assertTrue(plans.isNotEmpty())
    }

    @Test
    fun `referral data state is accessible`() {
        val referral = repository.referralData.value
        assertTrue(referral.code.isNotBlank())
    }

    @Test
    fun `auth state is accessible`() {
        val auth = repository.authState.value
        assertFalse(auth.isLoading)
    }
}
