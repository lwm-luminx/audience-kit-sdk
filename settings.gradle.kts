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

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "audience-kit-sdk"

// core/: Kotlin Multiplatform code shared by every platform (JVM, Android and Apple).
include(":audiencekit-core")
project(":audiencekit-core").projectDir = file("core")

// android/: the JVM library (the client, models and GraphQL; builds with only a JDK) and the Android extras.
include(":audiencekit")
project(":audiencekit").projectDir = file("android/audiencekit")

// The Android extras (keystore token store, device description) need the Android SDK. They're
// left out when there's no SDK, so the core still builds and tests anywhere; CI always has one.
val hasAndroidSdk = listOf("ANDROID_HOME", "ANDROID_SDK_ROOT").any { System.getenv(it) != null } ||
    file("local.properties").let { it.exists() && it.readText().contains("sdk.dir") }
if (hasAndroidSdk) {
    include(":audiencekit-android")
    project(":audiencekit-android").projectDir = file("android/audiencekit-android")
}
