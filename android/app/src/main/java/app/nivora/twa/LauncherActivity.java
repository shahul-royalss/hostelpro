package app.nivora.twa;

/**
 * Entry point of the wrapper.
 *
 * <p>All of the behaviour lives in {@code androidbrowserhelper}'s base class: it
 * builds an {@code androidx.browser.trusted.TrustedWebActivityIntentBuilder},
 * picks a TWA-capable browser, shows the splash screen declared in
 * {@code AndroidManifest.xml} and hands over to Chrome. If no installed browser
 * supports Trusted Web Activities it degrades to a Custom Tab, and failing that
 * to an ordinary browser intent — the app is never a dead icon.
 *
 * <p>This subclass exists so the manifest can name an activity inside the app's
 * own package (required for the {@code android:autoVerify} deep-link filter to
 * be attributed to this app) and so future launch-time customisation has a home.
 * Deliberately empty otherwise: every line added here runs outside Chrome's
 * sandbox and is code Play review has to trust.
 */
public class LauncherActivity extends com.google.androidbrowserhelper.trusted.LauncherActivity {
}
