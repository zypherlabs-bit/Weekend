package com.weekend.domain.usecase

import com.weekend.domain.model.ChatMessage
import com.weekend.domain.repository.ChatRepository

class SendMessageUseCase(private val chatRepository: ChatRepository) {
    suspend operator fun invoke(matchId: String, text: String): Result<ChatMessage> {
        return chatRepository.sendMessage(matchId, text)
    }
}