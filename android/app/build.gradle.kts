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
        freeCompilerArgs += "-Xincremental-compilation=false"
    }

    defaultConfig {
        applicationId = "com.weekend.app"
        minSdk = 24  // Required for Credential Manager / Passkeys
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing is provided via an untracked key.properties file
    // (see key.properties.example). Builds without it fall back to a locally
    // generated debug keystore so CI and fresh checkouts remain friction-free.
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
                // Fallback: reuse (or generate) the standard Android debug
                // keystore when key.properties is absent. The path is set
                // explicitly so the build does not depend on how the Android
                // Gradle Plugin resolves ANDROID_USER_HOME on a given machine.
                println(
                    "WARNING: key.properties not found or incomplete. " +
                        "The release build will be signed with a generated development " +
                        "key and must not be distributed as a production build.",
                )
                val debugStore = File(System.getProperty("user.home"), ".android/debug.keystore")
                if (!debugStore.exists()) {
                    debugStore.parentFile?.mkdirs()
                    val generated = ProcessBuilder(
                        listOf(
                            "keytool", "-genkeypair",
                            "-keystore", debugStore.absolutePath,
                            "-storepass", "android",
                            "-alias", "androiddebugkey",
                            "-keypass", "android",
                            "-keyalg", "RSA",
                            "-keysize", "2048",
                            "-validity", "10000",
                            "-dname", "CN=Android Debug,O=Android,C=US",
                        ),
                    ).redirectErrorStream(true).start().waitFor()
                    if (generated != 0 || !debugStore.exists()) {
                        throw IllegalStateException(
                            "key.properties is missing and no debug keystore could be " +
                                "generated at ${debugStore.absolutePath}. Provide a valid " +
                                "key.properties (see android/key.properties.example) to sign " +
                                "the release build.",
                        )
                    }
                }
                storeFile = debugStore
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
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
