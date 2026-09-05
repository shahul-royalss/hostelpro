import 'package:mobile/features/auth/email_verification_service.dart';

/// A stand-in for the real verification service, shared by every test that has to mount a
/// screen which reads it.
///
/// It lives here rather than inside one test file because two now need it:
/// email_verification_test.dart, which is about this feature, and
/// change_password_finishes_test.dart, which is about where a password change ARRIVES — and
/// that is now sometimes the verify screen. The alternative was a second copy of fifty lines
/// whose two versions would drift the first time the interface changed.
class FakeVerification implements EmailVerificationService {
  FakeVerification({
    this.resendAfter = const Duration(seconds: 60),
    this.sendFailure,
    this.statusFailure,
  });

  /// Flipped when the "user" opens the link. Everything about this feature is downstream of
  /// this one boolean changing while the app is not looking.
  bool verified = false;

  Duration resendAfter;
  VerificationFailure? sendFailure;
  VerificationFailure? statusFailure;

  int sends = 0;
  int statusCalls = 0;
  final List<String> sentTo = <String>[];

  @override
  Future<VerificationStatus> status() async {
    statusCalls++;
    final failure = statusFailure;
    if (failure != null) throw failure;
    return VerificationStatus(
      email: 'owner@example.com',
      verified: verified,
      required_: !verified,
      verifiedAt: verified ? DateTime.utc(2026, 9, 1, 10, 30) : null,
    );
  }

  @override
  Future<SendOutcome> sendLink(String email) async {
    sends++;
    sentTo.add(email);
    final failure = sendFailure;
    if (failure != null) throw failure;
    return SendOutcome(email: email, resendAfter: resendAfter);
  }
}
