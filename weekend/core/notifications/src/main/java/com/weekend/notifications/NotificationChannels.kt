package com.weekend.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import com.weekend.core.common.Constants

object NotificationChannels {
    const val MATCH_CHANNEL_ID = "matches"
    const val MESSAGE_CHANNEL_ID = "messages"
    const val SAFETY_CHANNEL_ID = "safety"
    const val SUBSCRIPTION_CHANNEL_ID = "subscription"

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(MATCH_CHANNEL_ID, "Matches", NotificationManager.IMPORTANCE_HIGH)
            )
            manager.createNotificationChannel(
                NotificationChannel(MESSAGE_CHANNEL_ID, "Messages", NotificationManager.IMPORTANCE_HIGH)
            )
            manager.createNotificationChannel(
                NotificationChannel(SAFETY_CHANNEL_ID, "Safety", NotificationManager.IMPORTANCE_DEFAULT)
            )
            manager.createNotificationChannel(
                NotificationChannel(SUBSCRIPTION_CHANNEL_ID, "Subscription", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }
}
