import java.util.Properties

plugins {
    id("com.android.application")
}

/* ──────────────────────────────────────────────────────────────────────────
 * Release signing material.
 *
 * The keystore and its passwords are NEVER in this repository. It lives outside
 * the working tree, where a `git clean`, a branch switch or an accidental
 * `git add -A` cannot touch it. Losing it costs an upload-key reset through Play
 * support and a redeployed assetlinks.json at best, and the ability to ever
 * update the listing at worst - docs/play-store.md §3 spells out which.
 *
 * Resolution order, first hit wins:
 *   1. environment variables  — what CI should use
 *   2. the properties file named by HOSTELPRO_KEYSTORE_PROPERTIES
 *   3. ~/.hostelpro-keys/keystore.properties  — the local default
 *
 * If nothing resolves, `bundleRelease` / `assembleRelease` fail with an
 * explicit message rather than quietly emitting an unsigned artifact that
 * Play would reject hours later.
 * ────────────────────────────────────────────────────────────────────────── */
val keystoreProps = Properties().apply {
    val explicit = System.getenv("HOSTELPRO_KEYSTORE_PROPERTIES")
    val file = if (explicit.isNullOrBlank()) {
        File(System.getProperty("user.home"), ".hostelpro-keys/keystore.properties")
    } else {
        File(explicit)
    }
    if (file.isFile) file.inputStream().use { load(it) }
}

fun signingValue(envName: String, propName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: keystoreProps.getProperty(propName)?.takeIf { it.isNotBlank() }

val ksStoreFile = signingValue("HOSTELPRO_KEYSTORE_FILE", "storeFile")
val ksStorePass = signingValue("HOSTELPRO_KEYSTORE_PASSWORD", "storePassword")
val ksKeyAlias = signingValue("HOSTELPRO_KEY_ALIAS", "keyAlias")
val ksKeyPass = signingValue("HOSTELPRO_KEY_PASSWORD", "keyPassword")
val ksStoreType = signingValue("HOSTELPRO_KEYSTORE_TYPE", "storeType") ?: "PKCS12"
val hasSigningMaterial =
    ksStoreFile != null && ksStorePass != null && ksKeyAlias != null && ksKeyPass != null &&
        File(ksStoreFile).isFile

android {
    namespace = "app.nivora.twa"
    compileSdk = 36

    defaultConfig {
        // PERMANENT once the first build reaches Play — it is the app's identity
        // in the store and cannot be changed afterwards.
        applicationId = "app.nivora.twa"
        // Chrome's TWA support itself starts at API 21, but
        // androidbrowserhelper 2.7.x declares minSdk 23 (Android 6.0), so that
        // is the real floor. It still covers ~99% of active devices.
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        // Single source of truth for the origin this app is welded to. Used by
        // the deep-link intent-filter in AndroidManifest.xml.
        manifestPlaceholders["hostName"] = "hostelpro-three.vercel.app"

        // No ACCESS_NETWORK_STATE / no analytics — the wrapper ships zero code
        // of its own beyond the launcher, so resConfigs stay at the default.
    }

    signingConfigs {
        create("release") {
            if (hasSigningMaterial) {
                storeFile = File(ksStoreFile!!)
                storeType = ksStoreType
                storePassword = ksStorePass
                keyAlias = ksKeyAlias
                keyPassword = ksKeyPass
                // API 23 predates APK Signature Scheme v2, so v1 (JAR signing)
                // is still required at this minSdk; v2/v3 cover API 24+.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (hasSigningMaterial) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = false
    }

    dependenciesInfo {
        // Play only needs the dependency blob for its own scanning; keeping it
        // out of the APK avoids shipping an encrypted blob users cannot inspect.
        includeInApk = false
        includeInBundle = true
    }
}

/*
 * Pin the JDK that compiles this module, independent of whichever JVM happens
 * to be running Gradle. It matters here: AGP shells out to `jlink` from the
 * compiling JDK to build android.jar's system-module image, and jlink from
 * JDK 26 - the default `java` on this workstation - fails that transform with
 * "Execution failed for JdkImageTransform". Declaring the toolchain keeps the
 * build reproducible instead of depending on the shell's JAVA_HOME.
 *
 * Gradle still has to FIND a JDK 21. Its auto-detection does not look inside
 * Android Studio, so where that is the only JDK 21 on the machine, point Gradle
 * at it once in ~/.gradle/gradle.properties (outside this repo, since the path
 * is machine-specific):
 *
 *   org.gradle.java.installations.paths=C:/Program Files/Android/Android Studio/jbr
 */
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

dependencies {
    // Google's official Trusted Web Activity support library. It wraps
    // androidx.browser.trusted (TrustedWebActivityIntentBuilder, the
    // TrustedWebActivityService binding used for notification delegation and
    // the Digital Asset Links verification handshake) and adds the splash
    // screen + "manage space" plumbing Play expects.
    implementation("com.google.androidbrowserhelper:androidbrowserhelper:2.7.3")
}

/*
 * Fail loudly instead of producing an unsigned release artifact.
 *
 * This has to run before ANY task executes, not as a doFirst on bundleRelease:
 * by the time that lifecycle task starts, packageReleaseBundle has already
 * written an unsigned .aab to app/build/outputs/bundle/release/, which then sits
 * there looking exactly like a good build until Play rejects it.
 */
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        task.project == project && Regex("^(bundle|assemble|package|sign).*Release$").matches(task.name)
    }
    if (buildingRelease && !hasSigningMaterial) {
        throw GradleException(
            "Release signing material not found - refusing to build an unsigned release.\n" +
                "Set HOSTELPRO_KEYSTORE_FILE / HOSTELPRO_KEYSTORE_PASSWORD / HOSTELPRO_KEY_ALIAS /\n" +
                "HOSTELPRO_KEY_PASSWORD, or create ~/.hostelpro-keys/keystore.properties from\n" +
                "android/keystore.properties.example. See docs/play-store.md."
        )
    }
}
