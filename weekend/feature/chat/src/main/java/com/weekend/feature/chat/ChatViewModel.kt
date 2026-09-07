package com.weekend.feature.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.weekend.domain.model.ChatMessage
import com.weekend.domain.model.MatchItem
import com.weekend.domain.model.UserProfile
import com.weekend.domain.usecase.BlockUserUseCase
import com.weekend.domain.usecase.GetMessagesUseCase
import com.weekend.domain.usecase.ReportUserUseCase
import com.weekend.domain.usecase.SendMessageUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ChatViewModel(
    private val sendMessageUseCase: SendMessageUseCase,
    private val getMessagesUseCase: GetMessagesUseCase,
    private val blockUserUseCase: BlockUserUseCase,
    private val reportUserUseCase: ReportUserUseCase
) : ViewModel() {
    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _currentUser = MutableStateFlow(UserProfile("", "", 0, "", emptyList(), "", 0, "", "", "", "", emptyList(), emptyList(), emptyList(), emptyList(), false, 0, 0, "", "", "", "", "", null, 0, "", "", 0, 0, false, false))
    val currentUser: StateFlow<UserProfile> = _currentUser.asStateFlow()

    fun loadMessages(matchId: String) {
        viewModelScope.launch {
            getMessagesUseCase(matchId).collect { msgList ->
                _messages.value = msgList
            }
        }
    }

    fun sendChatMessage(matchId: String, text: String) {
        viewModelScope.launch {
            sendMessageUseCase(matchId, text)
            loadMessages(matchId)
        }
    }

    fun blockUser(userId: String) {
        viewModelScope.launch {
            blockUserUseCase(userId)
        }
    }

    fun reportUser(userId: String, reason: String) {
        viewModelScope.launch {
            reportUserUseCase(userId, reason, "")
        }
    }
}
