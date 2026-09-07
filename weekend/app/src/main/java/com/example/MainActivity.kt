package com.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ui.WeekendViewModel
import com.example.ui.components.MatchCelebrationDialog
import com.example.ui.components.PhotoVerificationDialog
import com.example.ui.components.SafetyCenterDialog
import com.example.ui.components.ShareDateDialog
import com.example.ui.screens.ChatScreen
import com.example.ui.screens.DiscoverScreen
import com.example.ui.screens.LikesAndPlansScreen
import com.example.ui.screens.MatchesScreen
import com.example.ui.screens.NearbyScreen
import com.example.ui.screens.ProfileScreen
import com.example.ui.screens.WelcomeScreen
import com.example.ui.theme.DarkBackground
import com.example.ui.theme.GoldenPeach
import com.example.ui.theme.MidnightViolet
import com.example.ui.theme.MidnightVioletCard
import com.example.ui.theme.SunsetCoral
import com.example.ui.theme.ThemeMode
import com.example.ui.theme.WeekendTheme

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

class MainActivity : ComponentActivity() {
    private val viewModel: WeekendViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val themeMode by viewModel.themeMode.collectAsState()
            WeekendTheme(themeMode = themeMode) {
                WeekendMainApp(viewModel = viewModel)
            }
        }
    }
}

@Composable
fun WeekendMainApp(viewModel: WeekendViewModel) {
    val context = LocalContext.current
    var showWelcomeScreen by rememberSaveable { mutableStateOf(false) }
    var currentTabIndex by rememberSaveable { mutableIntStateOf(0) }
    val activeChatMatch by viewModel.activeChatMatch.collectAsState()
    val celebrationProfile by viewModel.recentMatchCelebration.collectAsState()
    val currentUser by viewModel.currentUser.collectAsState()
    val matches by viewModel.matches.collectAsState()

    val showPhotoVerification by viewModel.showPhotoVerificationDialog.collectAsState()
    val showSafetyCenter by viewModel.showSafetyCenterDialog.collectAsState()
    val showShareDate by viewModel.showShareDateDialog.collectAsState()

    val unreadTotal = matches.sumOf { it.unreadCount }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        if (showWelcomeScreen) {
            WelcomeScreen(
                onGetStarted = { showWelcomeScreen = false },
                onAlreadyHaveAccount = {
                    viewModel.signInWithGoogleSimulation()
                    showWelcomeScreen = false
                }
            )
        } else if (activeChatMatch != null) {
            ChatScreen(
                viewModel = viewModel,
                match = activeChatMatch!!,
                onBack = { viewModel.closeChat() }
            )
        } else {
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
                            onOpenSafetyCenter = { viewModel.openSafetyCenter() }
                        )
                        1 -> NearbyScreen(
                            viewModel = viewModel,
                            onNavigateToCrossedPaths = { currentTabIndex = 0 }
                        )
                        2 -> LikesAndPlansScreen(
                            viewModel = viewModel
                        )
                        3 -> MatchesScreen(
                            viewModel = viewModel,
                            onOpenChat = { match -> viewModel.openChat(match) }
                        )
                        4 -> ProfileScreen(
                            viewModel = viewModel,
                            onOpenSafetyCenter = { viewModel.openSafetyCenter() }
                        )
                    }
                }
            }
        }

        // Mutual Match Celebration Dialog (Mockup Screen 4)
        celebrationProfile?.let { matchedUser ->
            MatchCelebrationDialog(
                currentUser = currentUser,
                matchedUser = matchedUser,
                onStartChat = {
                    val targetMatch = matches.find { it.user.id == matchedUser.id }
                    if (targetMatch != null) {
                        viewModel.openChat(targetMatch)
                    }
                    viewModel.dismissCelebration()
                },
                onDismiss = { viewModel.dismissCelebration() }
            )
        }

        // Global Safety Dialogs
        if (showPhotoVerification) {
            PhotoVerificationDialog(
                user = currentUser,
                onComplete = { trustScore ->
                    viewModel.completePhotoVerification(trustScore)
                },
                onDismiss = { viewModel.dismissPhotoVerification() }
            )
        }

        if (showSafetyCenter) {
            SafetyCenterDialog(
                onDismiss = { viewModel.dismissSafetyCenter() },
                onOpenShareDate = {
                    viewModel.dismissSafetyCenter()
                    viewModel.openShareDate()
                }
            )
        }

        if (showShareDate) {
            ShareDateDialog(
                onShare = { name, venue, time ->
                    viewModel.shareDateDetails(context, name, venue, time)
                },
                onDismiss = { viewModel.dismissShareDate() }
            )
        }
    }
}
