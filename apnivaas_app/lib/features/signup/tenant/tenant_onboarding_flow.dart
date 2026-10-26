/// A tenant's onboarding until a PG takes them in (docs/self-signup-onboarding-spec.md, Flow 4):
///
///     Your details  →  Find your PG  →  Request to join  →  Waiting for <PG> to accept
///
/// `st_my_join_request` decides where to start, on launch and again whenever the app comes
/// back to the foreground. An accepted request re-reads the profile: `users.hostel_id` is set
/// now, [SignupGate] lets go, and the tenant home opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/signup.dart';
import '../../../data/repositories/signup_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../common/form_parts.dart';
import '../signup_widgets.dart';
import 'find_pg_screen.dart';
import 'tenant_details_screen.dart';

enum TenantStage { checking, details, find, waiting }

class TenantOnboardingFlow extends ConsumerStatefulWidget {
  const TenantOnboardingFlow({super.key});

  @override
  ConsumerState<TenantOnboardingFlow> createState() => _TenantOnboardingFlowState();
}

class _TenantOnboardingFlowState extends ConsumerState<TenantOnboardingFlow> {
  TenantStage _stage = TenantStage.checking;
  JoinRequest? _request;
  String? _pendingName;
  String? _loadError;
  bool _refreshing = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // REFRESH ON RESUME: the owner usually answers while the app is closed.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (_stage == TenantStage.waiting || _stage == TenantStage.checking) _refresh();
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
      final request = await ref.read(signupApiProvider).myJoinRequest();
      if (!mounted) return;
      if (request?.status == JoinStatus.accepted) {
        // The gate releases on the re-read; keep a calm "checking" frame until it does.
        setState(() => _stage = TenantStage.checking);
        await ref.read(authControllerProvider.notifier).reload();
        return;
      }
      setState(() {
        _loadError = null;
        _request = request;
        if (request?.status == JoinStatus.pending) {
          _pendingName = request!.hostelName;
          _stage = TenantStage.waiting;
        } else if (_stage == TenantStage.checking || _stage == TenantStage.waiting) {
          // Nothing pending: a first visit starts at Your details; a request that ended while
          // we waited (declined, expired, cancelled elsewhere) goes back to the search.
          _stage = _stage == TenantStage.waiting ? TenantStage.find : TenantStage.details;
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
    final declined = _request?.status == JoinStatus.declined ? _request : null;
    final Widget page = switch (_stage) {
      TenantStage.checking => _Checking(error: _loadError, onRetry: _refresh),
      TenantStage.details => TenantDetailsScreen(
          key: const ValueKey('details'),
          onSaved: () => setState(() => _stage = TenantStage.find),
        ),
      TenantStage.find => FindPgScreen(
          key: const ValueKey('find'),
          declined: declined,
          onEditDetails: () => setState(() => _stage = TenantStage.details),
          onRequested: (name) => setState(() {
            _pendingName = name;
            _request = null;
            _stage = TenantStage.waiting;
          }),
        ),
      TenantStage.waiting => WaitingScreen(
          key: const ValueKey('waiting'),
          hostelName: _pendingName ?? 'your PG',
          refreshing: _refreshing,
          error: _loadError,
          onRefresh: _refresh,
          onCancelled: () => setState(() {
            _request = null;
            _stage = TenantStage.find;
          }),
        ),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: page);
  }
}

class _Checking extends StatelessWidget {
  const _Checking({required this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SignupPage(
      showSignOut: true,
      children: [
        const SizedBox(height: Space.huge),
        if (error == null)
          const Center(child: CircularProgressIndicator())
        else
          EmptyState.error(message: error!, onRetry: onRetry),
      ],
    );
  }
}

/// "Waiting for `PG` to accept", with Cancel.
class WaitingScreen extends ConsumerStatefulWidget {
  const WaitingScreen({
    super.key,
    required this.hostelName,
    required this.onRefresh,
    required this.onCancelled,
    this.refreshing = false,
    this.error,
    this.cancel,
    this.message,
  });

  final String hostelName;

  /// Cancels the request; defaults to the tenant's `st_cancel_join_request`.
  final Future<void> Function()? cancel;

  /// The line under the heading; a default for tenants.
  final String? message;
  final VoidCallback onRefresh;
  final VoidCallback onCancelled;
  final bool refreshing;
  final String? error;

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen> {
  bool _cancelling = false;
  String? _error;

  Future<void> _cancel() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel your request?'),
        content: Text('${widget.hostelName} will no longer see it. You can ask another PG.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      final cancel = widget.cancel;
      if (cancel != null) {
        await cancel();
      } else {
        await ref.read(signupApiProvider).cancelJoinRequest();
      }
      if (!mounted) return;
      widget.onCancelled();
    } on SignupFailure catch (f) {
      if (!mounted) return;
      // Already answered or cancelled elsewhere: re-read and follow the server.
      if (f.message == 'You have no pending request.' ||
          f.message == 'There is no pending request.') {
        widget.onRefresh();
      }
      setState(() {
        _cancelling = false;
        _error = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final error = _error ?? widget.error;
    return SignupPage(
      showSignOut: true,
      children: [
        const SizedBox(height: Space.xl),
        const Center(child: ClayIcon(ClayIcons.gate, size: ClaySize.persona)),
        const SizedBox(height: Space.lg),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            'Waiting for ${widget.hostelName} to accept',
            textAlign: TextAlign.center,
            style: t.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          widget.message ??
              'Your request has been sent. We will let you know as soon as they answer — you '
                  'can close the app.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        if (error != null) ...[const SizedBox(height: Space.sm), FormNote(error)],
        const SizedBox(height: Space.xl),
        BusyFilledButton(
          label: 'Check again',
          busy: widget.refreshing,
          onPressed: widget.refreshing || _cancelling ? null : widget.onRefresh,
        ),
        const SizedBox(height: Space.xs),
        Center(
          child: TextButton(
            onPressed: _cancelling || widget.refreshing ? null : _cancel,
            child: Text(_cancelling ? 'Cancelling…' : 'Cancel request'),
          ),
        ),
      ],
    );
  }
}
