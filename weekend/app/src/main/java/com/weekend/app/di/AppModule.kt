package com.weekend.app.di

import android.app.Application
import com.weekend.core.analytics.AnalyticsTracker
import com.weekend.core.common.Constants
import com.weekend.core.database.WeekendDatabase
import com.weekend.core.datastore.PreferencesManager
import com.weekend.core.location.LocationClient
import com.weekend.core.notifications.NotificationChannels
import com.weekend.security.SecureStorage
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides
    @Singleton
    fun provideAnalyticsTracker(application: Application): AnalyticsTracker {
        return com.weekend.data.remote.FirebaseAnalyticsTracker()
    }

    @Provides
    @Singleton
    fun provideSecureStorage(application: Application): SecureStorage {
        return SecureStorage.getInstance(application)
    }

    @Provides
    @Singleton
    fun provideLocationClient(application: Application): LocationClient {
        return LocationClient(application)
    }

    @Provides
    @Singleton
    fun providePreferencesManager(application: Application): PreferencesManager {
        return PreferencesManager(application)
    }

    @Provides
    @Singleton
    fun provideWeekendDatabase(application: Application): WeekendDatabase {
        return com.weekend.database.WeekendDatabase.getInstance(application)
    }
}
