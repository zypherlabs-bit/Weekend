# Weekend ProGuard Rules
# Keep Supabase and Flutter related classes

-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Supabase
-keep class com.supabase.** { *; }
-keep class io.supabase.** { *; }
-keep class org.postgresql.** { *; }

# Local Auth
-keep class androidx.biometric.** { *; }
-keep class androidx.core.content.** { *; }

# Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Mobile Scanner
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }

# QR Flutter
-keep class qr.** { *; }

# Riverpod
-keep class io.flutter.plugins.** { *; }

# Keep serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Don't obfuscate model classes
-keep class weekend.models.** { *; }

# OkHttp
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }

# Gson/JSON
-keep class com.google.gson.** { *; }

# Network security config
-keep class android.security.** { *; }

# Prevent removal of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}