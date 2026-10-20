// AGP 9 compiles Kotlin itself (built-in Kotlin), so there's no separate Kotlin Android plugin.
plugins {
    id("com.android.library") // on the root build classpath; see ../../build.gradle.kts
    `maven-publish`
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

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

kotlin {
    explicitApi()
}

dependencies {
    api(project(":audiencekit"))
}

publishing {
    publications {
        create<MavenPublication>("release") {
            artifactId = "audiencekit-android"
            afterEvaluate { from(components["release"]) }
        }
    }
}
