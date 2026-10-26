/// Find your PG — a tenant's step after Your details (docs/self-signup-onboarding-spec.md,
/// Flow 4). "PGs near you" uses the approximate position, asked for in words first; "Search by
/// name or city" needs nothing. Rows never carry an address or an owner's contact.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/device/signup_device.dart';
import '../../../data/models/signup.dart';
import '../../../data/repositories/signup_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../auth/auth_scaffold.dart';
import '../../student/pg/pg_profile_page.dart';
import '../../student/pg/pg_widgets.dart';
import '../../common/form_parts.dart';
import '../signup_widgets.dart';

class FindPgScreen extends ConsumerStatefulWidget {
  const FindPgScreen({
    super.key,
    required this.onRequested,
    required this.onEditDetails,
    this.declined,
    this.sendRequest,
    this.forStaff = false,
  });

  /// The request was sent; [String] is the PG's name for the waiting screen.
  final ValueChanged<String> onRequested;
  final VoidCallback onEditDetails;

  /// The last request, when a PG said no — its note is shown at the top.
  final JoinRequest? declined;

  /// Sends the request; defaults to the tenant's `st_request_join`.
  final Future<void> Function(String hostelId, String? message)? sendRequest;

  /// A staff applicant (R8): staff copy, and no "Your details" step.
  final bool forStaff;

  @override
  ConsumerState<FindPgScreen> createState() => _FindPgScreenState();
}

class _FindPgScreenState extends ConsumerState<FindPgScreen> {
  final _query = TextEditingController();
  List<HostelHit>? _hits;
  bool _searching = false;
  String? _note;
  String? _error;
  String? _requesting;

