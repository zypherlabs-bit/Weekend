package com.example.data.remote

import android.content.Context
import android.util.Log
import com.example.data.model.ChatMessage
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.tasks.await
import java.security.MessageDigest
import java.util.UUID

object FirebaseManager {
    private const val TAG = "WeekendFirebase"

    // Safe getters that catch uninitialized Firebase instances gracefully
    val auth: FirebaseAuth?
        get() = try {
            FirebaseAuth.getInstance()
        } catch (e: Exception) {
            Log.w(TAG, "FirebaseAuth not initialized or config missing: ${e.message}")
            null
        }

    val firestore: FirebaseFirestore?
        get() = try {
            FirebaseFirestore.getInstance()
        } catch (e: Exception) {
            Log.w(TAG, "Firestore not initialized or config missing: ${e.message}")
            null
        }

    fun isFirebaseReady(): Boolean {
        return auth != null && firestore != null
    }

    fun getCurrentUser(): FirebaseUser? {
        return auth?.currentUser
    }

    suspend fun signInWithEmail(email: String, pass: String): Result<FirebaseUser?> {
        val authInstance = auth ?: return Result.failure(IllegalStateException("Firebase Auth not initialized"))
        return try {
            val res = authInstance.signInWithEmailAndPassword(email, pass).await()
            Result.success(res.user)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun signUpWithEmail(email: String, pass: String): Result<FirebaseUser?> {
        val authInstance = auth ?: return Result.failure(IllegalStateException("Firebase Auth not initialized"))
        return try {
            val res = authInstance.createUserWithEmailAndPassword(email, pass).await()
            Result.success(res.user)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun signInAnonymously(): Result<FirebaseUser?> {
        val authInstance = auth ?: return Result.failure(IllegalStateException("Firebase Auth not initialized"))
        return try {
            val res = authInstance.signInAnonymously().await()
            Result.success(res.user)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun signInWithGoogleCredential(idToken: String): Result<FirebaseUser?> {
        val authInstance = auth ?: return Result.failure(IllegalStateException("Firebase Auth not initialized"))
        return try {
            val credential = GoogleAuthProvider.getCredential(idToken, null)
            val res = authInstance.signInWithCredential(credential).await()
            Result.success(res.user)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun saveUserProfile(profile: UserProfile): Boolean {
        val db = firestore ?: return false
        return try {
            val data = hashMapOf(
                "id" to profile.id,
                "name" to profile.name,
                "age" to profile.age,
                "gender" to profile.gender,
                "city" to profile.city,
                "bio" to profile.bio,
                "occupation" to profile.occupation,
                "relationshipIntent" to profile.relationshipIntent,
                "interests" to profile.interests,
                "favoritePlaces" to profile.favoritePlaces,
                "isPhotoVerified" to profile.isPhotoVerified,
                "trustScore" to profile.trustScore,
                "referralCode" to profile.referralCode,
                "updatedAt" to System.currentTimeMillis()
            )
            db.collection("users").document(profile.id).set(data, SetOptions.merge()).await()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to persist profile to Firestore: ${e.message}")
            false
        }
    }

    suspend fun saveWeekendPlan(plan: WeekendPlan): Boolean {
        val db = firestore ?: return false
        return try {
            val data = hashMapOf(
                "id" to plan.id,
                "creatorId" to plan.creatorId,
                "creatorName" to plan.creatorName,
                "title" to plan.title,
                "category" to plan.category,
                "venue" to plan.venue,
                "time" to plan.time,
                "description" to plan.description,
                "participants" to plan.participants,
                "createdAt" to System.currentTimeMillis()
            )
            db.collection("plans").document(plan.id).set(data, SetOptions.merge()).await()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to persist plan to Firestore: ${e.message}")
            false
        }
    }

    suspend fun sendChatMessage(matchId: String, message: ChatMessage): Boolean {
        val db = firestore ?: return false
        return try {
            val data = hashMapOf(
                "id" to message.id,
                "senderId" to message.senderId,
                "text" to message.text,
                "timestamp" to message.timestamp,
                "isRead" to message.isRead
            )
            db.collection("matches").document(matchId)
                .collection("messages").document(message.id).set(data).await()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to persist message to Firestore: ${e.message}")
            false
        }
    }
}
