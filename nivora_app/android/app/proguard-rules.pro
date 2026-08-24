# R8 rules for the Nivora release build.
#
# Minification is ON (see build.gradle.kts), which is what keeps the APK from carrying every
# unused class in every dependency. The cost is that anything reached only by reflection has to
# be named here, because R8 cannot see those references and will strip them. Each block below
# exists because something breaks without it — not as a precaution.

# ── Flutter engine ───────────────────────────────────────────────────────────
# The embedding is entered from native code via JNI, so R8 sees no callers.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── Razorpay ─────────────────────────────────────────────────────────────────
# Checkout builds its payment screens reflectively and talks to the host app through an
# annotated bridge. Stripping any of it turns "pay rent" into a blank activity, and the failure
# only shows up in a release build — never in debug.
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.** { *; }
-dontwarn com.razorpay.**
-keepclassmembers class * {
    @proguard.annotation.Keep *;
}
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

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
