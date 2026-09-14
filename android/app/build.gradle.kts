plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aistudio.weekend.appwk.weekend"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aistudio.weekend.appwk.weekend"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing configuration
    val keyPropsFile = rootProject.file("key.properties")
    val keyProps = java.util.Properties()
    val storeFile: File?
    val storePassword: String?
    val keyAlias: String?
    val keyPassword: String?

    if (keyPropsFile.exists()) {
        keyProps.load(FileInputStream(keyPropsFile))
        storeFile = File(keyProps["storeFile"] as String?)
        storePassword = keyProps["storePassword"] as String?
        keyAlias = keyProps["keyAlias"] as String?
        keyPassword = keyProps["keyPassword"] as String?
    } else {
        storeFile = null
        storePassword = null
        keyAlias = null
        keyPassword = null
    }

    signingConfigs {
        create("release") {
            if (storeFile != null && storePassword != null && keyAlias != null && keyPassword != null) {
                storeFile = storeFile
                storePassword = storePassword
                keyAlias = keyAlias
                keyPassword = keyPassword
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
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
