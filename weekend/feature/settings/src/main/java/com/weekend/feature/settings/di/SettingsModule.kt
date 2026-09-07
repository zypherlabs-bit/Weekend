package com.weekend.feature.settings.di

import com.weekend.domain.repository.SettingsRepository
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.feature.settings.SettingsViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object SettingsModule {
    @Provides
    @ViewModelScoped
    fun provideSettingsViewModel(
        settingsRepository: SettingsRepository,
        blockUserUseCase: BlockUserUseCase,
        reportUserUseCase: ReportUserUseCase
    ): SettingsViewModel {
        return SettingsViewModel(settingsRepository, blockUserUseCase, reportUserUseCase)
    }
}
