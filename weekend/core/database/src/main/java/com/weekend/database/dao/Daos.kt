package com.weekend.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.weekend.database.entity.BlockedUserEntity
import com.weekend.database.entity.MatchEntity
import com.weekend.database.entity.MessageEntity
import com.weekend.database.entity.PlanEntity
import com.weekend.database.entity.UserEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface UserDao {
    @Query("SELECT * FROM users WHERE id = :id")
    suspend fun getUserById(id: String): UserEntity?

    @Query("SELECT * FROM users WHERE isActive = 1 AND isBlocked = 0")
    fun getAllActiveUsers(): Flow<List<UserEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUser(user: UserEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUsers(users: List<UserEntity>)

    @Query("DELETE FROM users")
    suspend fun clearUsers()
}

@Dao
interface MatchDao {
    @Query("SELECT * FROM matches ORDER BY matchedAt DESC")
    fun getAllMatches(): Flow<List<MatchEntity>>

    @Query("SELECT * FROM matches WHERE id = :matchId")
    suspend fun getMatchById(matchId: String): MatchEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMatch(match: MatchEntity)

    @Query("UPDATE matches SET lastMessage = :lastMessage, lastMessageTime = :lastMessageTime WHERE id = :matchId")
    suspend fun updateLastMessage(matchId: String, lastMessage: String, lastMessageTime: String)

    @Query("DELETE FROM matches WHERE id = :matchId")
    suspend fun deleteMatch(matchId: String)
}

@Dao
interface MessageDao {
    @Query("SELECT * FROM messages WHERE matchId = :matchId ORDER BY timestamp ASC")
    fun getMessagesForMatch(matchId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE id = :messageId")
    suspend fun getMessageById(messageId: String): MessageEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessage(message: MessageEntity)

    @Query("UPDATE messages SET isRead = 1 WHERE matchId = :matchId AND senderId != :currentUserId")
    suspend fun markMessagesAsRead(matchId: String, currentUserId: String)

    @Query("DELETE FROM messages WHERE matchId = :matchId")
    suspend fun deleteMessagesForMatch(matchId: String)
}

@Dao
interface PlanDao {
    @Query("SELECT * FROM plans ORDER BY createdAt DESC")
    fun getAllPlans(): Flow<List<PlanEntity>>

    @Query("SELECT * FROM plans WHERE id = :planId")
    suspend fun getPlanById(planId: String): PlanEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPlan(plan: PlanEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPlans(plans: List<PlanEntity>)

    @Query("DELETE FROM plans WHERE id = :planId")
    suspend fun deletePlan(planId: String)
}

@Dao
interface BlockedUserDao {
    @Query("SELECT * FROM blocked_users ORDER BY blockedAt DESC")
    fun getAllBlockedUsers(): Flow<List<BlockedUserEntity>>

    @Query("SELECT userId FROM blocked_users")
    suspend fun getBlockedUserIds(): List<String>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertBlockedUser(blockedUser: BlockedUserEntity)

    @Delete
    suspend fun deleteBlockedUser(blockedUser: BlockedUserEntity)

    @Query("DELETE FROM blocked_users WHERE userId = :userId")
    suspend fun deleteBlockedUserById(userId: String)
}
