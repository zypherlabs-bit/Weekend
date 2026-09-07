package com.weekend.database.converter

import androidx.room.TypeConverter
import com.weekend.domain.model.DiscoveryMode
import com.weekend.domain.model.MessageState
import com.weekend.domain.model.MatchStatus
import com.weekend.domain.model.UserStatus

class Converters {
    @TypeConverter
    fun fromDiscoveryMode(mode: DiscoveryMode): String = mode.name

    @TypeConverter
    fun toDiscoveryMode(value: String): DiscoveryMode = DiscoveryMode.valueOf(value)

    @TypeConverter
    fun fromMessageState(state: MessageState): String = state.name

    @TypeConverter
    fun toMessageState(value: String): MessageState = MessageState.valueOf(value)

    @TypeConverter
    fun fromMatchStatus(status: MatchStatus): String = status.name

    @TypeConverter
    fun toMatchStatus(value: String): MatchStatus = MatchStatus.valueOf(value)

    @TypeConverter
    fun fromUserStatus(status: UserStatus): String = status.name

    @TypeConverter
    fun toUserStatus(value: String): UserStatus = UserStatus.valueOf(value)

    @TypeConverter
    fun fromStringList(value: List<String>): String = value.joinToString(",")

    @TypeConverter
    fun toStringList(value: String): List<String> = if (value.isBlank()) emptyList() else value.split(",")
}
