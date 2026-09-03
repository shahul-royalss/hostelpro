library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../data/sa_models.dart';
import '../data/sa_providers.dart';
import '../sa_hostel_detail_screen.dart';
import '../widgets/sa_ui.dart';
import 'create_controller.dart';
import 'credentials_dialog.dart';

/// SA-2 — Create Owner & Hostel, native, four steps.
///
/// EDGE FUNCTION: supabase/functions/sa-create-owner.
/// Which in turn calls: auth.admin.createUser → public.users →
///                      public.sa_create_hostel_with_subscription() → public.scaffold_hostel().
///
/// ── THE TWO MODES, WHICH ARE TWO DIFFERENT PRODUCTS ──────────────────────────────────────
///
/// NEW OWNER mints a login. A temporary password comes back exactly once, and the dialog that
/// shows it cannot be dismissed until the admin confirms they have saved it.
///
/// EXISTING OWNER attaches a second hostel, with its own subscription, to an owner account that
/// already exists — Hard rule §4.1, one subscription per hostel, and an owner may hold several.
/// No login is created, so there is no password, nothing to roll back, and the owner keeps the
/// one they have. Saying so on the review step matters: an admin who expects credentials and
/// gets none will assume something failed.
///
/// ── WHY THERE IS NO BROWSER ANYWHERE IN THIS FLOW ────────────────────────────────────────
///
/// Creating a login needs the service-role key, which bypasses row-level security for the whole
/// project. An APK is a zip file, so a key compiled into one is a published key. The key lives
/// in a Deno process on Supabase; this screen sends a JSON body over HTTPS with the admin's own
/// access token attached, and the function verifies the caller's role against public.users
/// before it does anything. No WebView, no url_launcher, no redirect.
class CreateWizardScreen extends ConsumerWidget {
  const CreateWizardScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const CreateWizardScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(createWizardProvider);

    // The password dialog is presented from a listener rather than from build(), because build()
    // can run many times for one state and would stack a second dialog on the first.
    ref.listen<CreateWizardState>(createWizardProvider, (previous, next) {
      final credentials = next.result?.credentials;
      if (credentials == null) return;
      if (previous?.result != null) return;
      CredentialsDialog.show(
        context,
        credentials: credentials,
        hostelName: next.draft.hostelName,
      );
    });

    return SaPage(
      eyebrow: 'SUPER ADMIN',
      title: state.isDone ? 'Created' : 'Create owner & hostel',
      scrollable: false,
      child: state.isDone
          ? _SuccessPanel(state: state)
          : _Wizard(state: state),
    );
  }
}

class _Wizard extends ConsumerWidget {
  const _Wizard({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(createWizardProvider.notifier);

    return Column(
      children: [
        _Stepper(state: state),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xl),
            children: [
              if (state.failure != null) ...[
                SaError(error: state.failure!, onRetry: controller.submit),
                const SizedBox(height: Space.md),
              ],
              if (state.banner != null) ...[
                _Banner(message: state.banner!),
                const SizedBox(height: Space.md),
              ],
              switch (state.currentStep) {
                WizardStep.owner => _OwnerStep(state: state),
                WizardStep.hostel => _HostelStep(state: state),
                WizardStep.subscription => _SubscriptionStep(state: state),
                WizardStep.review => _ReviewStep(state: state),
              },
            ],
          ),
        ),
        _Footer(state: state),
      ],
    );
  }
}

