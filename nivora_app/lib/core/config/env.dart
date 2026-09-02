/// Environment configuration.
///
/// WHAT IS SAFE TO BE HERE, and why. Only the project URL and the ANON key. The anon key is
/// designed to be public: it identifies the project and grants nothing by itself, because
/// every table is behind row-level security evaluated against the caller's JWT. Shipping it in
/// an APK is the intended use.
///
/// WHAT MUST NEVER BE HERE: SUPABASE_SERVICE_ROLE_KEY, the Razorpay key SECRET, the webhook
/// secret, or any SMTP credential. Those bypass RLS or authorise money movement, and anything
/// compiled into an APK is readable by anyone who downloads it. They stay server-side, in the
/// Next.js server actions and the Razorpay webhook route.
///
/// RAZORPAY_KEY_ID USED TO BE HERE and is gone with the checkout: v1 takes rent at the warden's
/// desk, and a publishable key no code reads is a build-time knob that can only drift. The
/// razorpay-order Edge Function reads its own key from the server's environment, where the
/// secret half already lives.
///
/// Values can be overridden at build time without editing this file:
///   flutter build appbundle --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// which is how staging and production builds differ.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nimxvgzscbanhtvgnjll.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pbXh2Z3pzY2Jhbmh0dmduamxsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1NzQzNjYsImV4cCI6MjEwMTE1MDM2Nn0.AEFDIcHmli9QKx5pFbTGCTpwFuDykK212XJFTqvSMN4',
  );

  /// The custom URL scheme the confirmation link comes back on.
  ///
  /// It is this app's own `applicationId` (android/app/build.gradle.kts) used as a scheme, which
  /// is the reverse-DNS form RFC 3986 allows and nothing else on the device can claim. It is
  /// duplicated in exactly one other place — the `<data>` element of the VIEW intent-filter in
  /// android/app/src/main/AndroidManifest.xml — because a manifest cannot read a Dart constant.
  /// Change one and you must change the other, and the operator instruction below changes with
  /// them, which is why the instruction is built from these constants rather than typed out.
  static const emailLinkScheme = 'app.nivora.mobile';

  /// The authority half of the deep link. Pinned in the intent-filter alongside the scheme, so
  /// the filter cannot be widened by accident into "any app.nivora.mobile:// link".
  static const emailLinkHost = 'verify-email';

  /// Where the confirmation link in a verification email lands after GoTrue has accepted it.
  ///
  /// ═══ IT IS A DEEP LINK BACK INTO NIVORA, AND THAT IS THE WHOLE FIX ═══
  ///
  /// The owner asked for this in as many words: "it has to ask to login through that link, once
  /// they login through that link they have to verify". A custom scheme is the only shape that
  /// can actually do it. `main.dart` pins [AuthFlowType.pkce], so the code verifier for a link
  /// this app requested lives in THIS APP'S keystore and nowhere else. When the link lands here,
  /// supabase_flutter's deep-link observer sees the `?code=` GoTrue appends, exchanges it for a
  /// session, and the person is signed in BY THE LINK — which is the proof. A browser holds no
  /// verifier, so a web landing page can never complete that exchange; the best a page could
  /// ever do was render a sentence and hope, which is what the previous value did.
  ///
  /// ═══ WHAT THE OLD VALUE ACTUALLY DID, MEASURED ═══
  ///
  /// It was `https://hostelpro-three.vercel.app/verify-email/confirmed`. Measured 2026-09-01,
  /// that URL 307s to `/login?next=/verify-email/confirmed` and renders "Page not found — That
  /// link doesn't exist, or you don't have access to it", which is the screenshot the owner
  /// sent. The route is UNTRACKED in git (`git ls-files app/verify-email/` returns nothing) and
  /// was never deployed, and so is the middleware change that would make it public. Both are the
  /// owner's to commit — docs/email-verification.md §7 has the exact commands. Neither is needed
  /// for verification to work; the page is only where a LAPTOP lands.
  ///
  /// ═══ THIS VALUE MUST BE ON THE PROJECT'S ALLOW-LIST ═══
  ///
  /// GoTrue's `isRedirectURLValid` accepts a redirect that matches the allow-list OR shares a
  /// hostname with the Site URL. A custom scheme shares a hostname with nothing, so it needs the
  /// dashboard entry. Measured against this project on 2026-09-01 by asking /auth/v1/verify to
  /// redirect a dead token:
  ///
  ///   app.nivora.mobile://verify-email                      -> https://hostelpro-three.vercel.app
  ///   https://hostelpro-three.vercel.app/verify-email/…     -> honoured (same host as Site URL)
  ///   https://definitely-not-allowed.example.org/x          -> https://hostelpro-three.vercel.app
  ///
  /// So the entry is NOT there yet, and GoTrue does not say so out loud — it SUBSTITUTES the
  /// Site URL, silently. Paste this exact string into Supabase → Authentication → URL
  /// Configuration → Redirect URLs, and press Save:
  ///
  ///     app.nivora.mobile://verify-email
  ///
  /// ═══ AND IF NOBODY EVER PASTES IT, NOTHING BREAKS ═══
  ///
  /// The substitution now lands on `https://hostelpro-three.vercel.app` — the Site URL root,
  /// which returns 200. The user sees the Nivora web home page instead of the app, and the
  /// verification still SUCCEEDS: GoTrue matched the one-time token at /auth/v1/verify BEFORE
  /// redirecting anywhere, and public.email_link_proof() reads that from GoTrue's own tables
  /// afterwards. The same is true of a laptop with no Nivora installed, where the browser cannot
  /// open a custom scheme at all. In every one of those cases "I have opened the link" on the
  /// verify screen still completes the proof. This value decides where the person is standing
  /// when it finishes; it has never decided whether it finishes.
  ///
  /// Override per build:
  ///   flutter build appbundle --dart-define=EMAIL_CONFIRM_REDIRECT_URL=…
  /// Set it to the empty string to send no redirect at all and let GoTrue use the Site URL.
  static const emailConfirmRedirectUrl = String.fromEnvironment(
    'EMAIL_CONFIRM_REDIRECT_URL',
    defaultValue: '$emailLinkScheme://$emailLinkHost',
  );


  /// The one sentence an administrator has to act on, assembled from the values that are
  /// actually compiled into this build rather than transcribed from a document that can drift.
  ///
  /// Shown on the verification screen when the evidence says the link is not coming back to the
  /// app, and repeated verbatim in docs/email-verification.md.
  static String get emailRedirectSetupHint =>
      'Supabase → Authentication → URL Configuration → Redirect URLs must contain '
      '$emailConfirmRedirectUrl (exactly, then Save). Site URL does not need to change.';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
