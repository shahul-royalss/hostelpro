/// A staff sign-up until an owner accepts it (R8, docs/round3-api.md §6):
///
///     Request to join a PG as staff  →  Waiting for <PG>  →  (accepted) staff home
///
/// `stf_my_join_request` decides the stage on launch and on resume. An accepted request
/// re-reads the profile: the role is manager or warden now, and the router opens that shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/signup.dart' show JoinRequest, JoinStatus;
import '../../../data/models/staff_request.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../data/repositories/staff_request_repository.dart';
import '../../../shared/clay/clay.dart';
import '../signup_widgets.dart';
import '../tenant/find_pg_screen.dart';
import '../tenant/tenant_onboarding_flow.dart' show WaitingScreen;

enum StaffStage { checking, find, waiting }

class StaffApplicantFlow extends ConsumerStatefulWidget {
  const StaffApplicantFlow({super.key});

  @override
  ConsumerState<StaffApplicantFlow> createState() => _StaffApplicantFlowState();
}

class _StaffApplicantFlowState extends ConsumerState<StaffApplicantFlow> {
  StaffStage _stage = StaffStage.checking;
  StaffJoinRequest? _request;
  String? _pendingName;
  String? _loadError;
  bool _refreshing = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      if (_stage != StaffStage.find) _refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final request = await ref.read(staffRequestApiProvider).myRequest();
      if (!mounted) return;
      if (request?.status == StaffRequestStatus.accepted) {
        setState(() => _stage = StaffStage.checking);
        await ref.read(authControllerProvider.notifier).reload();
        return;
      }
      setState(() {
        _loadError = null;
        _request = request;
        if (request?.status == StaffRequestStatus.pending) {
          _pendingName = request!.hostelName;
          _stage = StaffStage.waiting;
        } else {
          _stage = StaffStage.find;
        }
      });
    } on SignupFailure catch (f) {
      if (!mounted) return;
      if (f.signedOut) {
        ref.read(authControllerProvider.notifier).reload();
        return;
      }
      setState(() => _loadError = f.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;
    final declined = r != null && r.status == StaffRequestStatus.declined
        ? JoinRequest(
            requestId: r.requestId,
            hostelName: r.hostelName,
            status: JoinStatus.declined,
            decisionNote: r.decisionNote,
          )
        : null;
    final api = ref.read(staffRequestApiProvider);
    final Widget page = switch (_stage) {
      StaffStage.checking => SignupPage(
          showSignOut: true,
          children: [
            const SizedBox(height: Space.huge),
            if (_loadError == null)
              const Center(child: CircularProgressIndicator())
            else
              EmptyState.error(message: _loadError!, onRetry: _refresh),
          ],
        ),
      StaffStage.find => FindPgScreen(
          key: const ValueKey('staff-find'),
          forStaff: true,
          declined: declined,
          onEditDetails: () {},
          sendRequest: (id, message) => api.requestJoin(id, message: message),
          onRequested: (name) => setState(() {
            _pendingName = name;
            _request = null;
            _stage = StaffStage.waiting;
          }),
        ),
      StaffStage.waiting => WaitingScreen(
          key: const ValueKey('staff-waiting'),
          hostelName: _pendingName ?? 'the PG',
          refreshing: _refreshing,
          error: _loadError,
          onRefresh: _refresh,
          cancel: () => api.cancel(),
          message: 'The owner chooses your role, Manager or Warden. We will let you know as '
              'soon as they answer — you can close the app.',
          onCancelled: () => setState(() {
            _request = null;
            _stage = StaffStage.find;
          }),
        ),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: page);
  }
}
