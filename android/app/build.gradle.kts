import java.io.File
import java.io.FileInputStream
import java.net.URI
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// WebAuthn / passkey build configuration
// ---------------------------------------------------------------------------
//
// Android Credential Manager only completes a passkey ceremony for an RP that
// is associated with the installed app. That association is proved by:
//   1. `android.credentials.webauthn.relying_party_id` in AndroidManifest.xml
//      equalling the Supabase `webauthn_rp_id`, and
//   2. an `assetlinks.json` served at https://<rp-id>/.well-known/assetlinks.json
//      listing this package name plus the SHA-256 of the SIGNING certificate.
//
// Both facts depend on WHICH CERTIFICATE signed the APK, so debug and release
// builds are associated differently and a release APK signed by a different
// key silently stops working. `PASSKEY_RP_ID` overrides the derived RP ID when
// a custom domain is in use; `PASSKEY_REQUIRE_RP_ID=true` turns a missing RP ID
// into a build failure rather than shipping an APK whose passkeys cannot work.

/** The WebAuthn relying-party ID to bake into the manifest. */
fun resolvePasskeyRpId(): String {
    val override = (project.findProperty("PASSKEY_RP_ID")
        ?: System.getenv("PASSKEY_RP_ID")) as String?
    if (override != null && override.isNotBlank()) return override.trim()

    // Derived from the same SUPABASE_URL the Dart side is built with.
    val url = (project.findProperty("SUPABASE_URL")
        ?: System.getenv("SUPABASE_URL")) as String?
    if (url == null || url.isBlank()) {
        val required = (project.findProperty("PASSKEY_REQUIRE_RP_ID")
            ?: System.getenv("PASSKEY_REQUIRE_RP_ID")) as String?
        if (required == "true") {
            throw GradleException(
                "PASSKEY_RP_ID (or SUPABASE_URL) is required when " +
                    "PASSKEY_REQUIRE_RP_ID=true, but neither is set.",
            )
        }
        return ""
    }
    val host = URI(url).host
    return if (host.isNullOrEmpty()) "" else host
}

val passkeyRpId: String = resolvePasskeyRpId()


/** base64(SHA-256(cert DER)), no padding - the assetlinks.json format. */
fun base64NoWrap(bytes: ByteArray): String =
    Base64.getEncoder().withoutPadding().encodeToString(bytes)

/**
 * SHA-256 of the certificate that will sign a release build, or "" when it
 * cannot be determined. Reads android/key.properties, which is untracked, so a
 * fresh checkout legitimately has none.
 */
fun releaseSigningSha256(): String {
    val f = File(rootDir, "key.properties")
    if (!f.exists()) return ""
    val props = Properties()
    FileInputStream(f).use { props.load(it) }
    val raw = props["storeFile"] as String? ?: return ""
    val candidate = File(raw)
    val storeFile = if (candidate.isAbsolute) candidate else File(rootDir, raw)
    if (!storeFile.exists()) return ""
    return try {
        // Read the DER bytes straight off the keystore: the first entry in a
        // JKS is the certificate, but a PKCS#12 store needs decoding, so use
        // CertificateFactory over an explicit stream rather than guessing.
        val cf = CertificateFactory.getInstance("X.509")
        val input = FileInputStream(storeFile)
        val cert = try {
            cf.generateCertificate(input)
        } finally {
            input.close()
        }
        base64NoWrap(MessageDigest.getInstance("SHA-256").digest(cert.encoded))
    } catch (e: Exception) {
        ""
    }
}

/**
 * Emits the passkey association facts into the build log.
 *
 * Without this a Digital Asset Links failure is indistinguishable from a
 * credential-provider bug on the device; with it, CI output names the exact
 * RP ID and certificate digest that must appear in assetlinks.json.
 */
tasks.register("logPasskeyConfig") {
    doLast {
        val rpId = passkeyRpId
        val digest = releaseSigningSha256()
        logger.lifecycle("---- Weekend passkey / WebAuthn configuration ----")
        logger.lifecycle("relying_party_id : $rpId")
        logger.lifecycle(
            "signing SHA-256    : " +
                (if (digest.isEmpty()) {
                    "<unavailable - check android/key.properties>"
                } else {
                    digest
                }),
        )
        if (rpId.isEmpty()) {
            logger.lifecycle(
                "WARNING: no WebAuthn RP ID; passkeys cannot complete on this build.",
            )
        } else {
            logger.lifecycle(
                "Serve this at https://$rpId/.well-known/assetlinks.json:",
            )
            logger.lifecycle(
                """[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app","package_name":"com.weekend.app","sha256_cert_fingerprints":["$digest"]}}]""",
            )
        }
        logger.lifecycle("------------------------------------------------")
    }
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

        // WebAuthn relying-party ID, fed into AndroidManifest.xml.
        //
        // Android Credential Manager will NOT complete a passkey ceremony
        // unless the RP can be associated with this app, and that association
        // is proved two ways: the `assetlinks.json` served at
        // https://<rp-id>/.well-known/assetlinks.json, and the value of
        // `android.credentials.webauthn.relying_party_id` matching it.
        //
        // The RP ID is the host of the Supabase project URL, so it can only be
        // derived at build time. `PASSKEY_RP_ID` overrides it for a custom
        // domain; `PASSKEY_REQUIRE_RP_ID=true` makes a missing one a hard
        // build failure instead of shipping an app whose passkeys cannot work.
        manifestPlaceholders["weekendRpId"] = passkeyRpId
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
