import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, loaded from android/key.properties.
//
// That file is git-ignored and holds the keystore path and passwords, so
// nothing secret lives in this build script or in version control. When it is
// absent — a fresh clone, or CI — the release build falls back to the debug key
// so `flutter run --release` still works locally. Such a build is fine for
// testing but Google Play will reject it.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

android {
    namespace = "com.slowvibes.slow_vibes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications: it uses java.time APIs that
        // do not exist below API 26, and desugaring back-ports them. Without
        // this the build fails at :app:checkReleaseAarMetadata.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.slowvibes.slow_vibes"
        // FFmpegKit requires API 24 or higher.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Flutter turns R8 on for release builds whether or not we ask, so
            // the keep rules have to be registered explicitly. Without them R8
            // strips androidx.work.impl.WorkDatabase_Impl, which Room loads by
            // name, and the app dies on startup before reaching any Dart code.
            // See android/app/proguard-rules.pro for the full explanation.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Back-ports java.time (and friends) to the minSdk 24 floor.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
