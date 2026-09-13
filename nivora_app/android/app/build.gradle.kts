import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * FIREBASE, IF THIS CHECKOUT HAS IT.
 *
 * The Google Services plugin reads android/app/google-services.json and fails the build when it
 * is absent. That file is not a secret — it ships inside the APK — but it belongs to whoever
 * owns the Play listing, so it is gitignored, and a fresh clone (or CI) has no copy. Applying
 * the plugin unconditionally would mean nobody but the account holder could build the app at
 * all.
 *
 * So it is applied only when the file is there. Without it the app still builds and still runs:
 * Firebase.initializeApp() is guarded in lib/core/notify/ and push simply stays off, while every
 * notification is still written to public.notifications and still visible in the app.
 *
 * `apply(plugin = ...)` rather than a `plugins {}` entry, because the plugins DSL is declarative
 * and cannot take an `if`. The version is pinned in settings.gradle.kts with `apply false`.
 */
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    logger.lifecycle("Nivora: google-services.json found - Firebase Cloud Messaging is enabled.")
} else {
    logger.lifecycle("Nivora: no google-services.json - building WITHOUT push notifications.")
}


/*
 * Release signing.
 *
 * Resolution order, deliberately: environment variables first so GitHub Actions can inject
 * secrets, then ~/.hostelpro-keys/keystore.properties for local builds. The keystore itself lives
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
    namespace = "com.srnivora.app"
    /*
     * PINNED AHEAD OF flutter.compileSdkVersion, WHICH IS 36.
     *
     * permission_handler_android refuses to link against anything below 37:
     *
     *     Dependency ':permission_handler_android' requires libraries and applications that
     *     depend on it to compile against version 37 or later of the Android APIs.
     *
     * COMPILING against 37 is not TARGETING 37 — targetSdk below stays on Flutter's value, which
     * is what Play measures. Compiling against the newest SDK and targeting a tested one is the
     * normal arrangement, not a compromise.
     *
     * Remove this line once flutter.compileSdkVersion reaches 37 on its own.
     */
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        /*
         * REQUIRED BY flutter_local_notifications, WHICH DRAWS THE FOREGROUND BANNER.
         *
         * That library schedules with java.time, which does not exist on API 24-25. Desugaring
         * rewrites those calls against a bundled backport at build time. Without this the build
         * does not merely lose notifications — it FAILS, at :app:checkReleaseAarMetadata, with
         * "Dependency ':flutter_local_notifications' requires core library desugaring".
         *
         * The other half of this is coreLibraryDesugaring() in the dependencies block at the
         * bottom of this file. Both are needed; either alone is an error.
         */
        isCoreLibraryDesugaringEnabled = true
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
        applicationId = "com.srnivora.app"
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

        // ── A SINGLE-ABI BUILD MUST PACKAGE A SINGLE ABI ────────────────────────────────────
        //
        // `--target-platform android-arm64` tells FLUTTER what to compile. It does not tell
        // GRADLE what to package, and Gradle packages every .so it finds in every plugin AAR.
        // Two plugins ship all three architectures, so the "arm64" APK came out containing:
        //
        //   lib/arm64-v8a/    libapp.so  libflutter.so  libdartjni.so  libdatastore....so
        //   lib/armeabi-v7a/                            libdartjni.so  libdatastore....so
        //   lib/x86_64/                                 libdartjni.so  libdatastore....so
        //
        // Android chooses its primary ABI by looking for a matching lib/ directory. On an
        // armeabi-v7a-only handset — ordinary in India's budget segment, which is this
        // product's market — it found one, installed cleanly, and then died on
        // System.loadLibrary("flutter") the instant FlutterJNI started. Installs, then will not
        // open: the exact failure this project already fought once.
        //
        // ── WHY IT IS CONDITIONAL, AND WHY ON A COMMA ──────────────────────────────────────
        //
        // The AAB must stay complete — Play splits it per device, and filtering it here would
        // ship an arm64-only bundle to every phone on earth. So this narrows the ABI set ONLY
        // when exactly one target platform was requested, which is what the per-CPU APK build
        // does and nothing else does. `flutter build apk` (universal) passes all three
        // comma-separated, and `flutter build appbundle` passes none; both fall through
        // untouched.
        val requested = project.findProperty("target-platform")?.toString()
        if (requested != null && !requested.contains(",")) {
            val abi = when (requested) {
                "android-arm64" -> "arm64-v8a"
                "android-arm" -> "armeabi-v7a"
                "android-x64" -> "x86_64"
                else -> null
            }
            if (abi != null) {
                ndk { abiFilters.clear(); abiFilters.add(abi) }
            }
        }
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

dependencies {
    // The backport that isCoreLibraryDesugaringEnabled above rewrites java.time calls against.
    // Pinned, not ranged: a floating version here is a build that can break on a machine that
    // has never seen this project, on a day nobody touched it.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
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
