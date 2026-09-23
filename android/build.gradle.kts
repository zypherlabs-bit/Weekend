buildscript {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    dependencies {
        // Inherited by every subproject. Needed so we can apply the Kotlin plugin to
        // third-party plugin modules below that fail to declare it themselves.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

subprojects {
    // credential_manager_android 4.1.0 configures `kotlin { ... }` in its build.gradle but
    // never applies the Kotlin plugin - it assumes AGP 9's built-in Kotlin support (it even
    // pins AGP 9.0.1 in its own buildscript). This project resolves the Android Gradle plugin
    // to 8.11.1, where `kotlin {}` only exists once org.jetbrains.kotlin.android is applied,
    // so assembleRelease used to die with:
    //   "Could not find method kotlin() ... on project ':credential_manager_android'"
    // Apply the Kotlin plugin the moment the Android library plugin is attached (before the
    // plugin's own script reaches its `kotlin { ... }` block). Version matches settings.gradle.kts.
    val sub = project
    if (sub.name == "credential_manager_android") {
        sub.plugins.withId("com.android.library") {
            if (!sub.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                sub.apply(mapOf("plugin" to "org.jetbrains.kotlin.android"))
            }
        }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
