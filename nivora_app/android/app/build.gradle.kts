import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


/*
 * Release signing.
 *
 * Resolution order, deliberately: environment variables first so GitHub Actions can inject
 * secrets, then ~/.nivora-keys/keystore.properties for local builds. The keystore itself lives
 * OUTSIDE the repository and is never committed — losing it means Play will not accept another
 * update to this listing, and committing it means anyone with repo access can publish as you.
 *
 * A release build with no key configured falls back to the debug key and FAILS LOUDLY at the
 * point of use, rather than silently producing an artifact Play will reject on upload.
 */
val keystoreProps = Properties().apply {
    val f = File(System.getProperty("user.home"), ".hostelpro-keys/keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(env: String, prop: String): String? =
    System.getenv(env) ?: keystoreProps.getProperty(prop)

val ksStoreFile = signingValue("NIVORA_KEYSTORE_FILE", "storeFile")
val ksStoreType = signingValue("NIVORA_KEYSTORE_TYPE", "storeType") ?: "PKCS12"
val ksKeyAlias = signingValue("NIVORA_KEY_ALIAS", "keyAlias")
val ksStorePassword = signingValue("NIVORA_KEYSTORE_PASSWORD", "storePassword")
val ksKeyPassword = signingValue("NIVORA_KEY_PASSWORD", "keyPassword")
val hasReleaseKey = listOf(ksStoreFile, ksKeyAlias, ksStorePassword, ksKeyPassword)
    .all { !it.isNullOrBlank() } && File(ksStoreFile!!).exists()

android {
    namespace = "app.nivora.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                storeFile = File(ksStoreFile!!)
                storeType = ksStoreType
                keyAlias = ksKeyAlias
                storePassword = ksStorePassword
                keyPassword = ksKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "app.nivora.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Keeps `flutter run --release` working on a machine without the key, but the
                // check below stops such an artifact reaching Play by accident.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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

/*
 * A release artifact signed with the debug key is one Play rejects on upload, and the failure
 * arrives minutes later in a browser rather than here. Fail at build time instead.
 */
tasks.configureEach {
    if (name == "bundleRelease" || name == "assembleRelease") {
        doFirst {
            if (!hasReleaseKey) {
                throw GradleException(
                    """
                    Release signing key not found.
                    Set NIVORA_KEYSTORE_FILE / NIVORA_KEY_ALIAS / NIVORA_KEYSTORE_PASSWORD /
                    NIVORA_KEY_PASSWORD, or create ~/.hostelpro-keys/keystore.properties.
                    Building unsigned would produce an artifact the Play Console refuses.
                    """.trimIndent()
                )
            }
        }
    }
}
