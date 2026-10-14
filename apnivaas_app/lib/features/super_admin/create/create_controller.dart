library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/models.dart';
import '../data/sa_models.dart';
import '../data/sa_repository.dart';
import '../data/sa_providers.dart';

// The four steps of "Create Owner & Hostel", as state rather than as widget fields.
//
// PORTS components/super-admin/create-wizard.tsx. Same four steps, same two modes, same
// per-step validation gate before Continue, same "jumping forward re-validates everything in
// between", same review screen with per-section edit links.
//
// ── WHY THE VALIDATION IS DUPLICATED HERE, AND WHY THAT IS NOT DUPLICATION ────────────────
//
// supabase/functions/sa-create-owner owns the rules. It is the only place that can, because it
// is the only place an attacker cannot edit: this app is an APK, and an APK is a zip file. The
// copy below exists for a different job — telling somebody that a field is blank without a
// round trip, and putting the message on the step that owns the field rather than at the
// bottom of step four.
//
// So the messages are matched to the function's WORD FOR WORD ("Enter the owner's full name",
// "Add at least one room per floor"). When the server rejects something this misses, its
// `fieldErrors` land in the same CreateWizardState.fieldErrors map under the same dotted keys,
// and the wizard cannot tell the two apart — which is exactly right, because to the person
// filling the form they are the same event.

/// One step of the wizard.
enum WizardStep {
  owner('Owner'),
  hostel('Hostel'),
  subscription('Subscription'),
  review('Review');

  const WizardStep(this.label);
  final String label;
}

/// Everything on screen, in one value.
class CreateWizardState {
  const CreateWizardState({
    required this.draft,
    this.step = 0,
    this.visited = 0,
    this.submitting = false,
    this.fieldErrors = const {},
    this.banner,
    this.result,
    this.failure,
  });

  final CreateOwnerHostelDraft draft;

  /// Which step is showing, 0–3.
  final int step;

  /// The furthest step reached. The stepper only lets you jump back to somewhere you have been,
  /// so the summary panel cannot be used to skip a validation gate.
  final int visited;

  final bool submitting;

  /// Keyed by the dotted path the Edge Function uses: 'owner.email', 'hostel.rooms',
  /// 'subscription.endDate'. Client-side and server-side messages share this map.
  final Map<String, String> fieldErrors;

  /// A page-level message that is not about one field — "Please fix the highlighted fields",
  /// or a conflict the server explained in a sentence.
  final String? banner;

  /// Non-null once the hostel exists. The wizard switches to its success panel and stops
  /// accepting edits.
  final CreatedHostel? result;

  /// Anything that was not about the input: offline, session ended, not permitted, a rollback
  /// report. Rendered with the console's own error card rather than as a field message.
  final AppFailure? failure;

  bool get isDone => result != null;
  WizardStep get currentStep => WizardStep.values[step];

  String? errorFor(String path) => fieldErrors[path];

