package app.hostelpro.twa;

/**
 * The app half of {@code androidx.browser.trusted.TrustedWebActivityService}.
 *
 * <p>Chrome binds to this service to hand the splash bitmap across the process
 * boundary, and it is the hook web push notifications would be delegated
 * through if the PWA ever registers a service worker. It must live in the app's
 * package because Chrome resolves it by the app's own package name after the
 * Digital Asset Links check passes.
 */
public class DelegationService extends com.google.androidbrowserhelper.trusted.DelegationService {
}
