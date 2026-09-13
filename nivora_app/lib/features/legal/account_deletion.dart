library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../../shared/glass/glass.dart';
import 'legal_documents.dart';

/// "Delete my account and data" — the in-app half of Google Play's account deletion requirement.
///
/// ── WHY IT IS OWED ────────────────────────────────────────────────────────────────────────
///
/// Play's User Data policy: where an account can be created inside an app, the app must offer an
/// in-app path to request its deletion AND a web link. In Nivora an owner creates staff and a
/// warden registers residents, both inside the app, so both halves are owed. The web link has
/// existed for a while (/legal/account-deletion). This screen is the half the app was missing.
///
/// ── IT FILES A REQUEST, IT DELETES NOTHING ────────────────────────────────────────────────
///
/// Nobody in this product holds a delete privilege on their own record, deliberately. A
/// resident's fee ledger cascades from their row, so a self-service delete would destroy records
/// the hostel is legally required to keep; and "erase my data", sent by somebody who is not the
/// person it names, is an attack on that person. So the request goes to the people who can act on
/// it, who confirm identity in person first. That is the same flow the website runs.
///
/// ── IT AGREES WITH THE WEBSITE ABOUT WHAT IS "ON FILE" ────────────────────────────────────
///
/// public.request_account_deletion() writes the same audit_log action the web's server action
/// writes, and public.my_account_deletion_request() reads it back. A request filed on either
/// surface therefore shows as sent on both, and a second tap inside 30 days returns the first
/// request rather than filing another.
///
/// ── NOTHING HERE OPENS A BROWSER ──────────────────────────────────────────────────────────
///
/// The public deletion page is printed as selectable text, the same way LegalScreen prints the
/// published policy. It is there for somebody who has lost access to the app, not as a route out
/// of it.

/// What the server says once a request is on file.
class DeletionRequestReceipt {
  const DeletionRequestReceipt({
    required this.requestedAt,
    required this.alreadyPending,
    required this.notified,
  });

  final DateTime requestedAt;

  /// True when a request was already on file, so this call filed nothing new.
  final bool alreadyPending;

  /// How many staff inboxes it reached. Zero on a fresh request means a person must be told.
  final int notified;
}

/// The store the screen talks through. An interface so widget tests need no network.
abstract interface class AccountDeletionStore {
  /// When the signed-in user's request still on file was made, or null.
  Future<DateTime?> pendingRequest();

  /// File a request. [hostelId] only matters for an owner with several hostels.
  Future<DeletionRequestReceipt> request({String? reason, String? hostelId});
}

final class AccountDeletionRepository extends Repository implements AccountDeletionStore {
  const AccountDeletionRepository(super.db);

  @override
  Future<DateTime?> pendingRequest() => guard(() async {
        requireLiveSession('my_account_deletion_request');
        final result = await db.rpc('my_account_deletion_request');
        return result is String ? DateTime.tryParse(result)?.toLocal() : null;
      });

  @override
  Future<DeletionRequestReceipt> request({String? reason, String? hostelId}) =>
      // `guard`, not `guardWrite`: the RPC is idempotent for 30 days — a repeat returns the
      // request already on file and writes nothing — so a timeout is safe to retry and must not
      // be reported as "we cannot tell whether that worked".
      guard(() async {
        requireLiveSession('request_account_deletion');
        final trimmed = reason?.trim() ?? '';
        final result = await db.rpc('request_account_deletion', params: {
          'p_reason': trimmed.isEmpty ? null : trimmed,
          'p_hostel_id': hostelId,
        });
        final map = result is Map ? result : const <String, dynamic>{};
        final at = map['requested_at'];
        return DeletionRequestReceipt(
          requestedAt: (at is String ? DateTime.tryParse(at)?.toLocal() : null) ?? DateTime.now(),
          alreadyPending: map['already_pending'] == true,
          notified: (map['notified'] as num?)?.toInt() ?? 0,
        );
      });
}

final accountDeletionStoreProvider = Provider<AccountDeletionStore>(
  (ref) => AccountDeletionRepository(ref.watch(supabaseClientProvider)),
);

/// The signed-in user's request still on file. Keyed off the session so signing in as somebody
/// else asks again.
final pendingDeletionRequestProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.watch(accountDeletionStoreProvider).pendingRequest();
});

