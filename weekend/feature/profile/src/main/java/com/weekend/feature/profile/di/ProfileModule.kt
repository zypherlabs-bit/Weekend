package com.weekend.feature.profile.di

import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.domain.usecase.UpdateProfileUseCase
import com.weekend.feature.profile.ProfileViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object ProfileModule {
    @Provides
    @ViewModelScoped
    fun provideProfileViewModel(
        updateProfileUseCase: UpdateProfileUseCase,
        blockUserUseCase: BlockUserUseCase,
        reportUserUseCase: ReportUserUseCase
    ): ProfileViewModel {
        return ProfileViewModel(updateProfileUseCase, blockUserUseCase, reportUserUseCase)
    }
}
