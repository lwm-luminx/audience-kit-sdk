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
    alias(libs.plugins.maven.publish) apply false
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

// Every module that publishes goes to Maven Central as com.audiencekit:<module>:<VERSION>, its POM naming the AudienceKit
// SDK License: source-available, for use only with AudienceKit as hosted by Love Wins Media, Inc. (LICENSE beside this
// file). The `maven-central` job in .github/workflows/swift-kotlin.yml publishes each new version; signing and the
// Central Portal credentials come from ORG_GRADLE_PROJECT_* environment variables there, so `publishToMavenLocal`
// works anywhere without them.
subprojects {
    plugins.withId("com.vanniktech.maven.publish") {
        extensions.configure<com.vanniktech.maven.publish.MavenPublishBaseExtension> {
            publishToMavenCentral(automaticRelease = true)
            if (providers.gradleProperty("signingInMemoryKey").isPresent) {
                signAllPublications()
            }
            pom {
                name.set(project.name)
                description.set(
                    "AudienceKit SDK for Kotlin (${project.name}): sign people in and read an audience's venues, " +
                        "people, locales, events and chat over the AudienceKit API.",
                )
                url.set("https://developer.audiencekit.com/sdks/kotlin/audiencekit/")
                inceptionYear.set("2022")
                licenses {
                    license {
                        name.set("AudienceKit SDK License 1.2 (LicenseRef-AudienceKit-SDK-1.2)")
                        url.set("https://github.com/lwm-luminx/audience-kit-sdk/blob/main/LICENSE")
                        distribution.set("repo")
                        comments.set("Source-available, not open source: use only with AudienceKit as hosted by Love Wins Media, Inc.")
                    }
                }
                organization {
                    name.set("Love Wins Media, Inc.")
                    url.set("https://lovewins.media")
                }
                developers {
                    developer {
                        id.set("lovewinsmedia")
                        name.set("Love Wins Media, Inc.")
                        url.set("https://lovewins.media")
                    }
                }
                scm {
                    url.set("https://github.com/lwm-luminx/audience-kit-sdk")
                    connection.set("scm:git:https://github.com/lwm-luminx/audience-kit-sdk.git")
                    developerConnection.set("scm:git:ssh://git@github.com/lwm-luminx/audience-kit-sdk.git")
                }
                issueManagement {
                    system.set("GitHub")
                    url.set("https://github.com/lwm-luminx/audience-kit-sdk/issues")
                }
            }
        }
    }
}
