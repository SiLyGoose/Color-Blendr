import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored) points at the Play upload keystore.
// https://docs.flutter.dev/deployment/android#configure-signing-in-gradle
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}

// AdMob app id (ca-app-pub-…~…): `admob.appId` in android/local.properties (gitignored).
// Without it, Google's sample app id, which only serves test ads. Release builds
// show no ads at all without a real ad unit (ADMOB_INTERSTITIAL_ID dart-define).
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) load(FileInputStream(file))
}
val adMobAppId = localProperties.getProperty("admob.appId")
    ?: "ca-app-pub-3940256099942544~3347511713"

android {
    // Must stay the same as the published Play app.
    namespace = "org.ColorBlendr.color_blendr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Must stay the same as the published Play app.
        applicationId = "org.ColorBlendr.color_blendr"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["adMobAppId"] = adMobAppId
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties, fall back to debug keys so `flutter run --release`
            // works locally. Play rejects debug-signed bundles, so this can't ship by accident.
            signingConfig =
                if (keystorePropertiesFile.exists()) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // NormalTheme in res/values/styles.xml extends Theme.MaterialComponents.
    implementation("com.google.android.material:material:1.14.0")
}