/// Four dots and a rule. Tapping one jumps back to a step already visited; jumping forward
/// re-validates everything in between, so the stepper cannot be used to skip a gate.
class _Stepper extends ConsumerWidget {
  const _Stepper({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final controller = ref.read(createWizardProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xs),
      child: Row(
        children: [
          for (final step in WizardStep.values) ...[
            Expanded(
              child: Semantics(
                button: step.index <= state.visited,
                selected: step.index == state.step,
                label: 'Step ${step.index + 1} of 4: ${step.label}',
                child: InkWell(
                  borderRadius: Radii.rControl,
                  onTap: step.index <= state.visited
                      ? () => controller.jumpTo(step.index)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Column(
                      children: [
                        _Dot(
                          index: step.index,
                          current: state.step,
                          visited: state.visited,
                        ),
                        const SizedBox(height: Space.xxs),
                        Text(
                          step.label,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: step.index == state.step ? t.colorScheme.primary : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.current, required this.visited});
  final int index;
  final int current;
  final int visited;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final done = index < current;
    final active = index == current;
    final reachable = index <= visited;

    final color = active
        ? t.colorScheme.primary
        : done
            ? context.tones.success
            : reachable
                ? t.colorScheme.outline
                : t.colorScheme.outlineVariant;

    // The design draws the CURRENT step as a SOLID disc with the numeral knocked out of it, and
    // every other step as an outline. That contrast is the whole point of the row: at a glance
    // you should see where you are, not read four rings and work it out. A tinted wash behind an
    // outline — which is what this used to be — makes the active step the same shape as the
    // others and only slightly brighter.
    //
    // The fill is `primaryContainer`, which in this palette is the CREAM `#F5F3EE` with
    // near-black on it, not the gold and not a violet. It is the same fill as the wizard's own
    // Continue button, so the step you are on and the button that advances it are visibly the
    // same object. (An earlier version of this comment said "violet": that was the Stitch
    // palette, which this app no longer ships.)
    final filled = active;
    return Container(
      height: Space.xxl,
      width: Space.xxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? t.colorScheme.primaryContainer : Colors.transparent,
        border: filled
            ? null
            : Border.all(color: color, width: Strokes.hairline),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: IconSize.xs, color: color)
          : Text('${index + 1}',
              style: t.textTheme.labelSmall?.copyWith(
                color: filled ? t.colorScheme.onPrimaryContainer : color,
              )),
    );
  }
}

/// A page-level message — "Please fix the highlighted fields", or something the server said in
/// prose. Not an error card: it is about the form, not about a failure to reach the server.
class _Banner extends StatelessWidget {
  const _Banner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final tone = tones.warning;
    // The design's own badge recipe — a 10% fill of the tone under a full-strength hairline of
    // it (4:1576, 4:204, 4:210). It used to be 0.08 over 0.32, two alphas typed in by eye that
    // were a light-theme pair painted twice; NivoraSemantics is where the measured numbers live.
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tones.chipFill(tone),
        borderRadius: Radii.rControl,
        border: Border.all(color: tones.chipBorder(tone), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: IconSize.sm, color: tone),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(message, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — OWNER
// ─────────────────────────────────────────────────────────────────────────────

class _OwnerStep extends ConsumerWidget {
  const _OwnerStep({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(createWizardProvider.notifier);
    final mode = state.draft.mode;

    return _StepShell(
      title: 'Owner details',
      description: mode == OwnerMode.create
          ? 'The person who owns this hostel. They receive a login and set their own password '
              'the first time they sign in.'
          : 'Adds a second hostel, with its own subscription, under an owner account that '
              'already exists. No new login is created — the owner switches hostels from their '
              'own dashboard.',
      children: [
        SegmentedButton<OwnerMode>(
          segments: const [
            ButtonSegment(
              value: OwnerMode.create,
              label: Text('New owner'),
              icon: Icon(Icons.person_add_alt_rounded, size: IconSize.sm),
            ),
            ButtonSegment(
              value: OwnerMode.existing,
              label: Text('Existing owner'),
              icon: Icon(Icons.people_alt_rounded, size: IconSize.sm),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (values) => controller.setMode(values.first),
        ),
        const SizedBox(height: Space.md),
        if (mode == OwnerMode.create) ...[
          _Field(
            label: 'Full name',
            hint: 'e.g. Priya Sharma',
            initial: state.draft.ownerName,
            error: state.errorFor('owner.name'),
            onChanged: controller.setOwnerName,
            textCapitalization: TextCapitalization.words,
          ),
          _Field(
            label: 'Email address',
            hint: 'owner@example.com',
            helper: "Used as the owner's login ID",
            initial: state.draft.ownerEmail,
            error: state.errorFor('owner.email'),
            onChanged: controller.setOwnerEmail,
            keyboardType: TextInputType.emailAddress,
          ),
          _Field(
            label: 'Phone number',
            hint: '98765 43210',
            initial: state.draft.ownerPhone,
            error: state.errorFor('owner.phone'),
            onChanged: controller.setOwnerPhone,
            keyboardType: TextInputType.phone,
          ),
        ] else
          _OwnerPicker(
            selectedId: state.draft.ownerUserId,
            error: state.errorFor('owner.ownerUserId'),
            onPick: controller.pickOwner,
          ),
      ],
    );
  }
}

/// Searchable list of owner accounts. public.users, via saOwnersProvider.
///
/// Shows how many hostels each already holds, because that is the number that turns "Priya
/// Sharma" into "the Priya Sharma who already runs two of these".
class _OwnerPicker extends ConsumerStatefulWidget {
  const _OwnerPicker({required this.selectedId, required this.error, required this.onPick});

  final String? selectedId;
  final String? error;
  final ValueChanged<String?> onPick;

  @override
  ConsumerState<_OwnerPicker> createState() => _OwnerPickerState();
}

class _OwnerPickerState extends ConsumerState<_OwnerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owners = ref.watch(saOwnersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('OWNER ACCOUNT', style: t.textTheme.labelSmall),
        const SizedBox(height: Space.xs),
        saAsync<List<SaOwnerOption>>(
          owners,
          loading: () => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SaSkeletonCard(lines: 1, height: 68),
              SizedBox(height: Space.xs),
              SaSkeletonCard(lines: 1, height: 68),
            ],
          ),
          error: (e) => SaError(error: e, onRetry: () => ref.invalidate(saOwnersProvider)),
          data: (all) {
            if (all.isEmpty) {
              return SaEmpty(
                icon: Icons.person_off_rounded,
                title: 'No owner accounts yet',
                message: 'Switch to New owner to create the first one.',
                tone: NivoraDomain.people.tone,
              );
            }
            final matching = all.where((o) => o.matches(_query)).toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search by name, email or phone',
                    prefixIcon: Icon(Icons.search_rounded, size: IconSize.md),
                  ),
                ),
                const SizedBox(height: Space.xs),
                if (matching.isEmpty)
                  const SaEmpty(
                    icon: Icons.search_off_rounded,
                    title: 'No owner matches that',
                    compact: true,
                  )
                else
                  for (final owner in matching) ...[
                    _OwnerRow(
                      owner: owner,
                      selected: owner.id == widget.selectedId,
                      // An inactive owner is refused by the Edge Function with "reactivate it
                      // before adding a hostel". Saying so here saves four steps and a failure.
                      onTap: owner.isActive ? () => widget.onPick(owner.id) : null,
                    ),
                    const SizedBox(height: Space.xs),
                  ],
              ],
            );
          },
        ),
        if (widget.error != null) ...[
          const SizedBox(height: Space.xxs),
          Text(widget.error!,
              style: t.textTheme.bodySmall?.copyWith(color: context.tones.error)),
        ],
      ],
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.owner, required this.selected, required this.onTap});

  final SaOwnerOption owner;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Opacity(
      // Dim.readOnly is the design's own "you can look at this, you cannot use it" (4:1539).
      // An owner whose account is inactive is refused by the Edge Function, so the row is
      // exactly that: readable, not pickable.
      opacity: owner.isActive ? 1 : Dim.readOnly,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: Radii.rCard,
          border: Border.all(
            color: selected ? t.colorScheme.primary : Colors.transparent,
            width: selected ? Strokes.focus : 0,
          ),
        ),
        child: SaTapCard(
          onTap: onTap,
          padding: const EdgeInsets.all(Space.sm),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: IconSize.md,
                color: selected ? t.colorScheme.primary : t.colorScheme.outline,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(owner.fullName,
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      owner.email ?? owner.phone ?? 'No contact on record',
                      style: t.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              if (!owner.isActive)
                SaPill(label: 'Inactive', tone: context.tones.error)
              else
                SaPill(
                  label: owner.hostelCount == 0
                      ? 'No hostels'
                      : plural(owner.hostelCount, 'hostel'),
                  tone: context.tones.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — HOSTEL
// ─────────────────────────────────────────────────────────────────────────────

class _HostelStep extends ConsumerWidget {
  const _HostelStep({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final controller = ref.read(createWizardProvider.notifier);
    final draft = state.draft;

    return _StepShell(
      title: 'Hostel details',
      description: 'The physical layout. Only a Super Admin can change floor and room counts '
          'afterwards, and only upwards.',
      children: [
        _Field(
          label: 'Hostel name',
          hint: 'e.g. Sunny Days PG, Koramangala',
          initial: draft.hostelName,
          error: state.errorFor('hostel.name'),
          onChanged: controller.setHostelName,
          textCapitalization: TextCapitalization.words,
        ),
        _Stepper2(
          label: 'Floors',
          value: draft.floors,
          min: 1,
          max: 50,
          error: state.errorFor('hostel.floors'),
          onChanged: controller.setFloors,
        ),
        _Stepper2(
          label: 'Rooms',
          value: draft.rooms,
          min: 1,
          max: 5000,
          step: 5,
          error: state.errorFor('hostel.rooms'),
          onChanged: controller.setRooms,
        ),
        _Stepper2(
          label: 'Beds per room',
          value: draft.bedsPerRoom,
          min: 1,
          max: 12,
          error: state.errorFor('hostel.bedsPerRoom'),
          onChanged: controller.setBedsPerRoom,
        ),
        _Field(
          label: 'Address',
          hint: 'Street, area, city, PIN',
          initial: draft.address,
          error: state.errorFor('hostel.address'),
          onChanged: controller.setAddress,
          maxLines: 3,
          optional: true,
        ),
        // A plain raised surface, not a gold wash. The design tints a panel only when it is
        // saying something is WRONG — the state badges and the read-only band. This one is
        // describing what the server is about to do, which is neither good news nor bad, so it
        // gets the raised fill.
        //
        // AND A BARE GLYPH, NOT A DOMAIN PLATE. This carried a violet [DomainIcon] holding an
        // "i". An info circle is a state-ish mark, the rooms domain is otherwise apartment /
        // bed / meeting_room, and the plate said nothing the sentence beside it does not — so
        // the colour was identifying nothing. The quiet outline ink is what the same note
        // wears on the Subscriptions tab (_ReadOnlyExplainer), which is the shape a note has
        // in this app.
        FlatSurface(
          weight: GlassWeight.regular,
          borderRadius: Radii.rControl,
          padding: const EdgeInsets.all(Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: IconSize.md, color: t.colorScheme.outline),
              const SizedBox(width: Space.xs),
              Expanded(
                // Exactly what public.scaffold_hostel() will do, in the order it does it. An
                // admin who knows the rooms are numbered 101, 102… 201 does not ask the warden
                // to renumber them next week.
                child: Text(
                  'Rooms and beds are generated on creation: ${count(draft.rooms)} rooms spread '
                  'evenly across ${plural(draft.floors, 'floor')}, numbered 101, 102… 201, 202…, '
                  'with ${count(draft.bedsPerRoom)} beds each. '
                  'That is ${plural(draft.totalBeds, 'bed')} in total. The warden can fine-tune '
                  'room numbers later.',
                  style: t.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — SUBSCRIPTION
// ─────────────────────────────────────────────────────────────────────────────

class _SubscriptionStep extends ConsumerWidget {
  const _SubscriptionStep({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(createWizardProvider.notifier);
    final draft = state.draft;

    return _StepShell(
      title: 'Subscription',
      description: 'One subscription per hostel. The hostel becomes read-only after the end '
          'date until it is renewed — its staff can read everything and record nothing.',
      children: [
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Start date',
                value: draft.startDate,
                error: state.errorFor('subscription.startDate'),
                onChanged: controller.setStartDate,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _DateField(
                label: 'End date',
                value: draft.endDate,
                firstDate: draft.startDate.add(const Duration(days: 1)),
                error: state.errorFor('subscription.endDate'),
                onChanged: controller.setEndDate,
              ),
            ),
          ],
        ),
        _Field(
          label: 'Amount (₹)',
          hint: 'e.g. 24000',
          initial: draft.amount == null ? '' : draft.amount!.toStringAsFixed(0),
          error: state.errorFor('subscription.amount'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: (value) => controller.setAmount(double.tryParse(value.trim())),
        ),
        _Field(
          label: 'Notes',
          hint: 'e.g. Annual plan, paid via UPI',
          helper: 'Optional — plan name, payment reference',
          initial: draft.notes,
          error: state.errorFor('subscription.notes'),
          onChanged: controller.setNotes,
          optional: true,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 4 — REVIEW
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(createWizardProvider.notifier);
    final tones = context.tones;
    final draft = state.draft;
    final newOwner = draft.mode == OwnerMode.create;
    final reviewTone = newOwner ? tones.warning : tones.info;

    // The picked row is looked up rather than stored on the draft: the draft carries the id,
    // which is what the server needs, and the name/email shown here must come from the same
    // list the admin chose from rather than from a copy that could drift.
    SaOwnerOption? picked;

    /// What to print where the owner's name should be when the lookup came back with nothing.
    ///
    /// A DASH IS THE WRONG ANSWER HERE. This is the last screen before an owner login and a
    /// hostel are created under that account, and "—" in the Name, Email and Phone rows reads
    /// as "this owner has no name on record" rather than as "we could not re-read who this is".
    /// The list is refetched after every successful create, so a second hostel in one sitting
    /// is exactly when it is in flight.
    String? gap;
    if (!newOwner) {
      final owners = ref.watch(saOwnersProvider);
      for (final owner in owners.value ?? const <SaOwnerOption>[]) {
        if (owner.id == draft.ownerUserId) {
          picked = owner;
          break;
        }
      }
      if (picked == null) {
        gap = owners.hasValue
            ? 'Not in the owner list any more'
            : owners.hasError
                ? 'The owner list could not be read'
                : 'Still reading the owner list…';
      }
    }

    return _StepShell(
      title: 'Review & create',
      description: newOwner
          ? 'On submit Nivora creates the owner login, the hostel, its floors, rooms and beds, '
              'and the subscription.'
          : 'On submit Nivora creates the hostel, its floors, rooms and beds, and the '
              'subscription, under the selected owner.',
      children: [
        _ReviewSection(
          title: 'Owner',
          domain: NivoraDomain.people,
          onEdit: () => controller.jumpTo(WizardStep.owner.index),
          rows: newOwner
              ? [
                  ('Name', draft.ownerName),
                  ('Email (login)', draft.ownerEmail),
                  ('Phone', draft.ownerPhone),
                ]
              : [
                  ('Account', picked?.fullName ?? gap ?? '—'),
                  ('Email (login)', picked?.email ?? gap ?? '—'),
                  ('Phone', picked?.phone ?? gap ?? '—'),
                  (
                    'Hostels',
                    picked == null
                        ? (gap ?? '—')
                        : '${count(picked.hostelCount)} → ${count(picked.hostelCount + 1)} '
                            'after this',
                  ),
                ],
        ),
        _ReviewSection(
          title: 'Hostel',
          domain: NivoraDomain.rooms,
          onEdit: () => controller.jumpTo(WizardStep.hostel.index),
          rows: [
            ('Name', draft.hostelName),
            (
              'Structure',
              '${plural(draft.floors, 'floor')} · ${plural(draft.rooms, 'room')} · '
                  '${count(draft.bedsPerRoom)} beds/room'
            ),
            ('Total beds', count(draft.totalBeds)),
            ('Address', draft.address.trim().isEmpty ? '—' : draft.address.trim()),
          ],
        ),
        _ReviewSection(
          title: 'Subscription',
          domain: NivoraDomain.money,
          onEdit: () => controller.jumpTo(WizardStep.subscription.index),
          rows: [
            ('Period', '${dateLabel(draft.startDate)} → ${dateLabel(draft.endDate)}'),
            ('Amount', draft.amount == null ? '—' : money(draft.amount!)),
            ('Notes', draft.notes.trim().isEmpty ? '—' : draft.notes.trim()),
          ],
        ),
        // The design's badge recipe again — 10% fill, full-strength hairline, both from
        // NivoraSemantics. Amber when a password is about to exist for exactly one dialog;
        // the neutral info tone when nothing secret is being minted.
        Container(
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            color: tones.chipFill(reviewTone),
            borderRadius: Radii.rControl,
            border: Border.all(color: tones.chipBorder(reviewTone), width: Strokes.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                newOwner ? Icons.key_rounded : Icons.info_outline_rounded,
                size: IconSize.sm,
                color: reviewTone,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  newOwner
                      ? 'A temporary password is generated and shown ONCE after creation. It is '
                          'stored nowhere — copy it before closing the dialog.'
                      : 'No new login is created. The owner keeps their existing password and '
                          'will see a hostel switcher in their dashboard.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One block of the review, headed by the same domain plate the hostel detail screen puts on
/// its Owner / Subscription / Structure headings — so what the admin is about to create looks
/// like what they will be looking at a minute later. The plate is identity only; nothing in a
/// review block carries a state.
class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.rows,
    required this.onEdit,
    this.domain,
  });

  final String title;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  /// Which area of the product this block belongs to. Null draws no plate.
  final NivoraDomain? domain;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (domain != null) ...[
                DomainIcon(domain: domain!, size: DomainIconSize.sm),
                const SizedBox(width: Space.xs),
              ],
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: IconSize.xs),
                label: const Text('Edit'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ],
          ),
          for (final row in rows)
            SaDetailRow(label: row.$1, value: row.$2.trim().isEmpty ? '—' : row.$2),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUCCESS
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessPanel extends ConsumerWidget {
  const _SuccessPanel({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final result = state.result!;
    final controller = ref.read(createWizardProvider.notifier);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.md,
        Space.lg,
        Space.md,
        Space.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        // The design already specifies what a screen looks like when its whole job is to report
        // a state: a raised card, a caps tag in the tone, an outlined glyph, a title and a
        // support line (4:1575 / 4:1578). This is that shape, filled with what the server
        // actually created — rather than the bespoke card with a filled tick this used to be,
        // which was the only success treatment in the app that looked like nothing else in it.
        StateCard(
          badge: 'Created',
          tone: NivoraColors.success,
          child: StateBody(
            icon: Icons.check_rounded,
            tone: NivoraColors.success,
            title: '${state.draft.hostelName} is live',
            message: result.issuedLogin
                ? 'The owner login, the hostel, ${plural(state.draft.rooms, 'room')} and '
                    '${plural(state.draft.totalBeds, 'bed')} were created, along with the '
                    'first subscription.'
                : 'The hostel, ${plural(state.draft.rooms, 'room')} and '
                    '${plural(state.draft.totalBeds, 'bed')} were created under the '
                    'existing owner, along with its own subscription. No new login was issued.',
          ),
        ),
        const SizedBox(height: Space.md),
        if (result.credentials != null)
          FlatSurface(
            weight: GlassWeight.regular,
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.key_rounded, size: IconSize.md, color: context.tones.warning),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Credentials', style: t.textTheme.titleMedium),
                      const SizedBox(height: Space.xxs),
                      Text(
                        'The temporary password was shown once and is not stored anywhere. If '
                        'it was not saved, issue a new one from the owner account rather than '
                        'looking for it.',
                        style: t.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.md),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pushReplacement(
            SaHostelDetailScreen.route(result.hostelId),
          ),
          icon: const Icon(Icons.apartment_rounded, size: IconSize.sm),
          label: const Text('Open the hostel'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        const SizedBox(height: Space.xs),
        OutlinedButton.icon(
          onPressed: controller.startOver,
          icon: const Icon(Icons.add_rounded, size: IconSize.sm),
          label: const Text('Create another'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        const SizedBox(height: Space.xs),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back to the console'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIECES
// ─────────────────────────────────────────────────────────────────────────────

class _StepShell extends StatelessWidget {
  const _StepShell({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // The design gives every step its own pane — "Owner Details" and the fields under it read as
    // one object, separated from the stepper above and the action bar below. Loose text on the
    // page background made the title look like a section heading for the whole screen rather
    // than the label of this step's form.
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.textTheme.titleMedium),
          const SizedBox(height: Space.xxs),
          Text(description, style: t.textTheme.bodySmall),
          const SizedBox(height: Space.md),
          for (final (i, child) in children.indexed) ...[
            child,
            // No trailing gap after the last field: the pane's own padding closes the card.
            if (i != children.length - 1) const SizedBox(height: Space.md),
          ],
        ],
      ),
    );
  }
}

/// A labelled text field that keeps its own controller.
///
/// STATEFUL ON PURPOSE. The wizard's state is rebuilt on every keystroke, and a TextField
/// rebuilt from `TextEditingController(text: value)` moves the caret to the end of the line —
/// which makes correcting a typo in the middle of an email address impossible. The controller is
/// created once from [initial] and the state is fed from onChanged, one direction only.
class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.initial,
    required this.onChanged,
    this.hint,
    this.helper,
    this.error,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.optional = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? helper;
  final String? error;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final bool optional;
  final TextCapitalization textCapitalization;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label.toUpperCase(), style: t.textTheme.labelSmall),
            if (!widget.optional)
              Text(' *', style: t.textTheme.labelSmall?.copyWith(color: context.tones.error)),
          ],
        ),
        const SizedBox(height: Space.xxs),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          maxLines: widget.maxLines,
          textCapitalization: widget.textCapitalization,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            errorText: widget.error,
          ),
        ),
      ],
    );
  }
}

/// A number with minus and plus buttons. Named `_Stepper2` because Flutter already has a
/// `Stepper` and shadowing it in this file would be a trap for the next reader.
///
/// TYPEABLE AS WELL AS TAPPABLE: "rooms" is routinely 120, and reaching 120 by tapping plus is
/// not an interface.
class _Stepper2 extends StatefulWidget {
  const _Stepper2({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.error,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? error;
  final ValueChanged<int> onChanged;

  @override
  State<_Stepper2> createState() => _Stepper2State();
}

class _Stepper2State extends State<_Stepper2> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(_Stepper2 old) {
    super.didUpdateWidget(old);
    // The buttons change the value from outside the field, so the text has to follow them —
    // but only when it genuinely disagrees, or typing would fight the controller.
    if (widget.value != old.value && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _bump(int by) {
    final next = (widget.value + by).clamp(widget.min, widget.max);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label.toUpperCase(), style: t.textTheme.labelSmall),
            Text(' *', style: t.textTheme.labelSmall?.copyWith(color: context.tones.error)),
          ],
        ),
        const SizedBox(height: Space.xxs),
        Row(
          children: [
            IconButton.outlined(
              onPressed: widget.value > widget.min ? () => _bump(-widget.step) : null,
              icon: const Icon(Icons.remove_rounded, size: IconSize.md),
              tooltip: 'Decrease ${widget.label}',
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (raw) {
                  final parsed = int.tryParse(raw.trim());
                  // An empty box is mid-edit, not zero. Leaving the value alone lets somebody
                  // clear "10" and type "120" without the field snapping to the minimum first.
                  if (parsed == null) return;
                  widget.onChanged(parsed.clamp(widget.min, widget.max));
                },
                decoration: InputDecoration(errorText: widget.error),
              ),
            ),
            const SizedBox(width: Space.xs),
            IconButton.outlined(
              onPressed: widget.value < widget.max ? () => _bump(widget.step) : null,
              icon: const Icon(Icons.add_rounded, size: IconSize.md),
              tooltip: 'Increase ${widget.label}',
            ),
          ],
        ),
      ],
    );
  }
}

/// A date, chosen with the platform picker. No free-typed dates: the Edge Function wants
/// YYYY-MM-DD and a typed "01/02/2027" is ambiguous in exactly the country this app is for.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.error,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = firstDate ?? DateTime(2020);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: t.textTheme.labelSmall),
            Text(' *', style: t.textTheme.labelSmall?.copyWith(color: context.tones.error)),
          ],
        ),
        const SizedBox(height: Space.xxs),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value.isBefore(first) ? first : value,
              firstDate: first,
              lastDate: DateTime(DateTime.now().year + 10),
            );
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(Icons.calendar_today_rounded, size: IconSize.sm),
          label: Text(dateLabel(value)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            alignment: Alignment.centerLeft,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: Space.xxs),
          Text(error!, style: t.textTheme.bodySmall?.copyWith(color: context.tones.error)),
        ],
      ],
    );
  }
}

/// Back / Continue, or Back / Create on the last step.
class _Footer extends ConsumerWidget {
  const _Footer({required this.state});
  final CreateWizardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final controller = ref.read(createWizardProvider.notifier);
    final last = state.currentStep == WizardStep.review;
    final newOwner = state.draft.mode == OwnerMode.create;

    return Container(
      padding: EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        Space.sm + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(top: BorderSide(color: t.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: state.step == 0 || state.submitting ? null : controller.back,
            icon: const Icon(Icons.arrow_back_rounded, size: IconSize.sm),
            label: const Text('Back'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
          const Spacer(),
          if (last)
            FilledButton.icon(
              onPressed: state.submitting ? null : controller.submit,
              icon: state.submitting
                  ? const SizedBox(
                      height: IconSize.md,
                      width: IconSize.md,
                      child: CircularProgressIndicator(strokeWidth: Strokes.glyph),
                    )
                  : const Icon(Icons.check_rounded, size: IconSize.sm),
              label: Text(newOwner ? 'Create owner & hostel' : 'Create hostel'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            )
          else
            FilledButton.icon(
              onPressed: controller.next,
              icon: const Icon(Icons.arrow_forward_rounded, size: IconSize.sm),
              label: const Text('Continue'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
        ],
      ),
    );
  }
}
