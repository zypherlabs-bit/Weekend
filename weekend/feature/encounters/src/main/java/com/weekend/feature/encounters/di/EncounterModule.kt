package com.weekend.feature.encounters.di

import com.weekend.domain.usecase.GetCrossedPathsUseCase
import com.weekend.feature.encounters.EncounterViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object EncounterModule {
    @Provides
    @ViewModelScoped
    fun provideEncounterViewModel(getCrossedPathsUseCase: GetCrossedPathsUseCase): EncounterViewModel {
        return EncounterViewModel(getCrossedPathsUseCase)
    }
}
