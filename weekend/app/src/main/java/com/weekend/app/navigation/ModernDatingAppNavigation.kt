package com.weekend.app.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.weekend.feature.auth.ui.AuthScreen
import com.weekend.feature.chat.ui.ChatScreen
import com.weekend.feature.dates.ui.DatePlannerScreen
import com.weekend.feature.discovery.ui.DiscoverScreen
import com.weekend.feature.encounters.ui.EncounterScreen
import com.weekend.feature.matches.ui.MatchesScreen
import com.weekend.feature.profile.ui.ProfileScreen
import com.weekend.feature.settings.ui.SettingsScreen
import com.weekend.feature.subscription.ui.SubscriptionScreen

@Composable
fun ModernDatingAppNavigation(
    navController: NavHostController,
    modifier: Modifier = Modifier,
    startDestination: String = "auth"
) {
    NavHost(
        navController = navController,
        startDestination = startDestination,
        modifier = modifier
    ) {
        composable("auth") {
            AuthScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel(),
                onAuthSuccess = { navController.navigate("main") {
                    popUpTo("auth") { inclusive = true }
                }}
            )
        }

        composable("main") {
            MainScreen(navController = navController)
        }

        composable("chat/{matchId}") { backStackEntry ->
            val matchId = backStack.arguments?.getString("matchId") ?: ""
            ChatScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel(),
                match = com.weekend.domain.model.MatchItem(
                    id = matchId,
                    user = com.weekend.domain.model.UserProfile(
                        id = "",
                        name = "",
                        age = 0,
                        gender = "",
                        photos = emptyList(),
                        city = "",
                        distanceKm = 0,
                        bio = "",
                        occupation = "",
                        education = "",
                        relationshipIntent = "",
                        interests = emptyList(),
                        favoritePlaces = emptyList(),
                        languages = emptyList(),
                        prompts = emptyList()
                    )
                ),
                onBack = { navController.popBackStack() }
            )
        }

        composable("subscription") {
            SubscriptionScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel()
            )
        }

        composable("dates") {
            DatePlannerScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel()
            )
        }

        composable("encounters") {
            EncounterScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel()
            )
        }

        composable("settings") {
            SettingsScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel()
            )
        }

        composable("safety") {
            com.weekend.feature.safety.ui.SafetyScreen(
                viewModel = androidx.hilt.navigation.compose.hiltViewModel()
            )
        }
    }
}
