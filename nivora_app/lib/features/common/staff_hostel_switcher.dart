/// Which PG a warden or manager is working in, and moving to another one. Shared by both roles.
///
/// ── WHAT CHANGED UNDERNEATH ──────────────────────────────────────────────────────────────
///
/// An owner with two or more PGs can now give one warden or manager access to several of them
/// (`public.staff_hostel_access`). `users.hostel_id` did NOT become a list: it is still the one
/// PG the person is working in right now, every RLS policy still reads it through
/// `app.user_hostel_id()`, and so a warden still sees exactly one PG at a time. Switching is
/// `public.staff_switch_hostel()` moving that column to another PG they are allowed into.
///
/// That design is what keeps the live Android build working: it has no switcher, and it goes
/// on showing whichever PG the column points at, exactly as it always did.
///
/// ── WHAT THIS FILE DRAWS, AND FOR WHOM ───────────────────────────────────────────────────
///
/// [StaffHostelBar] names the PG at the top of the warden's and the manager's home screen.
/// Until now neither said which PG it was showing (the masthead carries the greeting, not the
/// property), which did not matter while the answer could only ever be one PG. It adds a
/// Switch PG control ONLY for somebody with two or more; a warden with one PG sees the name and
/// nothing else, because a switcher with one choice in it is furniture.
///
/// ── WHY THE SESSION IS RE-READ, AND WHY THAT READ MAY NOT FAIL QUIETLY ───────────────────
///
/// Every screen keys its reads off the session's copy of `users.hostel_id`. After the RPC has
/// moved the column, the app is showing one PG while RLS answers for another, and every list
/// comes back empty, which looks exactly like a PG with nothing in it. So a switch is not done
/// until the session has been republished with the new id, and [switchStaffHostel] uses
/// `AuthController.republish`, which throws, rather than `reload`, which swallows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';

/// Moves the signed-in warden or manager to [hostelId], then republishes the session with it.
///
/// Returns the PG the server now has them working in, or null when the account turned out to
/// be signed out (deactivated in the meantime), in which case the router is already leaving.
/// Throws [AppFailure] with a sentence fit to show.
///
/// A [ProviderContainer], not a WidgetRef, for the reason `refreshOwnerBuilding` gives: the
/// republish rebuilds the shell underneath the sheet that asked, and a WidgetRef must not be
/// what the last step depends on. Capture it with `ProviderScope.containerOf(context, listen:
/// false)` before the first await.
///
/// ── THE THREE STEPS, AND WHAT A FAILURE IN EACH MEANS ────────────────────────────────────
///
///  1. The RPC. A refusal here changed nothing, and its message is the server's own
///     ('You do not have access to that PG.'), passed through verbatim.
///  2. The republish. A failure here is the one that must be said honestly: the server HAS
///     moved the person, so "that did not work" would be false. The sentence says what happened
///     and what to do, and doing it is safe because step 1 is a no-op the second time.
///  3. The unkeyed reads. Everything keyed by hostel id follows the new session on its own;
///     these two resolve the PG on the server and name none, so they are thrown away here.
///     Both also watch the session's hostel id, which covers every other path that moves it.
Future<String?> switchStaffHostel(ProviderContainer container, String hostelId) async {
  await container.read(staffHostelAccessProvider).switchTo(hostelId);

  final AuthPhase phase;
  try {
    phase = await container.read(authControllerProvider.notifier).republish();
  } catch (error) {
    final failure = AppFailure.from(error);
    // A dead session is its own, better-known sentence: there is nothing to retry until the
    // person signs in again, and saying "tap it again" would send them round in a circle.
    if (failure is SessionExpiredFailure || failure is SignedOutFailure) throw failure;
    throw ServerFailure(
      'Your PG was changed, but Nivora could not reload it. Check your connection and tap the '
      'PG again.',
      technical: 'staff_switch_hostel succeeded; the session re-read after it failed: $error',
    );
  }

  container.invalidate(hostelContactsProvider);
  container.invalidate(myStaffHostelsProvider);
  return phase is AuthSignedIn ? phase.session.hostelId : null;
}

/// Opens the switch sheet and, when a switch lands, says where the person is now.
///
/// The messenger is captured BEFORE the sheet opens. A successful switch rebuilds the whole
/// shell for the new PG, so the screen whose context opened the sheet is gone by the time
/// there is anything to say; the app-level messenger is not.
Future<void> openStaffHostelSwitcher(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  // A fresh list each time the sheet opens, drawn over the held one so nothing flickers. PGs
  // granted or taken away since the last read show up, and `is_active` is the server's word,
  // which is what lets [_StaffHostelSheetState._choose] notice a PG that moved elsewhere.
  ProviderScope.containerOf(context, listen: false).invalidate(myStaffHostelsProvider);
  final name = await showGlassSheet<String>(
    context: context,
    builder: (_) => const StaffHostelSheet(),
  );
  if (name == null) return;
  messenger.showSnackBar(
    SnackBar(content: Text('Now working in $name'), behavior: SnackBarBehavior.floating),
  );
}

