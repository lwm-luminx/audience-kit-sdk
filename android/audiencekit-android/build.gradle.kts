// AGP 9 compiles Kotlin itself (built-in Kotlin), so there's no separate Kotlin Android plugin.
plugins {
    id("com.android.library") // on the root build classpath; see ../../build.gradle.kts
    alias(libs.plugins.maven.publish)
}

android {
    namespace = "com.audiencekit.android"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    explicitApi()
}

dependencies {
    api(project(":audiencekit"))
    implementation(libs.play.integrity)
    // Play Integrity brings androidx.fragment 1.1.0 (through Play services), which Play Console flags as outdated.
    // A current Fragment wins dependency resolution in every app that uses this library.
    implementation(libs.androidx.fragment)
}

mavenPublishing {
    configure(
        com.vanniktech.maven.publish.AndroidSingleVariantLibrary(
            javadocJar = com.vanniktech.maven.publish.JavadocJar.Empty(),
            sourcesJar = com.vanniktech.maven.publish.SourcesJar.Sources(),
            variant = "release",
        ),
    )
}
