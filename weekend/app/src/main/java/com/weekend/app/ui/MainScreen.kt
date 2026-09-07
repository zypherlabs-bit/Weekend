package com.weekend.app.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.Whatshot
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import com.weekend.app.data.model.MatchItem
import com.weekend.app.ui.screens.ChatScreen
import com.weekend.app.ui.screens.DiscoverScreen
import com.weekend.app.ui.screens.LikesAndPlansScreen
import com.weekend.app.ui.screens.MatchesScreen
import com.weekend.app.ui.screens.NearbyScreen
import com.weekend.app.ui.screens.ProfileScreen
import com.weekend.app.ui.theme.SunsetCoral

enum class BottomTab(
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
) {
    DISCOVER("Discover", Icons.Filled.Whatshot, Icons.Outlined.Whatshot),
    NEARBY("Nearby", Icons.Filled.Place, Icons.Outlined.Place),
    LIKES("Likes", Icons.Filled.Favorite, Icons.Outlined.FavoriteBorder),
    MATCHES("Matches", Icons.Filled.ChatBubble, Icons.Outlined.ChatBubbleOutline),
    PROFILE("Profile", Icons.Filled.Person, Icons.Outlined.Person)
}

@Composable
fun MainScreen(viewModel: WeekendViewModel) {
    var currentTabIndex by rememberSaveable { mutableIntStateOf(0) }
    var chatMatch by remember { mutableStateOf<MatchItem?>(null) }

    // If a chat is open, show the chat screen
    chatMatch?.let { match ->
        ChatScreen(
            viewModel = viewModel,
            match = match,
            onBack = { chatMatch = null }
        )
        return
    }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurface
            ) {
                BottomTab.entries.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        icon = {
                            Icon(
                                if (currentTabIndex == index) tab.selectedIcon else tab.unselectedIcon,
                                contentDescription = tab.title
                            )
                        },
                        label = { Text(tab.title) },
                        selected = currentTabIndex == index,
                        onClick = { currentTabIndex = index },
                        colors = androidx.compose.material3.NavigationBarItemDefaults.colors(
                            selectedIconColor = SunsetCoral,
                            selectedTextColor = SunsetCoral,
                            indicatorColor = SunsetCoral.copy(alpha = 0.12f)
                        ),
                        modifier = Modifier.testTag("nav_tab_${tab.name.lowercase()}")
                    )
                }
            }
        }
    ) { innerPadding ->
        AnimatedContent(
            targetState = currentTabIndex,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "TabContentTransition",
            modifier = Modifier.padding(innerPadding)
        ) { targetTab ->
            when (targetTab) {
                0 -> DiscoverScreen(
                    viewModel = viewModel,
                    onOpenSafetyCenter = { /* Navigate to safety center */ }
                )
                1 -> NearbyScreen(viewModel = viewModel)
                2 -> LikesAndPlansScreen(viewModel = viewModel)
                3 -> MatchesScreen(
                    viewModel = viewModel,
                    onOpenChat = { match -> chatMatch = match }
                )
                4 -> ProfileScreen(
                    viewModel = viewModel,
                    onOpenSafetyCenter = { /* Navigate to safety center */ }
                )
            }
        }
    }
}
