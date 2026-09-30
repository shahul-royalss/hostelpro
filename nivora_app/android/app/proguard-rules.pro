# R8 rules for the Nivora release build.
#
# Minification is ON (see build.gradle.kts), which is what keeps the APK from carrying every
# unused class in every dependency. The cost is that anything reached only by reflection has to
# be named here, because R8 cannot see those references and will strip them. Each block below
# exists because something breaks without it — not as a precaution.

# ── Flutter engine ───────────────────────────────────────────────────────────
# NO BLANKET io.flutter KEEP, deliberately. There used to be seven lines here keeping every
# io.flutter class whole, on the reasoning that the embedding is entered from native code via JNI
# so R8 sees no callers. That reasoning is right, and the protection already exists without them:
#
#   - Every class libflutter.so looks up by name carries class-level @androidx.annotation.Keep in
#     the shipped embedding (flutter_embedding_release-1.0.0-5d531788...jar, checked 2026-09-30):
#     FlutterJNI, FlutterOverlaySurface, FlutterMutatorsStack, SurfaceTextureWrapper,
#     FlutterCallbackInformation, TextureRegistry$ImageConsumer.
#   - androidx.annotation ships the consumer rule "-keep @androidx.annotation.Keep class * {*;}",
#     so R8 keeps those classes with every member.
#   - The one reflective lookup of an app class, Class.forName("...GeneratedPluginRegistrant"),
#     targets a class the Flutter tool generates with @Keep (see that file).
#   - Manifest components (MainActivity, the FCM service/receiver) are kept by AAPT's rules.
#
# So the blanket lines kept only DEAD embedding classes. That cost DEX size and Play's R8 score,
# and some of those dead classes contain the deprecated Window.setStatusBarColor calls that
# Play's edge-to-edge warning counts. If a release build ever crashes with ClassNotFoundException
# or NoSuchMethodError in io.flutter, the fix is to keep that ONE class, not to bring back
# io.flutter.**.

# ── Generic and annotation metadata ──────────────────────────────────────────
# Kept for every library that reflects over types at runtime. This line arrived with Razorpay's
# checkout SDK, which is back in the app (razorpay_flutter; see the Razorpay block below), and it
# would stay even without it: Signature and InnerClasses are what let any library recover a
# generic type after minification, and dropping them is the kind of change that only fails in a
# release build.
#
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ── Razorpay checkout ──────────────────────────────────────────────────────
# The SDK builds its payment screens REFLECTIVELY. Minified, the screens come up blank and the
# only symptom is a resident staring at an empty sheet with their rent unpaid — a failure that
# appears in release builds and never in debug, which is why these rules ship with the plugin
# rather than being added after someone reports it.
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.** { *; }
-dontwarn com.razorpay.**
-keepclassmembers class * {
    @proguard.annotation.Keep *;
}

# ── Supabase / OkHttp / Kotlin serialization ────────────────────────────────
# Response bodies are deserialised by name. Obfuscated field names deserialise to null, which
# would surface as "no data" rather than as a crash — the worst kind of failure to debug.
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

# ── Play Core ────────────────────────────────────────────────────────────────
# Flutter's deferred-components hooks reference Play Core even when the feature is unused.
# Without this R8 fails on missing classes rather than simply omitting them.
-dontwarn com.google.android.play.core.**

# ── Crash reports that can be read ───────────────────────────────────────────
# Keep line numbers, then hide the original file name. A stack trace with line numbers and a
# mapping file is diagnosable; one without is guesswork.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
