package com.weekend.feature.onboarding.di

import com.weekend.feature.onboarding.OnboardingViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object OnboardingModule {
    @Provides
    @ViewModelScoped
    fun provideOnboardingViewModel(): OnboardingViewModel = OnboardingViewModel()
}
