package com.weekend.feature.matches.di

import com.weekend.domain.usecase.GetMatchesUseCase
import com.weekend.feature.matches.MatchesViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object MatchesModule {
    @Provides
    @ViewModelScoped
    fun provideMatchesViewModel(getMatchesUseCase: GetMatchesUseCase): MatchesViewModel {
        return MatchesViewModel(getMatchesUseCase)
    }
}