/// The PG this home screen belongs to, and the way to another one when there is one.
///
/// Drawn in the owner dashboard's shape (`_HostelSwitcher` in owner_dashboard_screen.dart): a
/// brand dot, the PG in `title` weight, and a hairline under it that makes it read as the
/// scope of everything below rather than as the first row of the page.
///
/// THE NAME COMES FROM WHICHEVER READ HAS IT. The access list names every PG the person may
/// work in; the hostel row (which both home screens already watch, so this costs nothing) names
/// the current one. Either is enough, and a failed access list must not cost the warden the
/// name of the PG they are standing in.
class StaffHostelBar extends ConsumerWidget {
  const StaffHostelBar({super.key, required this.hostelId});

  /// The session's current PG, as the home screen resolved it.
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final hostels = ref.watch(myStaffHostelsProvider).value ?? const <StaffHostel>[];
    String? name;
    for (final h in hostels) {
      if (h.hostelId == hostelId) name = h.name;
    }
    name ??= ref.watch(hostelProvider(hostelId)).value?.name;
    final several = hostels.length >= 2;

    // A FRESH LIST THAT DISAGREES WITH THE SESSION MEANS THE SESSION IS STALE. `is_active` is
    // the server's `users.hostel_id` as of this read, and [hostelId] is the session's copy. They
    // part when the PG moved without this device moving it: an owner took this PG away (the
    // server moves them to another one) or a switch on another device, while this app stayed
    // open, so the resume check never ran. The list is refetched on every pull to refresh and
    // every time the switch sheet opens, so those are when this catches it. The re-read
    // republishes only if the PG really moved, and
    // the rebuilt list then agrees, so this cannot repeat. Only a SETTLED answer counts: while a
    // refetch is in flight (straight after a switch here, say) the value is the previous list,
    // which is stale by definition. The session is read at the moment of the answer, not taken
    // from [hostelId]: a republish can land before this widget has rebuilt with the new id.
    ref.listen(myStaffHostelsProvider, (_, next) {
      if (next.isLoading || next.hasError) return;
      final session = ref.read(currentHostelIdProvider);
      for (final h in next.value ?? const <StaffHostel>[]) {
        if (h.isActive && h.hostelId != session) {
          ref.read(authControllerProvider.notifier).syncActiveHostel();
          return;
        }
      }
    });

    final label = Row(
      children: [
        // The owner header's brand dot. Decorative, so it is hidden from the semantics tree.
        ExcludeSemantics(
          child: Container(
            width: Space.xs,
            height: Space.xs,
            decoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: Space.xs),
        Flexible(
          child: name == null
              // A plain bar while both reads are in flight: the same footprint as the name, so
              // the page does not jump when it lands, and no invented "Your PG" in its place.
              ? Container(
                  width: 160,
                  height: IconSize.md,
                  decoration: BoxDecoration(
                    color: t.colorScheme.outlineVariant,
                    borderRadius: Radii.rTiny,
                  ),
                )
              : Text(
                  name,
                  style: t.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: name == null ? 'Loading your PG' : 'Current PG: $name',
                container: true,
                excludeSemantics: true,
                child: label,
              ),
            ),
            if (several) ...[
              const SizedBox(width: Space.xs),
              // A named button rather than a chevron on the name: "Switch PG" says what it does
              // to somebody who has never seen it, and it is a 44dp target on its own.
              TextButton.icon(
                onPressed: () => openStaffHostelSwitcher(context),
                icon: const Icon(Icons.swap_horiz_rounded, size: IconSize.lg),
                label: const Text('Switch PG'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ],
          ],
        ),
        SizedBox(height: several ? Space.xxs : Space.sm),
        Divider(
          color: t.colorScheme.outlineVariant,
          height: Strokes.hairline,
          thickness: Strokes.hairline,
        ),
      ],
    );
  }
}

/// The list of PGs a warden or manager may work in, with the current one marked.
///
/// PUBLIC so the tests can pump it on its own. Returns the NAME of the PG the person is now
/// working in when a switch lands, and null when they close it.
///
/// ── THE BUSY STATE IS THE WHOLE SHEET, NOT ONE ROW ───────────────────────────────────────
///
/// While a switch is in flight every row is inert and the sheet cannot be dragged away. A
/// second tap on another PG would race the first to `users.hostel_id`, and whichever landed
/// last would win on the server while the app republished whichever answered first.
class StaffHostelSheet extends ConsumerStatefulWidget {
  const StaffHostelSheet({super.key});

  @override
  ConsumerState<StaffHostelSheet> createState() => _StaffHostelSheetState();
}

class _StaffHostelSheetState extends ConsumerState<StaffHostelSheet> {
  /// The PG being switched to, while the request is in flight.
  String? _switching;

  /// Why the last attempt did not finish. Cleared by the next tap, and read when the sheet is
  /// closed (see the PopScope in [build]).
  String? _error;

