package com.example

import com.example.data.model.MatchItem
import com.example.data.model.UserProfile
import com.example.data.repository.WeekendRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class WeekendRepositoryTest {

    private val repository = WeekendRepository()

    @Test
    fun `currentUser has correct default values`() {
        val user = repository.currentUser.value
        assertEquals("Max", user.name)
        assertEquals(26, user.age)
        assertEquals("Pune", user.city)
        assertTrue(user.isPhotoVerified)
        assertEquals(98, user.trustScore)
    }

    @Test
    fun `deck profiles are initialized from sample data`() {
        val profiles = repository.deckProfiles.value
        assertTrue(profiles.isNotEmpty())
        assertTrue(profiles.size >= 5)
    }

    @Test
    fun `initial matches list is not empty`() {
        val matches = repository.matches.value
        assertTrue(matches.isNotEmpty())
    }

    @Test
    fun `initial plans list is not empty`() {
        val plans = repository.plans.value
        assertTrue(plans.isNotEmpty())
    }

    @Test
    fun `referral data has valid code`() {
        val code = repository.referralData.value.code
        assertTrue(code.isNotBlank())
    }

    @Test
    fun `swipe left removes profile from deck`() {
        val initialSize = repository.deckProfiles.value.size
        val profileToRemove = repository.deckProfiles.value.first()
        repository.swipeLeft(profileToRemove.id)
        assertEquals(initialSize - 1, repository.deckProfiles.value.size)
    }

    @Test
    fun `reset deck restores profiles`() {
        repository.resetDeck()
    }

    @Test
    fun `max distance km defaults to 25`() {
        assertEquals(25, repository.maxDistanceKm.value)
    }

    @Test
    fun `set max distance updates value`() {
        repository.setMaxDistance(50)
        assertEquals(50, repository.maxDistanceKm.value)
    }

    @Test
    fun `set discovery mode updates selected mode`() {
        val repo = WeekendRepository()
        assertEquals(com.example.data.model.DiscoveryMode.FOR_YOU, repo.selectedMode.value)
        repo.setDiscoveryMode(com.example.data.model.DiscoveryMode.NEARBY)
        assertEquals(com.example.data.model.DiscoveryMode.NEARBY, repo.selectedMode.value)
    }

    @Test
    fun `clear celebration sets recent match to null`() {
        repository.clearCelebration()
        assertEquals(null, repository.recentMatchCelebration.value)
    }

    @Test
    fun `blocked user ids starts empty`() {
        assertTrue(repository.blockedUserIds.value.isEmpty())
    }

    @Test
    fun `liked profiles starts empty`() {
        assertTrue(repository.likedProfiles.value.isEmpty())
    }
}
