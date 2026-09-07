package com.weekend.app.di

import com.weekend.core.network.ApiService
import com.weekend.core.network.NetworkModule
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkBindingsModule {
    @Provides
    @Singleton
    fun provideApiService(): ApiService = NetworkModule.provideApiService()
}
