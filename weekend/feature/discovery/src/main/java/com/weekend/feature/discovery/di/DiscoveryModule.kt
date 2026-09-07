package com.weekend.feature.discovery.di

import com.weekend.domain.repository.DiscoveryRepository
import com.weekend.domain.usecase.*
import com.weekend.feature.discovery.DiscoveryViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object DiscoveryModule {
    @Provides
    @ViewModelScoped
    fun provideDiscoveryViewModel(
        repository: DiscoveryRepository,
        getDiscoveryProfilesUseCase: GetDiscoveryProfilesUseCase,
        likeProfileUseCase: LikeProfileUseCase,
        passProfileUseCase: PassProfileUseCase,
        blockUserUseCase: BlockUserUseCase,
        reportUserUseCase: ReportUserUseCase
    ): DiscoveryViewModel = DiscoveryViewModel(
        repository = repository,
        getDiscoveryProfilesUseCase = getDiscoveryProfilesUseCase,
        likeProfileUseCase = likeProfileUseCase,
        passProfileUseCase = passProfileUseCase,
        blockUserUseCase = blockUserUseCase,
        reportUserUseCase = reportUserUseCase
    )
}