  Future<void> _choose(StaffHostel target, List<StaffHostel> all, String? current) async {
    if (_switching != null) return;
    // Already here, and the server agrees: nothing to do. Both halves are checked because they
    // can disagree after a switch on another device, and tapping the PG the screens show must
    // then bring the server back to it rather than close over a mismatch.
    //
    // NEVER AFTER A FAILED ATTEMPT. When the move landed and the reload did not, nothing has
    // refetched the list, so it still marks the PG on screen as active while the server has
    // already moved. Closing here would leave the screens on one PG and RLS on another. Going
    // through the switch moves the server back and republishes; in every other case it is one
    // round trip the server answers without writing anything.
    if (_error == null && target.hostelId == current && target.isActive) {
      Navigator.of(context).pop();
      return;
    }

    // Captured before the first await; see [switchStaffHostel].
    final container = ProviderScope.containerOf(context, listen: false);
    final names = {for (final h in all) h.hostelId: h.name};
    setState(() {
      _switching = target.hostelId;
      _error = null;
    });

    try {
      final now = await switchStaffHostel(container, target.hostelId);
      if (!mounted) return;
      // Null means the account is no longer signed in; the router is taking it to the sign-in
      // screen, and a "Now working in" line over that would be a sentence about nothing.
      Navigator.of(context).pop(now == null ? null : names[now] ?? target.name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _switching = null;
        _error = AppFailure.from(error).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final hostels = ref.watch(myStaffHostelsProvider);
    final current = ref.watch(currentHostelIdProvider);
    final busy = _switching != null;
    final media = MediaQuery.of(context);

    return PopScope(
      canPop: !busy,
      // CLOSING OVER A FAILED ATTEMPT ASKS THE SERVER ONCE WHICH PG THIS IS. The failure that
      // matters is the one where the move landed and the reload did not: the sheet says "tap the
      // PG again", but a person who drags it away instead would be left with every screen keyed
      // to the old PG while RLS answers for the new one, until the next resume or pull to
      // refresh. `syncActiveHostel` is one read of their own row, republishes only if the PG
      // really moved, and never throws, so after a plain refusal it costs a read and changes
      // nothing. A pop that carries a result is a switch that landed, and a pop with no error
      // outstanding is somebody closing an untouched sheet; neither needs asking.
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || result != null || _error == null) return;
        ref.read(authControllerProvider.notifier).syncActiveHostel();
      },
      // A transparent Material between the glass pane and the rows. ListTile paints its ink on
      // the nearest Material, and the pane is a DecoratedBox with a fill: without this layer the
      // ripple would be drawn underneath the pane, where nobody can see it.
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8 - media.padding.top),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Switch PG', style: t.textTheme.titleLarge),
                const SizedBox(height: Space.xxs),
                // The one surprising fact, said before the choice rather than after it:
                // users.hostel_id is shared by every device this account is signed in on.
                Text(
                  'Choose the PG you are working in. Your other devices will switch too.',
                  style: t.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.sm),
                ...switch (hostels) {
                  AsyncValue(:final value?) => [
                    for (final h in value)
                      _HostelChoice(
                        hostel: h,
                        current: h.hostelId == current,
                        switching: _switching == h.hostelId,
                        enabled: !busy,
                        onTap: () => _choose(h, value, current),
                      ),
                  ],
                  AsyncValue(:final error?) => [
                    Text(
                      AppFailure.from(error).message,
                      style: t.textTheme.bodyMedium?.copyWith(color: tones.error),
                    ),
                    const SizedBox(height: Space.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => ref.invalidate(myStaffHostelsProvider),
                        child: const Text('Try again'),
                      ),
                    ),
                  ],
                  _ => [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Space.lg),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                },
                if (_error != null) ...[
                  const SizedBox(height: Space.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: t.textTheme.bodyMedium?.copyWith(color: tones.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One PG in the switch sheet: a radio for "this is where you are", the name, and where it is.
class _HostelChoice extends StatelessWidget {
  const _HostelChoice({
    required this.hostel,
    required this.current,
    required this.switching,
    required this.enabled,
    required this.onTap,
  });

  final StaffHostel hostel;

  /// The PG every screen is showing now.
  final bool current;

  /// This is the PG a switch is in flight to.
  final bool switching;

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = hostel.status;
    // A suspended or read-only PG is still one the person may work in, and the server decides
    // whether switching into it is allowed. Saying so here saves a surprise on the far side.
    final detail = status != null && status != HostelStatus.active
        ? status.label
        : (hostel.address?.trim().isNotEmpty ?? false)
        ? hostel.address!.trim()
        : null;

    return Semantics(
      button: true,
      selected: current,
      enabled: enabled,
      label: current ? '${hostel.name}, current PG' : hostel.name,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: enabled,
        minTileHeight: 56,
        leading: Icon(
          current ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
          color: current ? t.colorScheme.primary : t.colorScheme.outline,
        ),
        title: Text(hostel.name, style: t.textTheme.titleMedium),
        subtitle: detail == null
            ? null
            : Text(
                detail,
                style: t.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: switching
            ? SizedBox.square(
                dimension: IconSize.lg,
                child: CircularProgressIndicator(strokeWidth: Strokes.glyph),
              )
            : current
            ? Text('Current', style: t.textTheme.labelMedium)
            : null,
        onTap: onTap,
      ),
    );
  }
}
