plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.noor.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.noor.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Task 127: R8 minification (Flutter 3.47+ enables it for release by
            // default) obfuscates the jlibtorrent/SWIG wrappers — torrents then die
            // with unreadable errors like `TorrentException(torrent_error): g0.d`
            // (NoClassDefFoundError on the renamed libtorrent_jni class). Keep the
            // engine unobfuscated until a maintained keep-rules file exists.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // On-device torrent streaming engine (libtorrent rasterbar via jlibtorrent).
    // Prebuilt natives ship inside the AARs below, so no NDK is required.
    implementation("com.frostwire:jlibtorrent:1.2.0.18")
    implementation("com.frostwire:jlibtorrent-android-arm64:1.2.0.18")
    implementation("com.frostwire:jlibtorrent-android-arm:1.2.0.18")
}
