package com.weekend.data.local

import com.weekend.core.common.Constants
import com.weekend.database.WeekendDatabase
import com.weekend.database.dao.*
import com.weekend.database.entity.*
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LocalDataSource @Inject constructor(private val database: WeekendDatabase) {
    suspend fun getUserById(id: String) = database.userDao().getUserById(id)
    fun getAllActiveUsers(): Flow<List<UserEntity>> = database.userDao().getAllActiveUsers()
    suspend fun insertUser(user: UserEntity) = database.userDao().insertUser(user)
    suspend fun insertUsers(users: List<UserEntity>) = database.userDao().insertUsers(users)
    suspend fun clearUsers() = database.userDao().clearUsers()

    fun getAllMatches() = database.matchDao().getAllMatches()
    suspend fun getMatchById(id: String) = database.matchDao().getMatchById(id)
    suspend fun insertMatch(match: MatchEntity) = database.matchDao().insertMatch(match)
    suspend fun updateLastMessage(id: String, lastMessage: String, lastMessageTime: String) =
        database.matchDao().updateLastMessage(id, lastMessage, lastMessageTime)
    suspend fun deleteMatch(id: String) = database.matchDao().deleteMatch(id)

    fun getMessagesForMatch(matchId: String) = database.messageDao().getMessagesForMatch(matchId)
    suspend fun getMessageById(id: String) = database.messageDao().getMessageById(id)
    suspend fun insertMessage(message: MessageEntity) = database.messageDao().insertMessage(message)
    suspend fun markMessagesAsRead(matchId: String, currentUserId: String) =
        database.messageDao().markMessagesAsRead(matchId, currentUserId)
    suspend fun deleteMessagesForMatch(matchId: String) = database.messageDao().deleteMessagesForMatch(matchId)

    fun getAllPlans() = database.planDao().getAllPlans()
    suspend fun getPlanById(id: String) = database.planDao().getPlanById(id)
    suspend fun insertPlan(plan: PlanEntity) = database.planDao().insertPlan(plan)
    suspend fun insertPlans(plans: List<PlanEntity>) = database.planDao().insertPlans(plans)
    suspend fun deletePlan(id: String) = database.planDao().deletePlan(id)

    fun getAllBlockedUsers() = database.blockedUserDao().getAllBlockedUsers()
    suspend fun getBlockedUserIds() = database.blockedUserDao().getBlockedUserIds()
    suspend fun insertBlockedUser(blockedUser: BlockedUserEntity) = database.blockedUserDao().insertBlockedUser(blockedUser)
    suspend fun deleteBlockedUser(blockedUser: BlockedUserEntity) = database.blockedUserDao().deleteBlockedUser(blockedUser)
    suspend fun deleteBlockedUserById(userId: String) = database.blockedUserDao().deleteBlockedUserById(userId)
}
