package com.example.ui.screens

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.Radar
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.R
import com.example.data.model.UserProfile
import com.example.ui.WeekendViewModel
import com.example.ui.components.ProfileDetailDialog
import com.example.ui.theme.DarkBackground
import com.example.ui.theme.GoldenPeach
import com.example.ui.theme.MidnightVioletCard
import com.example.ui.theme.SunsetCoral

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NearbyScreen(
    viewModel: WeekendViewModel,
    modifier: Modifier = Modifier
) {
    val deck by viewModel.deckProfiles.collectAsState()
    var selectedProfile by remember { mutableStateOf<UserProfile?>(null) }

    // Pulsing animation for user's center radar pin
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.8f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "pulseScale"
    )
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.6f,
        targetValue = 0f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "pulseAlpha"
    )

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(DarkBackground)
            .testTag("screen_nearby")
    ) {
        // Top Bar: "Nearby", "People around you" + Radar Icon
        TopAppBar(
            title = {
                Column {
                    Text(
                        text = "Nearby",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 24.sp
                    )
                    Text(
                        text = "People around you",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 13.sp
                    )
                }
            },
            actions = {
                IconButton(onClick = {}) {
                    Icon(
                        Icons.Default.Radar,
                        contentDescription = "Radar Scan",
                        tint = Color.White.copy(alpha = 0.85f),
                        modifier = Modifier.size(24.dp)
                    )
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = DarkBackground)
        )

        // Dark City Map Radar Area
        BoxWithConstraints(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
        ) {
            val widthPx = maxWidth
            val heightPx = maxHeight

            // Dark Map Background
            Image(
                painter = painterResource(id = R.drawable.dark_city_radar_map),
                contentDescription = "Nearby Radar Map",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )

            // Subtle dark overlay to ensure avatar pins stand out
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f))
            )

            // Center User Location Glowing Indicator
            Box(
                modifier = Modifier.align(Alignment.Center),
                contentAlignment = Alignment.Center
            ) {
                // Outer pulsing wave
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .scale(pulseScale)
                        .clip(CircleShape)
                        .background(Color(0xFF2196F3).copy(alpha = pulseAlpha))
                )

                // Outer halo
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF2196F3).copy(alpha = 0.3f))
                )

                // Core blue dot
                Box(
                    modifier = Modifier
                        .size(16.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF2196F3))
                        .border(2.5.dp, Color.White, CircleShape)
                )
            }

            // Floating Profile Avatar Pins mapped around the user (as shown in Mockup Screen 1)
            val pinOffsets = listOf(
                Pair(-85.dp, -130.dp), // top-left
                Pair(80.dp, -115.dp),  // top-right
                Pair(10.dp, -65.dp),   // top-center
                Pair(-105.dp, -30.dp), // middle-left
                Pair(95.dp, -15.dp),   // middle-right
                Pair(-90.dp, 45.dp),   // lower-left
                Pair(60.dp, 55.dp)     // lower-right
            )

            deck.forEachIndexed { index, profile ->
                if (index < pinOffsets.size) {
                    val (xOffset, yOffset) = pinOffsets[index]
                    Box(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .offset(x = xOffset, y = yOffset)
                            .clickable { selectedProfile = profile }
                            .testTag("pin_nearby_${profile.id}")
                    ) {
                        Surface(
                            shape = CircleShape,
                            shadowElevation = 8.dp,
                            color = Color.Transparent
                        ) {
                            AsyncImage(
                                model = profile.photos.firstOrNull() ?: "",
                                contentDescription = profile.name,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(46.dp)
                                    .clip(CircleShape)
                                    .border(2.5.dp, Color.White, CircleShape)
                            )
                        }
                    }
                }
            }
        }

        // Bottom "Within 5 km" Carousel Panel (from Mockup Screen 1)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            DarkBackground.copy(alpha = 0.85f),
                            DarkBackground
                        )
                    )
                )
                .padding(top = 8.dp, bottom = 16.dp)
        ) {
            Text(
                text = "Within 5 km",
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp)
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                deck.forEach { profile ->
                    Box(
                        modifier = Modifier
                            .clickable { selectedProfile = profile }
                            .testTag("avatar_carousel_${profile.id}")
                    ) {
                        AsyncImage(
                            model = profile.photos.firstOrNull() ?: "",
                            contentDescription = profile.name,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .size(56.dp)
                                .clip(CircleShape)
                                .border(2.dp, Color.White.copy(alpha = 0.9f), CircleShape)
                        )
                    }
                }
            }
        }
    }

    // Profile Detail Dialog when avatar or pin is tapped
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
