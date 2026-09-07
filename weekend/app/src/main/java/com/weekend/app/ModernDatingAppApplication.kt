package com.weekend.app

import android.app.Application
import android.util.Log
import com.weekend.app.data.remote.SupabaseClient

class ModernDatingAppApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize Supabase client
        try {
            SupabaseClient.initialize(this)
            Log.i("WeekendApp", "Supabase client initialized successfully")
        } catch (e: Exception) {
            Log.e("WeekendApp", "Failed to initialize Supabase: ${e.message}")
        }
    }
}
