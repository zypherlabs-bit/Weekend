package com.weekend.database

import androidx.room.AutoMigration
import androidx.room.Database
import androidx.room.RoomDatabase
import com.weekend.database.entity.UserEntity
import com.weekend.database.entity.MatchEntity
import com.weekend.database.entity.MessageEntity
import com.weekend.database.entity.PlanEntity
import com.weekend.database.entity.BlockedUserEntity
import com.weekend.database.dao.UserDao
import com.weekend.database.dao.MatchDao
import com.weekend.database.dao.MessageDao
import com.weekend.database.dao.PlanDao
import com.weekend.database.dao.BlockedUserDao

@Database(
    entities = [
        UserEntity::class,
        MatchEntity::class,
        MessageEntity::class,
        PlanEntity::class,
        BlockedUserEntity::class
    ],
    version = 1,
    exportSchema = true
)
abstract class WeekendDatabase : RoomDatabase() {
    abstract fun userDao(): UserDao
    abstract fun matchDao(): MatchDao
    abstract fun messageDao(): MessageDao
    abstract fun planDao(): PlanDao
    abstract fun blockedUserDao(): BlockedUserDao
}
