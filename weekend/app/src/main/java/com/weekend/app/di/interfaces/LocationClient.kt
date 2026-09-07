package com.weekend.app.di.interfaces

import kotlinx.coroutines.flow.Flow

interface LocationClient {
    fun getLastLocation(): Flow<android.location.Location?>
}
