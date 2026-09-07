package com.weekend.analytics

import com.weekend.core.common.Constants

object AnalyticsEvents {
    const val APP_OPENED = "app_opened"
    const val SIGNUP_STARTED = "signup_started"
    const val SIGNUP_COMPLETED = "signup_completed"
    const val PROFILE_COMPLETED = "profile_completed"
    const val PHOTO_UPLOADED = "photo_uploaded"
    const val PROFILE_VERIFIED = "profile_verified"
    const val DISCOVERY_VIEWED = "discovery_viewed"
    const val PROFILE_VIEWED = "profile_viewed"
    const val LIKE_SENT = "like_sent"
    const val PASS_SENT = "pass_sent"
    const val SUPER_LIKE_SENT = "super_like_sent"
    const val MATCH_CREATED = "match_created"
    const val MESSAGE_SENT = "message_sent"
    const val MESSAGE_RECEIVED = "message_received"
    const val CONVERSATION_STARTED = "conversation_started"
    const val DATE_CREATED = "date_created"
    const val REPORT_CREATED = "report_created"
    const val SUBSCRIPTION_STARTED = "subscription_started"
    const val SUBSCRIPTION_CANCELLED = "subscription_cancelled"
    const val ACCOUNT_DELETED = "account_deleted"
}

interface AnalyticsTracker {
    fun trackEvent(eventName: String, parameters: Map<String, Any> = emptyMap())
    fun setUserProperty(key: String, value: String)
    fun setUserId(userId: String)
    fun resetAnalytics()
}
