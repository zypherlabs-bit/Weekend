package com.weekend.feature.subscription.di

import com.weekend.domain.usecase.GetPlansUseCase
import com.weekend.feature.subscription.SubscriptionViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object SubscriptionModule {
    @Provides
    @ViewModelScoped
    fun provideSubscriptionViewModel(getPlansUseCase: GetPlansUseCase): SubscriptionViewModel {
        return SubscriptionViewModel(getPlansUseCase)
    }
}
