plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

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
