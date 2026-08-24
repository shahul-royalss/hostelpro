package app.nivora.twa;

import android.annotation.SuppressLint;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.SslErrorHandler;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.activity.OnBackPressedCallback;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

/**
 * NIVORA's application shell.
 *
 * <p>WHY THIS EXISTS. The app used to be a Trusted Web Activity, which is not a container at
 * all: {@code androidbrowserhelper}'s LauncherActivity builds an intent and hands the URL to
 * Chrome. Chrome is the renderer, so "the app opens Chrome" was not a misconfiguration — it was
 * the architecture. When Digital Asset Links verification succeeded Chrome hid its own toolbar
 * and it *looked* native; when it failed, or when no installed browser supported TWAs, it fell
 * back to a Custom Tab, which is visibly Chrome with an address bar.
 *
 * <p>A WebView is a view we own. There is no toolbar to hide because there is no toolbar, no
 * asset-links handshake to fail, and no dependency on Chrome being installed, enabled or
 * current — the System WebView ships on every Android device. The web app, the APIs, the
 * database and the auth flow are untouched; only the container changed.
 *
 * <p>WHAT THIS DELIBERATELY DOES NOT DO. It does not add a URL bar, a menu, a share button or
 * any browser affordance. Navigation inside our own origin stays in the WebView; everything
 * else is handed to the system, because a payment app, a dialler or a mail client opening
 * inside our shell would be both broken and a phishing surface.
 */
public class MainActivity extends AppCompatActivity {

    /** The only origin this shell renders. Anything else leaves. */
    private static final String APP_ORIGIN = BuildConfig.APP_ORIGIN;

    private WebView web;
    private ValueCallback<Uri[]> fileCallback;
    private static final int FILE_CHOOSER_REQUEST = 1001;

    @Override
    @SuppressLint("SetJavaScriptEnabled")
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Draw behind the system bars, then pad the WebView by the real inset values. Without
        // this the page collides with the notch and the gesture bar — the complaint that the
        // app "hasn't set good in mobile view".
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);

        FrameLayout root = new FrameLayout(this);
        root.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        root.setBackgroundColor(0xFFF6F8FC); // matches the web app's background so there is no flash

        web = new WebView(this);
        web.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(web);
        setContentView(root);

        ViewCompat.setOnApplyWindowInsetsListener(root, (v, windowInsets) -> {
            Insets bars = windowInsets.getInsets(
                    WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsetsCompat.CONSUMED;
        });

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);          // it is a Next.js app; without this there is no app
        s.setDomStorageEnabled(true);          // localStorage/sessionStorage
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);               // a native app does not pinch-zoom its own chrome
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW); // HTTPS only, no downgrade
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        // Identify ourselves so the server can tell app traffic from browser traffic, while
        // keeping the stock token so feature detection and Razorpay's checks still work.
        s.setUserAgentString(s.getUserAgentString() + " NivoraApp/1.0");

        // Supabase auth is cookie-based on our own origin.
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(web, true); // Razorpay Checkout runs in an iframe

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleUrl(request.getUrl());
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                // Only the main document matters; a failed image must not blank the app.
                if (request.isForMainFrame()) showOffline();
            }

            @Override
            public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                // Never proceed. The one thing worse than an offline app is one that renders a
                // login form over a connection it could not verify.
                handler.cancel();
                showOffline();
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                                             FileChooserParams params) {
                // Students upload an ID proof and a photo; wardens upload receipts. Without this
                // every file input in the app is silently dead.
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                try {
                    startActivityForResult(params.createIntent(), FILE_CHOOSER_REQUEST);
                    return true;
                } catch (ActivityNotFoundException e) {
                    fileCallback = null;
                    return false;
                }
            }
        });

        // Android's own back gesture should walk the web history, then leave the app — which is
        // what a user expects from a native screen stack.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (web.canGoBack()) web.goBack();
                else finish();
            }
        });

        if (savedInstanceState != null) web.restoreState(savedInstanceState);
        else web.loadUrl(APP_ORIGIN);
    }

    /**
     * @return true when we handled the URL ourselves (i.e. the WebView must NOT load it).
     */
    private boolean handleUrl(Uri uri) {
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase();
        String url = uri.toString();

        // Our own origin, and Razorpay's checkout, render in place.
        if (url.startsWith(APP_ORIGIN) || isRazorpay(uri)) return false;

        // upi:, tel:, mailto:, sms:, intent: — these belong to other apps. A UPI intent is how
        // Razorpay hands off to GPay/PhonePe, so swallowing it would break paying by UPI.
        if (!scheme.equals("http") && !scheme.equals("https")) {
            return openExternally(uri);
        }

        // Any other web origin opens in the user's browser rather than inside our shell: a
        // third-party page wearing our app's frame is a phishing surface.
        return openExternally(uri);
    }

    private boolean isRazorpay(Uri uri) {
        String host = uri.getHost();
        return host != null && (host.equals("razorpay.com") || host.endsWith(".razorpay.com"));
    }

    private boolean openExternally(Uri uri) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, uri);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (ActivityNotFoundException e) {
            // No app can take it. Staying put beats crashing.
        }
        return true;
    }

    private void showOffline() {
        // Deliberately inline: an error page fetched over the network is useless when the
        // problem is the network. Mirrors the web app's palette so it does not look like a crash.
        String html =
                "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'>"
              + "<style>html,body{margin:0;height:100%;font:16px/1.5 -apple-system,Roboto,"
              + "'Segoe UI',sans-serif;background:#F6F8FC;color:#111827;display:grid;"
              + "place-items:center;text-align:center}div{max-width:22rem;padding:2rem}"
              + "h1{font-size:1.125rem;margin:0 0 .5rem}p{color:#667085;margin:0 0 1.5rem}"
              + "button{font:inherit;font-weight:600;color:#fff;background:#5B5FEF;border:0;"
              + "border-radius:12px;padding:.75rem 1.25rem;min-height:44px}</style>"
              + "<div><h1>You're offline</h1><p>NIVORA needs a connection to load your data. "
              + "Check your network and try again.</p>"
              + "<button onclick=\"location.href='" + APP_ORIGIN + "'\">Try again</button></div>";
        web.loadDataWithBaseURL(APP_ORIGIN, html, "text/html", "utf-8", null);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode == FILE_CHOOSER_REQUEST) {
            if (fileCallback != null) {
                fileCallback.onReceiveValue(
                        WebChromeClient.FileChooserParams.parseResult(resultCode, data));
                fileCallback = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        web.saveState(outState);
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            ((ViewGroup) web.getParent()).removeView(web);
            web.destroy();
        }
        super.onDestroy();
    }
}
