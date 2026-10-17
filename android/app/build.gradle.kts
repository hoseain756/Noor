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
    // Keep Java wrappers and native ARM artifacts on the same maintained
    // libtorrent release. 1.2.0.18 dates from 2018 and misses years of Android,
    // DHT, tracker and NAT traversal fixes.
    val jlibtorrentVersion = "2.0.12.9"
    implementation("com.frostwire:jlibtorrent:$jlibtorrentVersion")
    implementation("com.frostwire:jlibtorrent-android-arm64:$jlibtorrentVersion")
    implementation("com.frostwire:jlibtorrent-android-arm:$jlibtorrentVersion")
}
