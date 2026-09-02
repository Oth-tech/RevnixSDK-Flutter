group = "com.revnix.revnix_flutter"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        // revnix-core models are @Serializable.
        classpath("org.jetbrains.kotlin:kotlin-serialization:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}
apply(plugin = "org.jetbrains.kotlin.android")
apply(plugin = "org.jetbrains.kotlin.plugin.serialization")

android {
    namespace = "com.revnix.revnix_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs(
                "src/main/kotlin",
                // revnix-kotlin is the git submodule at android/revnix-kotlin,
                // compiled straight into this AAR until it ships to Maven
                // Central — then drop these two dirs and depend on
                //   implementation("com.revnix:revnix-android:<version>")
                "revnix-kotlin/revnix-core/src/main/kotlin",
                "revnix-kotlin/revnix-android/src/main/kotlin",
            )
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // revnix-kotlin's own dependencies (android/revnix-kotlin/*/build.gradle.kts),
    // carried over verbatim so the submodule sources compile here:
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.android.billingclient:billing-ktx:8.3.0")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
}
