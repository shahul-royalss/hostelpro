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

  /// Razorpay's PUBLISHABLE key id (rzp_test_… / rzp_live_…). Safe in a client by design; the
  /// secret that signs orders never leaves the server.
  static const razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID', defaultValue: '');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
