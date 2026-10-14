pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // `apply false` puts Google Services on the plugin classpath WITHOUT applying it anywhere.
    // app/build.gradle.kts then applies it only if android/app/google-services.json is present,
    // because the plugin fails the build outright when that file is missing — and the file
    // belongs to whoever owns the Firebase project, so it is gitignored and absent from a fresh
    // clone. See docs/edge-functions.md -> push-send.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
