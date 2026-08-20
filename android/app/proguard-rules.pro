# The wrapper has no code of its own beyond two thin subclasses, both of which
# are named in AndroidManifest.xml and therefore kept automatically.
#
# androidbrowserhelper reflects on the browser-side TrustedWebActivityService
# interface; keeping the package intact avoids surprises when Chrome binds to it.
-keep class com.google.androidbrowserhelper.trusted.** { *; }
-keep class androidx.browser.trusted.** { *; }
-keep class androidx.browser.customtabs.** { *; }

# Standard: keep the annotation attributes AndroidX relies on.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