  CreateWizardState copyWith({
    CreateOwnerHostelDraft? draft,
    int? step,
    int? visited,
    bool? submitting,
    Map<String, String>? fieldErrors,
    String? banner,
    bool clearBanner = false,
    CreatedHostel? result,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return CreateWizardState(
      draft: draft ?? this.draft,
      step: step ?? this.step,
      visited: visited ?? this.visited,
      submitting: submitting ?? this.submitting,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      banner: clearBanner ? null : (banner ?? this.banner),
      result: result ?? this.result,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Drives the wizard.
///
/// autoDispose: leaving the screen throws the draft away. A half-typed owner that survived a
/// back-navigation and reappeared under a different hostel would be worse than losing it.
final createWizardProvider =
    NotifierProvider.autoDispose<CreateWizardController, CreateWizardState>(
  CreateWizardController.new,
);

class CreateWizardController extends Notifier<CreateWizardState> {
  @override
  CreateWizardState build() =>
      CreateWizardState(draft: CreateOwnerHostelDraft.initial(DateTime.now()));

  // ── EDITS ────────────────────────────────────────────────────────────────

  /// Switching mode keeps both branches' fields — see [CreateOwnerHostelDraft] — and clears the
  /// owner step's errors, which belonged to the branch that is no longer showing.
  void setMode(OwnerMode mode) {
    state = state.copyWith(
      draft: state.draft.copyWith(mode: mode),
      fieldErrors: _without(state.fieldErrors, prefix: 'owner.'),
      clearBanner: true,
    );
  }

  void setOwnerName(String value) => _edit('owner.name', (d) => d.copyWith(ownerName: value));
  void setOwnerEmail(String value) => _edit('owner.email', (d) => d.copyWith(ownerEmail: value));
  void setOwnerPhone(String value) => _edit('owner.phone', (d) => d.copyWith(ownerPhone: value));

  void pickOwner(String? ownerUserId) => _edit(
        'owner.ownerUserId',
        (d) => d.copyWith(ownerUserId: ownerUserId, clearOwnerUserId: ownerUserId == null),
      );

  void setHostelName(String value) => _edit('hostel.name', (d) => d.copyWith(hostelName: value));
  void setFloors(int value) => _edit('hostel.floors', (d) => d.copyWith(floors: value));
  void setRooms(int value) => _edit('hostel.rooms', (d) => d.copyWith(rooms: value));
  void setBedsPerRoom(int value) =>
      _edit('hostel.bedsPerRoom', (d) => d.copyWith(bedsPerRoom: value));
  void setAddress(String value) => _edit('hostel.address', (d) => d.copyWith(address: value));

  /// Both dates clear BOTH date errors. "End date must be after the start date" is a message
  /// about the pair, and it is filed under `subscription.endDate` — moving the start date so
  /// that the pair is now valid must not leave the old complaint sitting under the other field.
  void setStartDate(DateTime value) => _editDates((d) => d.copyWith(startDate: value));
  void setEndDate(DateTime value) => _editDates((d) => d.copyWith(endDate: value));

  void _editDates(CreateOwnerHostelDraft Function(CreateOwnerHostelDraft) change) {
    if (state.isDone) return;
    var errors = _without(state.fieldErrors, key: 'subscription.startDate');
    errors = _without(errors, key: 'subscription.endDate');
    state = state.copyWith(
      draft: change(state.draft),
      fieldErrors: errors,
      clearBanner: true,
    );
  }

  void setNotes(String value) => _edit('subscription.notes', (d) => d.copyWith(notes: value));

  /// Null clears the amount rather than storing zero. Zero is a legal subscription price (a
  /// pilot, a comp) and must be distinguishable from "not yet entered".
  void setAmount(double? value) => _edit(
        'subscription.amount',
        (d) => d.copyWith(amount: value, clearAmount: value == null),
      );

  /// Applies an edit and clears that field's error — the message described the old value.
  void _edit(String path, CreateOwnerHostelDraft Function(CreateOwnerHostelDraft) change) {
    if (state.isDone) return;
    state = state.copyWith(
      draft: change(state.draft),
      fieldErrors: _without(state.fieldErrors, key: path),
      clearBanner: true,
    );
  }

  // ── NAVIGATION ───────────────────────────────────────────────────────────

  /// Advances if this step validates, and records how far the admin has been.
  bool next() {
    final errors = validateStep(state.step, state.draft);
    if (errors.isNotEmpty) {
      state = state.copyWith(
        fieldErrors: {...state.fieldErrors, ...errors},
        banner: 'Please fix the highlighted fields',
      );
      return false;
    }
    final next = (state.step + 1).clamp(0, WizardStep.values.length - 1);
    state = state.copyWith(
      step: next,
      visited: next > state.visited ? next : state.visited,
      clearBanner: true,
    );
    return true;
  }

  void back() {
    if (state.step == 0) return;
    state = state.copyWith(step: state.step - 1, clearBanner: true);
  }

  /// Backwards is free; forwards re-validates every step in between and stops on the first that
  /// fails, exactly as the web stepper does. Jumping past a gate is how a form gets submitted
  /// with a step nobody filled in.
  void jumpTo(int target) {
    if (state.isDone || target > state.visited) return;
    if (target <= state.step) {
      state = state.copyWith(step: target, clearBanner: true);
      return;
    }
    for (var i = state.step; i < target; i++) {
      final errors = validateStep(i, state.draft);
      if (errors.isNotEmpty) {
        state = state.copyWith(
          step: i,
          fieldErrors: {...state.fieldErrors, ...errors},
          banner: 'Please fix the highlighted fields',
        );
        return;
      }
    }
    state = state.copyWith(step: target, clearBanner: true);
  }

  /// Back to an empty form, for "create another".
  void startOver() {
    state = CreateWizardState(draft: CreateOwnerHostelDraft.initial(DateTime.now()));
  }

  // ── SUBMIT ───────────────────────────────────────────────────────────────

  /// Validates all three input steps, then posts to sa-create-owner.
  ///
  /// The whole payload is checked before anything is sent, because the two halves of a create
  /// live in two systems that cannot share a transaction — the login is in GoTrue, the hostel is
  /// in Postgres. A typo caught on step four here is a typo that never leaves an auth user
  /// behind for the rollback to clean up.
  Future<void> submit() async {
    if (state.submitting || state.isDone) return;

    final errors = <String, String>{};
    for (var i = 0; i < WizardStep.review.index; i++) {
      errors.addAll(validateStep(i, state.draft));
    }
    if (errors.isNotEmpty) {
      // Land on the earliest step that has a problem rather than announcing four of them from
      // the review screen.
      final firstBad = _firstStepWithError(errors);
      state = state.copyWith(
        step: firstBad,
        fieldErrors: {...state.fieldErrors, ...errors},
        banner: 'Please fix the highlighted fields',
      );
      return;
    }

    state = state.copyWith(submitting: true, clearBanner: true, clearFailure: true);
    try {
      final outcome = await ref.read(saPlatformWritesProvider).createOwnerAndHostel(state.draft);
      switch (outcome) {
        case CreateSucceeded(:final result):
          // The owner list gained a row (new mode) or a hostel count (existing mode), and the
          // hostel lists gained a hostel. Everything that shows either is now stale.
          ref.invalidate(saOwnersProvider);
          state = state.copyWith(submitting: false, result: result);
        case CreateRejected(:final message, :final fieldErrors):
          state = state.copyWith(
            submitting: false,
            fieldErrors: {...state.fieldErrors, ...fieldErrors},
            banner: message,
            step: fieldErrors.isEmpty ? state.step : _firstStepWithError(fieldErrors),
          );
      }
    } catch (error) {
      state = state.copyWith(submitting: false, failure: AppFailure.from(error));
    }
  }

  static int _firstStepWithError(Map<String, String> errors) {
    if (errors.keys.any((k) => k.startsWith('owner.'))) return WizardStep.owner.index;
    if (errors.keys.any((k) => k.startsWith('hostel.'))) return WizardStep.hostel.index;
    if (errors.keys.any((k) => k.startsWith('subscription.'))) {
      return WizardStep.subscription.index;
    }
    return WizardStep.review.index;
  }

  static Map<String, String> _without(
    Map<String, String> errors, {
    String? key,
    String? prefix,
  }) {
    if (errors.isEmpty) return errors;
    return {
      for (final entry in errors.entries)
        if (entry.key != key && (prefix == null || !entry.key.startsWith(prefix)))
          entry.key: entry.value,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATION
//
// Top-level and pure, so it is testable without a widget, a container or a network. The
// messages match supabase/functions/sa-create-owner and lib/validators/super-admin.ts word for
// word — the web form and this one reject the same input for the same reason.
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _phoneShape = RegExp(r'^[\d\s+\-()]+$');

/// Everything wrong with one step, keyed by the dotted path the Edge Function uses.
Map<String, String> validateStep(int step, CreateOwnerHostelDraft draft) =>
    switch (WizardStep.values[step]) {
      WizardStep.owner => validateOwner(draft),
      WizardStep.hostel => validateHostel(draft),
      WizardStep.subscription => validateSubscription(draft),
      // The review step adds no fields of its own; submit() re-runs the three above.
      WizardStep.review => const {},
    };

Map<String, String> validateOwner(CreateOwnerHostelDraft draft) {
  final errors = <String, String>{};

  if (draft.mode == OwnerMode.existing) {
    if ((draft.ownerUserId ?? '').isEmpty) {
      errors['owner.ownerUserId'] = 'Pick an existing owner';
    }
    return errors;
  }

  final name = draft.ownerName.trim();
  if (name.length < 2) {
    errors['owner.name'] = "Enter the owner's full name";
  } else if (name.length > 120) {
    errors['owner.name'] = 'Keep this under 120 characters.';
  }

  final email = draft.ownerEmail.trim();
  if (email.isEmpty || !_email.hasMatch(email)) {
    errors['owner.email'] = 'Enter a valid email address';
  } else if (email.length > 200) {
    errors['owner.email'] = 'Keep this under 200 characters.';
  }

  final phone = draft.ownerPhone.trim();
  // 10 to 16 characters and only the separators people actually type — the same shape the
  // function accepts, so "+91 98765 43210" is not rejected here and accepted there.
  if (phone.length < 10 || phone.length > 16 || !_phoneShape.hasMatch(phone)) {
    errors['owner.phone'] = 'Enter a valid 10-digit phone number';
  }
  return errors;
}

Map<String, String> validateHostel(CreateOwnerHostelDraft draft) {
  final errors = <String, String>{};

  final name = draft.hostelName.trim();
  if (name.length < 2) {
    errors['hostel.name'] = 'Enter the hostel name';
  } else if (name.length > 120) {
    errors['hostel.name'] = 'Keep this under 120 characters.';
  }

  // The bounds are the CHECK constraints on public.hostels, not house style: floors 1–50,
  // rooms 1–5000, beds 1–12. A value outside them is refused by Postgres after the auth user
  // has already been created.
  if (draft.floors < 1 || draft.floors > 50) {
    errors['hostel.floors'] = 'Enter the number of floors';
  }
  if (draft.rooms < 1 || draft.rooms > 5000) {
    errors['hostel.rooms'] = 'Enter the number of rooms';
  } else if (draft.rooms < draft.floors) {
    // scaffold_hostel() divides rooms across floors; fewer rooms than floors leaves floors with
    // nothing on them.
    errors['hostel.rooms'] = 'Add at least one room per floor';
  }
  if (draft.bedsPerRoom < 1 || draft.bedsPerRoom > 12) {
    errors['hostel.bedsPerRoom'] = 'Enter beds per room';
  }
  if (draft.address.trim().length > 500) {
    errors['hostel.address'] = 'Keep this under 500 characters.';
  }
  return errors;
}

Map<String, String> validateSubscription(CreateOwnerHostelDraft draft) {
  final errors = <String, String>{};

  final start = DateTime(draft.startDate.year, draft.startDate.month, draft.startDate.day);
  final end = DateTime(draft.endDate.year, draft.endDate.month, draft.endDate.day);
  if (!end.isAfter(start)) {
    errors['subscription.endDate'] = 'End date must be after the start date';
  }

  final amount = draft.amount;
  if (amount == null || amount.isNaN) {
    errors['subscription.amount'] = 'Enter the amount';
  } else if (amount < 0 || amount > 99999999) {
    errors['subscription.amount'] = 'Enter the amount';
  }

  if (draft.notes.trim().length > 500) {
    errors['subscription.notes'] = 'Keep this under 500 characters.';
  }
  return errors;
}
