import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val signingValues = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}
android {
    namespace = "com.suhel.nextbell"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.suhel.nextbell"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (signingFile.exists()) create("production") {
            keyAlias = signingValues.getProperty("keyAlias")
            keyPassword = signingValues.getProperty("keyPassword")
            storeFile = rootProject.file(signingValues.getProperty("storeFile"))
            storePassword = signingValues.getProperty("storePassword")
        }
    }
    buildTypes {
        release {
            // Local/CI release builds remain unsigned unless production keys are supplied.
            signingConfig = signingConfigs.findByName("production")
        }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }

dependencyLocking {
    lockAllConfigurations()
    // Flutter 3.47.2 pins its engine; target-specific ABI artifacts vary by device.
    ignoredDependencies.add("io.flutter:*")
}