  /// The two refusals the fix for is on the previous step.
  static const _needsDetails = {
    'Add your phone number in Your details first.',
    'Add a profile photo before sending a request.',
  };

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _nearby() async {
    setState(() {
      _searching = true;
      _note = null;
      _error = null;
    });
    final outcome = await ref.read(deviceLocatorProvider).locate(
          explain: () => askInWords(
            context,
            title: 'Find PGs near you?',
            message: 'Apnivaas will ask your phone for your location to list PGs '
                'near you. It is used for this search only and is not saved. You can search by '
                'name or city instead.',
          ),
        );
    if (!mounted) return;
    switch (outcome) {
      case LocationFix(:final latitude, :final longitude):
        await _run(() => ref.read(signupApiProvider).nearbyHostels(latitude, longitude));
      case LocationSkipped():
        setState(() => _searching = false);
      case LocationUnavailable(:final message):
        setState(() {
          _searching = false;
          _note = message;
        });
    }
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() => _error = 'Type at least 2 letters of the PG name or city.');
      return;
    }
    setState(() {
      _searching = true;
      _note = null;
      _error = null;
    });
    await _run(() => ref.read(signupApiProvider).searchHostels(q));
  }

  Future<void> _run(Future<List<HostelHit>> Function() call) async {
    try {
      final hits = await call();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hits = hits;
      });
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = f.message;
      });
    }
  }

  Future<void> _request(HostelHit hit) async {
    final message = await showApnivaasSheet<String>(
      context: context,
      title: widget.forStaff ? 'Ask ${hit.name} to add you as staff?' : 'Ask ${hit.name} to take you in?',
      subtitle: widget.forStaff
          ? 'The owner sees your name, phone number and email.'
          : 'The owner and warden see your details, photo and documents.',
      builder: (ctx) => _RequestSheet(hostelName: hit.name, forStaff: widget.forStaff),
    );
    if (message == null || !mounted) return;
    setState(() {
      _requesting = hit.hostelId;
      _error = null;
    });
    try {
      final send = widget.sendRequest;
      if (send != null) {
        await send(hit.hostelId, message);
      } else {
        await ref.read(signupApiProvider).requestJoin(hit.hostelId, message: message);
      }
      if (!mounted) return;
      widget.onRequested(hit.name);
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _requesting = null;
        _error = f.message;
      });
    }
  }

  Future<void> _view(HostelHit hit) async {
    final go = await Navigator.of(context).push(
      PgProfilePage.route(hit.hostelId, title: hit.name, requestLabel: 'Request to join'),
    );
    if (go == true && mounted && _requesting == null) await _request(hit);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hits = _hits;
    final declined = widget.declined;
    return SignupPage(
      showSignOut: true,
      onBack: widget.forStaff ? null : widget.onEditDetails,
      children: [
        const SizedBox(height: Space.md),
        AuthHeading(
          title: widget.forStaff ? 'Request to join a PG as staff' : 'Find your PG',
          message: widget.forStaff
              ? 'Find the PG you work at and ask its owner to add you. They choose your role.'
              : 'Ask your PG to take you in. They see your request in the app.',
          icon: widget.forStaff ? ClayIcons.team : ClayIcons.gate,
        ),
        if (declined != null) ...[
          const SizedBox(height: Space.md),
          InfoBanner(
            title: '${declined.hostelName} could not take you in',
            message: declined.decisionNote ?? 'You can ask another PG.',
          ),
        ],
        const SizedBox(height: Space.md),
        OutlinedButton.icon(
          onPressed: _searching ? null : _nearby,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.near_me_rounded),
          label: const Text('PGs near you'),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _query,
          enabled: !_searching,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'Search by name or city',
            suffixIcon: IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded),
              onPressed: _searching ? null : _search,
            ),
          ),
        ),
        if (_note != null) ...[
          const SizedBox(height: Space.xs),
          FormNote(_note!, tone: FormNoteTone.warning),
        ],
        if (_error != null) ...[
          const SizedBox(height: Space.xs),
          FormNote(_error!),
          if (!widget.forStaff && _needsDetails.contains(_error))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: widget.onEditDetails,
                child: const Text('Go to Your details'),
              ),
            ),
        ],
        const SizedBox(height: Space.md),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (hits != null && hits.isEmpty)
          const EmptyState(
            title: 'No PGs found',
            body: 'Try another name or city, or ask your PG which name it uses on Apnivaas.',
            icon: ClayIcons.rooms,
            compact: true,
          )
        else if (hits != null)
          for (final hit in hits) ...[
            _HitCard(
              hit: hit,
              busy: _requesting == hit.hostelId,
              onRequest: _requesting == null ? () => _request(hit) : null,
              onView: () => _view(hit),
            ),
            const SizedBox(height: Space.sm),
          ],
        if (hits == null && !_searching)
          Text(
            'Only PGs that use Apnivaas are listed.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({
    required this.hit,
    required this.busy,
    required this.onRequest,
    required this.onView,
  });

  final HostelHit hit;
  final bool busy;
  final VoidCallback? onRequest;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final kind = [hit.typeLabel, if (hit.genderLabel != null) hit.genderLabel!].join(' · ');
    return GlassCard(
      onTap: onView,
      semanticLabel: 'View ${hit.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PgLogo(path: hit.logoPath),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hit.name, style: t.textTheme.titleMedium),
                    Text(kind, style: muted),
                    if (hit.place.isNotEmpty) Text(hit.place, style: muted),
                  ],
                ),
              ),
              if (hit.distanceLabel != null) ...[
                const SizedBox(width: Space.xs),
                StatusChip(label: hit.distanceLabel!, tone: StatusTone.neutral),
              ],
            ],
          ),
          const SizedBox(height: Space.xs),
          RatingLine(average: hit.ratingAvg, count: hit.ratingCount, dense: true),
          if (hit.amenities.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            AmenityChips(amenities: hit.amenities, limit: 3),
          ],
          const SizedBox(height: Space.sm),
          BusyFilledButton(label: 'Request to join', busy: busy, onPressed: onRequest),
          Center(
            child: TextButton(onPressed: onView, child: const Text('See photos and reviews')),
          ),
        ],
      ),
    );
  }
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.hostelName, this.forStaff = false});
  final String hostelName;
  final bool forStaff;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _message,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Message (optional)',
                hintText: widget.forStaff
                    ? 'For example, your shift or who asked you to join'
                    : 'For example, your room number or move-in date',
              ),
            ),
            const SizedBox(height: Space.sm),
            BusyFilledButton(
              label: 'Send request',
              onPressed: () => Navigator.of(context).pop(_message.text),
            ),
          ],
        ),
      ),
    );
  }
}
