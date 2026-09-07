package com.weekend.app.di.interfaces

interface SecureStorage {
    fun save(key: String, value: String)
    fun read(key: String): String?
}
