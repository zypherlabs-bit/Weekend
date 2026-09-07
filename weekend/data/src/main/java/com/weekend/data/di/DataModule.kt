package com.weekend.data.di

import android.content.Context
import com.weekend.core.common.Constants
import com.weekend.core.database.WeekendDatabase
import com.weekend.core.datastore.PreferencesManager
import com.weekend.data.local.LocalDataSource
import com.weekend.data.mapper.EntityMapper
import com.weekend.data.remote.*
import com.weekend.data.repository.*
import com.weekend.domain.repository.*
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DataModule {
    @Provides
    @Singleton
    fun provideDatabase(context: Context): WeekendDatabase {
        return com.weekend.database.WeekendDatabase.getInstance(context)
    }

    @Provides
    @Singleton
    fun provideLocalDataSource(database: WeekendDatabase): LocalDataSource {
        return LocalDataSource(database)
    }

    @Provides
    @Singleton
    fun providePreferencesManager(context: Context): PreferencesManager {
        return PreferencesManager(context)
    }

    @Provides
    @Singleton
    fun provideAuthRepository(
        remote: AuthRemoteDataSource,
        ioDispatcher: CoroutineDispatcher
    ): AuthRepository = AuthRepositoryImpl(remote)

    @Provides
    @Singleton
    fun provideProfileRepository(
        remote: ProfileRemoteDataSource
    ): ProfileRepository = ProfileRepositoryImpl(remote)

    @Provides
    @Singleton
    fun provideDiscoveryRepository(
        remote: DiscoveryRemoteDataSource
    ): DiscoveryRepository = DiscoveryRepositoryImpl(remote)

    @Provides
    @Singleton
    fun provideMatchRepository(
        remote: ChatRemoteDataSource,
        local: LocalDataSource
    ): MatchRepository = MatchRepositoryImpl(remote, local)

    @Provides
    @Singleton
    fun provideChatRepository(
        remote: ChatRemoteDataSource,
        local: LocalDataSource
    ): ChatRepository = ChatRepositoryImpl(remote, local)

    @Provides
    @Singleton
    fun providePlanRepository(
        remote: ProfileRemoteDataSource,
        local: LocalDataSource
    ): PlanRepository = PlanRepositoryImpl(remote, local)

    @Provides
    @Singleton
    fun provideEncounterRepository(
        remote: DiscoveryRemoteDataSource
    ): EncounterRepository = EncounterRepositoryImpl(remote)

    @Provides
    @Singleton
    fun provideSafetyRepository(
        remote: ProfileRemoteDataSource,
        local: LocalDataSource
    ): SafetyRepository = SafetyRepositoryImpl(remote, local)

    @Provides
    @Singleton
    fun provideSubscriptionRepository(
        remote: SubscriptionRemoteDataSource
    ): SubscriptionRepository = SubscriptionRepositoryImpl(remote)

    @Provides
    @Singleton
    fun provideSettingsRepository(
        preferencesManager: PreferencesManager,
        remote: ProfileRemoteDataSource
    ): SettingsRepository = SettingsRepositoryImpl(preferencesManager, remote)

    @Provides
    fun provideIoDispatcher(): CoroutineDispatcher = Dispatchers.IO
}
