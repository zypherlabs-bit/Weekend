import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.weekend.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.weekend.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing is provided via an untracked key.properties file
    // (see key.properties.example). Builds without it fall back to debug
    // signing so CI and local development remain friction-free.
    val keyPropsFile = rootProject.file("key.properties")
    val keyProps = Properties()
    var keyStoreFile: File? = null
    var keyStorePassword: String? = null
    var keyKeyAlias: String? = null
    var keyKeyPassword: String? = null

    if (keyPropsFile.exists()) {
        keyProps.load(FileInputStream(keyPropsFile))
        val rawStoreFile = keyProps["storeFile"] as String?
        if (!rawStoreFile.isNullOrBlank()) {
            val candidate = File(rawStoreFile)
            keyStoreFile = if (candidate.isAbsolute) candidate else File(rootDir, rawStoreFile)
        }
        keyStorePassword = keyProps["storePassword"] as String?
        keyKeyAlias = keyProps["keyAlias"] as String?
        keyKeyPassword = keyProps["keyPassword"] as String?
    }

    signingConfigs {
        create("release") {
            if (keyStoreFile != null && keyStorePassword != null && keyKeyAlias != null && keyKeyPassword != null) {
                storeFile = keyStoreFile
                storePassword = keyStorePassword
                keyAlias = keyKeyAlias
                keyPassword = keyKeyPassword
            } else {
                // Fallback to debug signing if release config not found
                println("WARNING: key.properties not found or incomplete. Using debug signing for release.")
                storeFile = signingConfigs.getByName("debug").storeFile
                storePassword = signingConfigs.getByName("debug").storePassword
                keyAlias = signingConfigs.getByName("debug").keyAlias
                keyPassword = signingConfigs.getByName("debug").keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
