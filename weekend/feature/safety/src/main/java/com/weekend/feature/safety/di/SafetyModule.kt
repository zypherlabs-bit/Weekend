package com.weekend.feature.safety.di

import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.feature.safety.SafetyViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object SafetyModule {
    @Provides
    @ViewModelScoped
    fun provideSafetyViewModel(
        blockUserUseCase: BlockUserUseCase,
        reportUserUseCase: ReportUserUseCase
    ): SafetyViewModel {
        return SafetyViewModel(blockUserUseCase, reportUserUseCase)
    }
}
