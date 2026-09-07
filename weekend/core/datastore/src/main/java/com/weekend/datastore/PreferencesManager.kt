package com.weekend.datastore

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.weekend.core.common.Constants
import com.weekend.domain.model.ThemeMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = Constants.PREFERENCES_NAME)

class PreferencesManager(private val context: Context) {
    private object Keys {
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val MAX_DISTANCE_KM = intPreferencesKey("max_distance_km")
        val HIDE_DISTANCE = booleanPreferencesKey("hide_distance")
        val HIDE_ONLINE_STATUS = booleanPreferencesKey("hide_online_status")
        val READ_RECEIPTS_ENABLED = booleanPreferencesKey("read_receipts_enabled")
        val NOTIFICATIONS_ENABLED = booleanPreferencesKey("notifications_enabled")
        val ENCOUNTER_DISCOVERY_ENABLED = booleanPreferencesKey("encounter_discovery_enabled")
    }

    val themeMode: Flow<ThemeMode> = context.dataStore.data.map { prefs ->
        ThemeMode.valueOf(prefs[Keys.THEME_MODE] ?: ThemeMode.SYSTEM.name)
    }

    val maxDistanceKm: Flow<Int> = context.dataStore.data.map { prefs ->
        prefs[Keys.MAX_DISTANCE_KM] ?: Constants.DEFAULT_DISTANCE_KM
    }

    val hideDistance: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[Keys.HIDE_DISTANCE] ?: false
    }

    val hideOnlineStatus: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[Keys.HIDE_ONLINE_STATUS] ?: false
    }

    val readReceiptsEnabled: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[Keys.READ_RECEIPTS_ENABLED] ?: true
    }

    val notificationsEnabled: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[Keys.NOTIFICATIONS_ENABLED] ?: true
    }

    val encounterDiscoveryEnabled: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[Keys.ENCOUNTER_DISCOVERY_ENABLED] ?: true
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.dataStore.edit { it[Keys.THEME_MODE] = mode.name }
    }

    suspend fun setMaxDistanceKm(km: Int) {
        context.dataStore.edit { it[Keys.MAX_DISTANCE_KM] = km }
    }

    suspend fun setHideDistance(hide: Boolean) {
        context.dataStore.edit { it[Keys.HIDE_DISTANCE] = hide }
    }

    suspend fun setHideOnlineStatus(hide: Boolean) {
        context.dataStore.edit { it[Keys.HIDE_ONLINE_STATUS] = hide }
    }

    suspend fun setReadReceiptsEnabled(enabled: Boolean) {
        context.dataStore.edit { it[Keys.READ_RECEIPTS_ENABLED] = enabled }
    }

    suspend fun setNotificationsEnabled(enabled: Boolean) {
        context.dataStore.edit { it[Keys.NOTIFICATIONS_ENABLED] = enabled }
    }

    suspend fun setEncounterDiscoveryEnabled(enabled: Boolean) {
        context.dataStore.edit { it[Keys.ENCOUNTER_DISCOVERY_ENABLED] = enabled }
    }
}
