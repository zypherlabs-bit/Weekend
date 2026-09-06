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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Verified
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan
import com.example.ui.WeekendViewModel
import com.example.ui.components.ProfileDetailDialog
import com.example.ui.theme.DarkBackground
import com.example.ui.theme.GoldenPeach
import com.example.ui.theme.MidnightVioletCard
import com.example.ui.theme.SunsetCoral

enum class LikesSubTab(val title: String) {
    LIKED_YOU("Who Liked You"),
    WEEKEND_PLANS("Weekend Plans")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LikesAndPlansScreen(
    viewModel: WeekendViewModel,
    modifier: Modifier = Modifier
) {
    var currentSubTab by remember { mutableStateOf(LikesSubTab.LIKED_YOU) }
    val deck by viewModel.deckProfiles.collectAsState()
    val plans by viewModel.plans.collectAsState()
    val showCreatePlanDialog by viewModel.showCreatePlanDialog.collectAsState()

    var selectedProfile by remember { mutableStateOf<UserProfile?>(null) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(DarkBackground)
            .testTag("screen_likes_and_plans")
    ) {
        TopAppBar(
            title = {
                Text(
                    text = "Likes & Plans",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 22.sp
                )
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = DarkBackground)
        )

        // Pill Switcher: "Who Liked You" & "Weekend Plans"
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            LikesSubTab.values().forEach { subTab ->
                val isSelected = currentSubTab == subTab
                Surface(
                    color = if (isSelected) Color.White else Color(0xFF1E1C24),
                    shape = RoundedCornerShape(20.dp),
                    modifier = Modifier.clickable { currentSubTab = subTab }
                ) {
                    Text(
                        text = subTab.title,
                        color = if (isSelected) Color.Black else Color.White.copy(alpha = 0.65f),
                        fontSize = 13.sp,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        when (currentSubTab) {
            LikesSubTab.LIKED_YOU -> {
                // Free & Unblurred Likes Grid (PRD Section 7: Free Forever, No Paywalls)
                Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
                    Text(
                        text = "100% Free · No blurred paywalls",
                        color = GoldenPeach,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(vertical = 4.dp)
                    )

                    LazyVerticalGrid(
                        columns = GridCells.Fixed(2),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize().padding(top = 8.dp)
                    ) {
                        items(deck) { profile ->
                            Card(
                                colors = CardDefaults.cardColors(containerColor = MidnightVioletCard),
                                shape = RoundedCornerShape(18.dp),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(230.dp)
                                    .clickable { selectedProfile = profile }
                            ) {
                                Box(modifier = Modifier.fillMaxSize()) {
                                    AsyncImage(
                                        model = profile.photos.firstOrNull() ?: "",
                                        contentDescription = profile.name,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier.fillMaxSize()
                                    )

                                    // Gradient overlay
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .background(
                                                Brush.verticalGradient(
                                                    colors = listOf(
                                                        Color.Transparent,
                                                        Color.Black.copy(alpha = 0.8f)
                                                    )
                                                )
                                            )
                                    )

                                    // Bottom Info & Match Action
                                    Column(
                                        modifier = Modifier
                                            .align(Alignment.BottomStart)
                                            .padding(12.dp)
                                    ) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(
                                                text = "${profile.name}, ${profile.age}",
                                                color = Color.White,
                                                fontSize = 16.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                            if (profile.isPhotoVerified) {
                                                Spacer(modifier = Modifier.width(4.dp))
                                                Icon(
                                                    Icons.Default.Verified,
                                                    contentDescription = null,
                                                    tint = Color(0xFF2196F3),
                                                    modifier = Modifier.size(14.dp)
                                                )
                                            }
                                        }

                                        Text(
                                            text = "${profile.distanceKm} km away",
                                            color = Color.White.copy(alpha = 0.75f),
                                            fontSize = 12.sp
                                        )

                                        Spacer(modifier = Modifier.height(6.dp))

                                        Button(
                                            onClick = { viewModel.swipeRight(profile) },
                                            colors = ButtonDefaults.buttonColors(containerColor = SunsetCoral),
                                            shape = RoundedCornerShape(14.dp),
                                            modifier = Modifier.fillMaxWidth().height(34.dp)
                                        ) {
                                            Icon(Icons.Default.Favorite, contentDescription = null, modifier = Modifier.size(12.dp))
                                            Spacer(modifier = Modifier.width(4.dp))
                                            Text("Match", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            LikesSubTab.WEEKEND_PLANS -> {
                // Plans List
                Box(modifier = Modifier.fillMaxSize()) {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(1),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 16.dp, vertical = 6.dp)
                    ) {
                        items(plans) { plan ->
                            Card(
                                colors = CardDefaults.cardColors(containerColor = MidnightVioletCard),
                                shape = RoundedCornerShape(18.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Surface(
                                            color = GoldenPeach.copy(alpha = 0.15f),
                                            shape = RoundedCornerShape(8.dp)
                                        ) {
                                            Text(
                                                text = plan.category,
                                                color = GoldenPeach,
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold,
                                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                                            )
                                        }
                                        Text(
                                            text = "by ${plan.creatorName}",
                                            color = Color.White.copy(alpha = 0.6f),
                                            fontSize = 12.sp
                                        )
                                    }

                                    Spacer(modifier = Modifier.height(8.dp))

                                    Text(
                                        text = plan.title,
                                        color = Color.White,
                                        fontSize = 17.sp,
                                        fontWeight = FontWeight.Bold
                                    )

                                    Text(
                                        text = plan.description,
                                        color = Color.White.copy(alpha = 0.8f),
                                        fontSize = 13.sp,
                                        modifier = Modifier.padding(top = 4.dp)
                                    )

                                    Spacer(modifier = Modifier.height(10.dp))

                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            text = "📍 ${plan.venue} · ${plan.time}",
                                            color = Color.White.copy(alpha = 0.7f),
                                            fontSize = 12.sp
                                        )

                                        Button(
                                            onClick = { viewModel.toggleJoinPlan(plan.id) },
                                            colors = ButtonDefaults.buttonColors(
                                                containerColor = if (plan.isJoined) Color(0xFF4CAF50) else SunsetCoral
                                            ),
                                            shape = RoundedCornerShape(14.dp),
                                            modifier = Modifier.height(34.dp)
                                        ) {
                                            Text(
                                                text = if (plan.isJoined) "Joined" else "Join Plan (${plan.participants.size})",
                                                fontSize = 12.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Floating Action Button to propose new plan
                    FloatingActionButton(
                        onClick = { viewModel.openCreatePlanDialog() },
                        containerColor = SunsetCoral,
                        contentColor = Color.White,
                        shape = CircleShape,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(20.dp)
                            .size(54.dp)
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "Propose Weekend Plan")
                    }
                }
            }
        }
    }

    if (showCreatePlanDialog) {
        CreatePlanDialog(
            onCreate = { title, category, venue, time, description ->
                viewModel.createPlan(title, category, venue, time, description)
            },
            onDismiss = { viewModel.dismissCreatePlanDialog() }
        )
    }

    selectedProfile?.let { profile ->
        ProfileDetailDialog(
            profile = profile,
            onLike = {
                viewModel.swipeRight(profile)
                selectedProfile = null
            },
            onPass = {
                viewModel.swipeLeft(profile.id)
                selectedProfile = null
            },
            onBlock = {
                viewModel.blockUser(profile.id)
                selectedProfile = null
            },
            onReport = {
                viewModel.reportUser(profile.id, "Reported")
                selectedProfile = null
            },
            onDismiss = { selectedProfile = null }
        )
    }
}
