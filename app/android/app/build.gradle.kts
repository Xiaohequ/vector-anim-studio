import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val playSigningProperties = Properties()
val playSigningPropertiesFile = rootProject.file("key.properties")
if (playSigningPropertiesFile.exists()) {
    playSigningProperties.load(FileInputStream(playSigningPropertiesFile))
}

android {
    namespace = "fr.xqu.vector_anim_studio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "fr.xqu.vector_anim_studio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (playSigningPropertiesFile.exists()) {
            create("playRelease") {
                storeFile = rootProject.file(playSigningProperties["storeFile"] as String)
                storePassword = playSigningProperties["storePassword"] as String
                keyAlias = playSigningProperties["keyAlias"] as String
                keyPassword = playSigningProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (playSigningPropertiesFile.exists()) {
                signingConfigs.getByName("playRelease")
            } else {
                // Builds de validation de PR : seulement pour vérifier la compilation.
                signingConfigs.getByName("debug")
            }
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
