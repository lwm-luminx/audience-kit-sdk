// The Kotlin and Android Gradle plugins must load in the same (root) classloader: AGP 9's built-in
// Kotlin support reaches into KGP, and KGP into AGP. The Android plugin is only put on the
// classpath when there's an Android SDK (the same check as settings.gradle.kts), so building the
// core never needs Google's Maven repository.
buildscript {
    val hasAndroidSdk = listOf("ANDROID_HOME", "ANDROID_SDK_ROOT").any { System.getenv(it) != null } ||
        rootDir.resolve("local.properties").let { it.exists() && it.readText().contains("sdk.dir") }
    if (hasAndroidSdk) {
        repositories {
            google()
            mavenCentral()
        }
        dependencies {
            // Keep in step with `agp` in gradle/libs.versions.toml.
            classpath("com.android.tools.build:gradle:9.1.0")
        }
    }
}

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.kover)
}

// Line coverage of the core and the JVM library together (Kover): `./gradlew koverVerify` fails under the floor, and
// `koverXmlReport`/`koverHtmlReport` show where. The Android extras module needs a device for most of what it does.
dependencies {
    kover(project(":audiencekit-core"))
    kover(project(":audiencekit"))
}

kover {
    reports {
        verify {
            rule("SDK line coverage") {
                minBound(85)
            }
        }
    }
}

// One version for the whole SDK, Swift and Kotlin alike: the VERSION file beside this one.
val sdkVersion = rootDir.resolve("VERSION").readText().trim()

allprojects {
    group = "com.audiencekit"
    version = sdkVersion
}
