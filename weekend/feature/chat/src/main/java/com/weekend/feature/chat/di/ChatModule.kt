package com.weekend.feature.chat.di

import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.GetMessagesUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.domain.usecase.SendMessageUseCase
import com.weekend.feature.chat.ChatViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped

@Module
@InstallIn(ViewModelComponent::class)
object ChatModule {
    @Provides
    @ViewModelScoped
    fun provideChatViewModel(
        sendMessageUseCase: SendMessageUseCase,
        getMessagesUseCase: GetMessagesUseCase,
        blockUserUseCase: BlockUserUseCase,
        reportUserUseCase: ReportUserUseCase
    ): ChatViewModel {
        return ChatViewModel(sendMessageUseCase, getMessagesUseCase, blockUserUseCase, reportUserUseCase)
    }
}
