import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "cz.gleba.gleba"
    compileSdk = maxOf(flutter.compileSdkVersion, 37) // flutter_local_notifications, androidx.core
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time on older Android).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cz.gleba.gleba"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 26) // Health Connect (health plugin)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Shared debug key committed to the repo, so local and CI builds all have
        // the same SHA-1 (registered in Firebase for Google sign-in).
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        // Upload key for Google Play. Never committed: CI writes it from the
        // GitHub secrets (see .github/workflows/release.yml), locally it comes
        // from android/key.properties (git-ignored).
        val uploadStore = System.getenv("GLEBA_UPLOAD_STORE_FILE") ?: keyProps.getProperty("storeFile")
        if (uploadStore != null) {
            create("upload") {
                storeFile = file(uploadStore)
                storePassword = System.getenv("GLEBA_UPLOAD_STORE_PASSWORD") ?: keyProps.getProperty("storePassword")
                keyAlias = System.getenv("GLEBA_UPLOAD_KEY_ALIAS") ?: keyProps.getProperty("keyAlias") ?: "upload"
                keyPassword = System.getenv("GLEBA_UPLOAD_KEY_PASSWORD") ?: keyProps.getProperty("keyPassword")
            }
        }
    }

    lint {
        // Release lint crashed inside a plugin's sources (lint bug); the
        // Flutter analyzer and tests already check our code.
        checkReleaseBuilds = false
    }

    buildTypes {
        release {
            // Play builds use the upload key; without it (local tries) the debug key.
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