void openAccountDeletion(BuildContext context) {
  Navigator.of(context).push(AccountDeletionScreen.route());
}

/// The longest reason the server accepts. Enforced here too, so the limit is met while typing
/// rather than discovered on send.
const kDeletionReasonMax = 500;

class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const AccountDeletionScreen());

  @override
  ConsumerState<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  final _reason = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;
  DateTime? _filedAt;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = ref.read(accountDeletionStoreProvider);
    final hostelId = ref.read(currentHostelIdProvider);
    try {
      final receipt = await store.request(reason: _reason.text, hostelId: hostelId);
      if (!mounted) return;
      setState(() {
        _filedAt = receipt.requestedAt;
        _busy = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'That did not go through. Please try again.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final role = ref.watch(sessionProvider)?.role;
    final pending = ref.watch(pendingDeletionRequestProvider);
    final filedAt = _filedAt ?? pending.value;
    final checking = pending.isLoading && _filedAt == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Delete my account and data', style: t.textTheme.titleLarge),
            const SizedBox(height: Space.sm),
            Text(_explanation(role), style: t.textTheme.bodyMedium),
            const SizedBox(height: Space.md),
            FlatSurface(
              padding: const EdgeInsets.all(Space.md),
              child: Text(_whatIsKept(role), style: t.textTheme.bodySmall),
            ),
            const SizedBox(height: Space.lg),
            if (checking)
              const Center(child: CircularProgressIndicator())
            else if (filedAt != null)
              _Sent(filedAt: filedAt, who: _whoActions(role))
            else ...[
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: kDeletionReasonMax,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
              const SizedBox(height: Space.xs),
              CheckboxListTile(
                value: _confirmed,
                onChanged: _busy ? null : (v) => setState(() => _confirmed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I understand this asks for my account and personal data to be erased.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.xs),
                Text(_error!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.error)),
              ],
              const SizedBox(height: Space.md),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: t.colorScheme.error,
                  foregroundColor: t.colorScheme.onError,
                ),
                onPressed: _confirmed && !_busy ? _send : null,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: IconSize.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: const Text('Send deletion request'),
              ),
            ],
            const SizedBox(height: Space.xl),
            FlatSurface(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account deletion page', style: t.textTheme.labelSmall),
                  const SizedBox(height: Space.xxs),
                  const SelectableText(kDeletionUrl),
                  const SizedBox(height: Space.xxs),
                  Text(
                    'For anyone who no longer has the app. It works without signing in, and '
                    'explains exactly what is erased and what the hostel must keep.',
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sent extends StatelessWidget {
  const _Sent({required this.filedAt, required this.who});

  final DateTime filedAt;
  final String who;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: IconSize.md, color: t.colorScheme.primary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Request sent on ${deletionDayLabel(filedAt)}. $who, and will speak to you to '
              'confirm it is really you before anything is erased. If nobody has been in touch '
              'within 30 days, use the contact details on the account deletion page below.',
              style: t.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _explanation(UserRole? role) => switch (role) {
      UserRole.student =>
        'Your hostel registered this account, so deletion is handled as a verified request. '
            'Your warden and hostel owner are told, they confirm it is really you, and your '
            'personal details, photo and ID proof are then erased.',
      UserRole.owner =>
        'Your account was set up by the platform administrator, so deletion is handled as a '
            'verified request. The administrator is told, confirms it is really you, and then '
            'removes the account and your personal details.',
      _ =>
        'Your hostel owner created this account, so deletion is handled as a verified request. '
            'They are told, they confirm it is really you, and the account and your personal '
            'details are then removed.',
    };

String _whatIsKept(UserRole? role) => switch (role) {
      UserRole.student =>
        'Fee and payment records are kept even after your details are erased — the hostel has '
            'an accounting duty it cannot waive. Your name is removed from them instead.',
      _ =>
        'Some records the hostel is required to keep for its accounts are retained after an '
            'account is removed. The account deletion page below sets out exactly what, and for '
            'how long.',
    };

String _whoActions(UserRole? role) => switch (role) {
      UserRole.student => 'Your warden and hostel owner have it',
      UserRole.owner => 'The platform administrator has it',
      _ => 'Your hostel owner has it',
    };

/// "13 Sep 2026". Local to this screen; the student feature's formatters are scoped to it.
String deletionDayLabel(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
