package com.weekend.app.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.weekend.feature.chat.ui.ChatScreen
import com.weekend.feature.discovery.ui.DiscoverScreen
import com.weekend.feature.encounters.ui.EncounterScreen
import com.weekend.feature.matches.ui.MatchesScreen
import com.weekend.feature.profile.ui.ProfileScreen
import com.weekend.ui.theme.GoldenPeach
import com.weekend.ui.theme.SunsetCoral

enum class BottomTab(
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
) {
    DISCOVER("Discover", Icons.Filled.Whatshot, Icons.Outlined.Whatshot),
    NEARBY("Nearby", Icons.Filled.Place, Icons.Outlined.Place),
    LIKES("Likes", Icons.Filled.Favorite, Icons.Outlined.FavoriteBorder),
    CHAT("Chat", Icons.Filled.ChatBubble, Icons.Outlined.ChatBubbleOutline),
    PROFILE("Profile", Icons.Filled.Person, Icons.Outlined.Person)
}

@Composable
fun MainScreen(navController: NavHostController) {
    var currentTabIndex by rememberSaveable { mutableIntStateOf(0) }
    val viewModel: com.weekend.feature.matches.MatchesViewModel = hiltViewModel()
    val matches by viewModel.matches.collectAsState()
    val unreadTotal = matches.sumOf { it.unreadCount }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurface,
                tonalElevation = 8.dp
            ) {
                BottomTab.values().forEachIndexed { index, tab ->
                    val isSelected = currentTabIndex == index
                    NavigationBarItem(
                        selected = isSelected,
                        onClick = { currentTabIndex = index },
                        icon = {
                            if (tab == BottomTab.CHAT && unreadTotal > 0) {
                                BadgedBox(
                                    badge = {
                                        Badge(containerColor = SunsetCoral) {
                                            Text("$unreadTotal", color = Color.White)
                                        }
                                    }
                                ) {
                                    Icon(
                                        imageVector = if (isSelected) tab.selectedIcon else tab.unselectedIcon,
                                        contentDescription = tab.title
                                    )
                                }
                            } else {
                                Icon(
                                    imageVector = if (isSelected) tab.selectedIcon else tab.unselectedIcon,
                                    contentDescription = tab.title
                                )
                            }
                        },
                        label = {
                            Text(
                                text = tab.title,
                                fontSize = 11.sp,
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                            )
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = SunsetCoral,
                            selectedTextColor = SunsetCoral,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                            unselectedTextColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                            indicatorColor = SunsetCoral.copy(alpha = 0.12f)
                        )
                    )
                }
            }
        }
    ) { innerPadding ->
        androidx.compose.animation.AnimatedContent(
            targetState = currentTabIndex,
            transitionSpec = { androidx.compose.animation.fadeIn() togetherWith androidx.compose.animation.fadeOut() },
            label = "TabContentTransition",
            modifier = Modifier.padding(innerPadding)
        ) { targetTab ->
            when (targetTab) {
                0 -> DiscoverScreen(
                    viewModel = androidx.hilt.navigation.compose.hiltViewModel(),
                    onOpenSafetyCenter = { }
                )
                1 -> EncounterScreen(
                    viewModel = androidx.hilt.navigation.compose.hiltViewModel()
                )
                2 -> MatchesScreen(
                    viewModel = viewModel,
                    onOpenChat = { match ->
                        navController.navigate("chat/${match.id}")
                    }
                )
                3 -> MatchesScreen(
                    viewModel = viewModel,
                    onOpenChat = { match ->
                        navController.navigate("chat/${match.id}")
                    }
                )
                4 -> ProfileScreen(
                    viewModel = androidx.hilt.navigation.compose.hiltViewModel(),
                    onOpenSafetyCenter = { }
                )
            }
        }
    }
}
