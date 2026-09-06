package com.example.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.data.model.DiscoveryMode
import com.example.data.model.UserProfile
import com.example.ui.WeekendViewModel
import com.example.ui.components.ProfileDetailDialog
import com.example.ui.components.SwipeCard
import com.example.ui.theme.DarkBackground
import com.example.ui.theme.GoldenPeach
import com.example.ui.theme.MidnightViolet
import com.example.ui.theme.MidnightVioletCard
import com.example.ui.theme.SunsetCoral

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    viewModel: WeekendViewModel,
    onOpenSafetyCenter: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val deck by viewModel.deckProfiles.collectAsState()
    val selectedMode by viewModel.selectedMode.collectAsState()
    var viewingProfile by remember { mutableStateOf<UserProfile?>(null) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(DarkBackground)
    ) {
        // Top Header Tabs (Screen 2: For You, Nearby, Vibes + Filter Icon)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // "For You" Pill (White pill when active)
                Surface(
                    color = if (selectedMode == DiscoveryMode.FOR_YOU) Color.White else Color.Transparent,
                    shape = RoundedCornerShape(20.dp),
                    modifier = Modifier.clickable { viewModel.selectDiscoveryMode(DiscoveryMode.FOR_YOU) }
                ) {
                    Text(
                        text = "For You",
                        color = if (selectedMode == DiscoveryMode.FOR_YOU) Color.Black else Color.White.copy(alpha = 0.6f),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 7.dp)
                    )
                }

                // "Nearby" Tab
                Text(
                    text = "Nearby",
                    color = if (selectedMode == DiscoveryMode.NEARBY) Color.White else Color.White.copy(alpha = 0.6f),
                    fontSize = 14.sp,
                    fontWeight = if (selectedMode == DiscoveryMode.NEARBY) FontWeight.Bold else FontWeight.Medium,
                    modifier = Modifier
                        .clickable { viewModel.selectDiscoveryMode(DiscoveryMode.NEARBY) }
                        .padding(horizontal = 4.dp, vertical = 6.dp)
                )

                // "Vibes" Tab
                Text(
                    text = "Vibes",
                    color = if (selectedMode == DiscoveryMode.INTERESTS) Color.White else Color.White.copy(alpha = 0.6f),
                    fontSize = 14.sp,
                    fontWeight = if (selectedMode == DiscoveryMode.INTERESTS) FontWeight.Bold else FontWeight.Medium,
                    modifier = Modifier
                        .clickable { viewModel.selectDiscoveryMode(DiscoveryMode.INTERESTS) }
                        .padding(horizontal = 4.dp, vertical = 6.dp)
                )
            }

            // Filter Icon on top right
            IconButton(
                onClick = onOpenSafetyCenter,
                modifier = Modifier.size(36.dp).testTag("btn_top_filter")
            ) {
                Icon(
                    androidx.compose.material.icons.Icons.Default.Tune,
                    contentDescription = "Filters",
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        // Swipe Cards Deck Area
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            contentAlignment = Alignment.Center
        ) {
            if (deck.isEmpty()) {
                // All Caught Up State
                Card(
                    colors = CardDefaults.cardColors(containerColor = MidnightVioletCard),
                    shape = RoundedCornerShape(24.dp),
                    modifier = Modifier
                        .fillMaxWidth(0.9f)
                        .padding(24.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Surface(
                            color = SunsetCoral.copy(alpha = 0.15f),
                            shape = CircleShape,
                            modifier = Modifier.size(72.dp)
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    Icons.Default.Refresh,
                                    contentDescription = null,
                                    tint = SunsetCoral,
                                    modifier = Modifier.size(36.dp)
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        Text(
                            text = "You're All Caught Up!",
                            color = Color.White,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(6.dp))

                        Text(
                            text = "No more profiles currently nearby in ${selectedMode.title}. Change your distance preferences or browse Weekend Plans!",
                            color = Color.White.copy(alpha = 0.75f),
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(20.dp))

                        Button(
                            onClick = { viewModel.resetDeck() },
                            colors = ButtonDefaults.buttonColors(containerColor = SunsetCoral),
                            shape = RoundedCornerShape(24.dp),
                            modifier = Modifier.testTag("btn_reset_deck")
                        ) {
                            Text("Rediscover Profiles", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            } else {
                // Render top 2 profiles (top card and background card for 3D depth)
                val profilesToShow = deck.take(2).reversed()
                profilesToShow.forEachIndexed { index, profile ->
                    val isTopCard = profile.id == deck.first().id
                    val scale = if (isTopCard) 1f else 0.95f

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .scale(scale)
                    ) {
                        SwipeCard(
                            profile = profile,
                            onSwipeLeft = { viewModel.swipeLeft(profile.id) },
                            onSwipeRight = { viewModel.swipeRight(profile) },
                            onStandOut = { viewModel.swipeRight(profile, isStandOut = true) },
                            onViewDetails = { viewingProfile = it }
                        )
                    }
                }
            }
        }

        // Bottom Action Controls (Pass, Stand Out, Like)
        if (deck.isNotEmpty()) {
            val topProfile = deck.first()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 40.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // PASS (Dark circular button with white X - Screen 2)
                FloatingActionButton(
                    onClick = { viewModel.swipeLeft(topProfile.id) },
                    containerColor = Color(0xFF22202A),
                    contentColor = Color.White,
                    shape = CircleShape,
                    modifier = Modifier
                        .size(54.dp)
                        .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                        .testTag("fab_swipe_pass")
                ) {
                    Icon(Icons.Default.Close, contentDescription = "Pass", modifier = Modifier.size(24.dp))
                }

                // STAND OUT / SUPER LIKE (Dark circular button with gold star - Screen 2)
                FloatingActionButton(
                    onClick = { viewModel.swipeRight(topProfile, isStandOut = true) },
                    containerColor = Color(0xFF22202A),
                    contentColor = GoldenPeach,
                    shape = CircleShape,
                    modifier = Modifier
                        .size(48.dp)
                        .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                        .testTag("fab_swipe_stand_out")
                ) {
                    Icon(Icons.Default.Star, contentDescription = "Stand Out", modifier = Modifier.size(24.dp))
                }

                // LIKE (Vibrant sunset coral circular button with white heart - Screen 2)
                FloatingActionButton(
                    onClick = { viewModel.swipeRight(topProfile) },
                    containerColor = SunsetCoral,
                    contentColor = Color.White,
                    shape = CircleShape,
                    modifier = Modifier
                        .size(64.dp)
                        .testTag("fab_swipe_like")
                ) {
                    Icon(Icons.Default.Favorite, contentDescription = "Like", modifier = Modifier.size(30.dp))
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))
    }

    // Full Profile Detail Modal
    viewingProfile?.let { profile ->
        ProfileDetailDialog(
            profile = profile,
            onLike = {
                viewModel.swipeRight(profile)
                viewingProfile = null
            },
            onPass = {
                viewModel.swipeLeft(profile.id)
                viewingProfile = null
            },
            onBlock = {
                viewModel.blockUser(profile.id)
                viewingProfile = null
            },
            onReport = {
                viewModel.reportUser(profile.id, "Inappropriate profile")
                viewingProfile = null
            },
            onDismiss = { viewingProfile = null }
        )
    }
}
