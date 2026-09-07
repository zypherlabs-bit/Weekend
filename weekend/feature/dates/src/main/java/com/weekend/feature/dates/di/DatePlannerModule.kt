package com.weekend.feature.dates.di

import com.weekend.domain.usecase.CreatePlanUseCase
import com.weekend.domain.usecase.GetPlansUseCase
import com.weekend.feature.dates.DatePlannerViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object DatePlannerModule {
    @Provides
    @ViewModelScoped
    fun provideDatePlannerViewModel(
        getPlansUseCase: GetPlansUseCase,
        createPlanUseCase: CreatePlanUseCase
    ): DatePlannerViewModel {
        return DatePlannerViewModel(getPlansUseCase, createPlanUseCase)
    }
}
