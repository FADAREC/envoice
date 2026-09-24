plugins {
    id("com.android.application")
    // Flutter Gradle Plugin must be applied after the Android plugin.
    // kotlin-android is not applied: AGP 9 uses built-in Kotlin (android.builtInKotlin=true).
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.envoice.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.envoice.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug signing so Codemagic APK installs without a custom keystore.
            // Replace with a real release keystore before Play Store.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
