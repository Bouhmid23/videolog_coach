import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key properties for release signing
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Support CI environment variables with fallback to key.properties
val storePass = System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties.getProperty("storePassword")
val keyPass = System.getenv("KEY_PASSWORD") ?: keystoreProperties.getProperty("keyPassword")
val keyAliasProp = System.getenv("KEY_ALIAS") ?: keystoreProperties.getProperty("keyAlias") ?: "upload"
val storeFilePath = System.getenv("KEYSTORE_FILE") ?: keystoreProperties.getProperty("storeFile") ?: "upload-keystore.jks"

val resolvedKeystoreFile = storeFilePath?.let { file(it) }
val isSigningConfigured = resolvedKeystoreFile != null &&
    resolvedKeystoreFile.exists() &&
    !storePass.isNullOrBlank() &&
    !keyPass.isNullOrBlank() &&
    !keyAliasProp.isNullOrBlank()

android {
    namespace = "com.opkodelabs.videolog_coach"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.opkodelabs.videolog_coach"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 31
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        create("release") {
            if (isSigningConfigured) {
                keyAlias = keyAliasProp
                keyPassword = keyPass
                storeFile = resolvedKeystoreFile
                storePassword = storePass
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (isSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
