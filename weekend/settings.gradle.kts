pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins { id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0" }

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ModernDatingApp"

include(":app")
include(":domain")
include(":data")
include(":core:common")
include(":core:designsystem")
include(":core:network")
include(":core:database")
include(":core:datastore")
include(":core:security")
include(":core:analytics")
include(":core:location")
include(":core:notifications")
include(":feature:auth")
include(":feature:onboarding")
include(":feature:profile")
include(":feature:discovery")
include(":feature:matches")
include(":feature:chat")
include(":feature:encounters")
include(":feature:dates")
include(":feature:settings")
include(":feature:subscription")
include(":feature:safety")
