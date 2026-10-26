/// THE ONBOARDING GATE (1.3.0): what a self-signed-up account sees before its home.
///
/// It wraps each role home INSIDE [ConsentGate], so it comes after every existing gate — second
/// factor, consent, the owed password change and email verification all run first, untouched.
/// Like ConsentGate it is a wrapper rather than a redirect arm: the decision needs data
/// (an owner's hostels) that the pure routing function cannot see.
///
///   * Owner with no PG (owns no hostel, `users.hostel_id` null) → [OwnerOnboardingFlow].
///   * Tenant (role student) with `users.hostel_id` null → [TenantOnboardingFlow].
///   * Everyone else → the home, at once.
///
/// PRESENTATION, NOT AUTHORIZATION. `ow_create_first_hostel` refuses anyone but a self-signed-up
/// owner with no PG, and the tenant RPCs refuse anyone but a tenant; this only picks a screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../owner/owner_providers.dart' show myHostelsProvider;
import 'owner/owner_onboarding_flow.dart';
import 'staff/staff_applicant_flow.dart';
import 'tenant/tenant_onboarding_flow.dart';

enum SignupNeed { none, ownerFirstPg, tenantJoin, staffApplicant }

/// What the signed-in account still owes before its home. Synchronous for every role but an
/// owner without a `hostel_id`, whose hostels are a read.
///
/// Keyed on (role, hostel_id) only, so an hourly token refresh — a new session object with the
/// same contents — does not rebuild anything.
final signupNeedProvider = Provider<AsyncValue<SignupNeed>>((ref) {
  final key = ref.watch(sessionProvider.select(
      (s) => (role: s?.role, hostel: s?.hostelId, applicant: s?.staffApplicant ?? false)));
  if (key.role == null || key.hostel != null) return const AsyncData(SignupNeed.none);
  // Round 3 (R8): a staff sign-up is role student with no PG until an owner accepts it.
  if (key.applicant) return const AsyncData(SignupNeed.staffApplicant);
  switch (key.role!) {
    case UserRole.student:
      return const AsyncData(SignupNeed.tenantJoin);
    case UserRole.owner:
      return ref
          .watch(myHostelsProvider)
          .whenData((owned) => owned.isEmpty ? SignupNeed.ownerFirstPg : SignupNeed.none);
    case UserRole.superAdmin:
    case UserRole.manager:
    case UserRole.warden:
      return const AsyncData(SignupNeed.none);
  }
});

class SignupGate extends ConsumerStatefulWidget {
  const SignupGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SignupGate> createState() => _SignupGateState();
}

class _SignupGateState extends ConsumerState<SignupGate> {
  /// Latched once the owner flow starts: creating the PG makes the hostel list non-empty, but
  /// the free-month sheet and Book a demo still belong to the flow.
  bool _ownerFlow = false;

  Future<void> _ownerFinished() async {
    ref.invalidate(myHostelsProvider);
    await ref.read(authControllerProvider.notifier).reload();
    if (mounted) setState(() => _ownerFlow = false);
  }

  @override
  Widget build(BuildContext context) {
    final need = ref.watch(signupNeedProvider);
    if (_ownerFlow) return OwnerOnboardingFlow(onFinished: _ownerFinished);
    switch (need) {
      case AsyncData(value: SignupNeed.ownerFirstPg):
        // Latched without a setState in build: the flag only matters for later builds.
        _ownerFlow = true;
        return OwnerOnboardingFlow(onFinished: _ownerFinished);
      case AsyncData(value: SignupNeed.tenantJoin):
        return const TenantOnboardingFlow();
      case AsyncData(value: SignupNeed.staffApplicant):
        return const StaffApplicantFlow();
      case AsyncLoading(hasValue: false):
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      default:
        // none, or a failed read: the home has its own error and empty states. Failing OPEN
        // here costs nothing — the server refuses what this gate would have hidden.
        return widget.child;
    }
  }
}
