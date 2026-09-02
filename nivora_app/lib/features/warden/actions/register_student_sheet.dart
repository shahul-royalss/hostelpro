library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart' show studentLoginDomain;
import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../data/warden_providers.dart';
import '../data/warden_repository.dart';
import '../widgets/warden_ui.dart';
import 'assign_bed_sheet.dart';
import 'sheet_scaffold.dart';
import 'student_credentials_dialog.dart';

/// Register a resident — roster row, bed, fee ledger AND the login they sign in with.
///
/// ── WHAT THIS SCREEN PROMISES, AND WHY THAT CHANGED ──────────────────────────────────────
///
/// It used to end with a notice saying an app login "has to be issued from the web console".
/// That was true when it was written — minting an auth user needs the service-role key, which
/// can never be inside an APK — and it is not true any more. `warden-register-student` holds
/// that key on the server, and [WardenRepository.registerStudent] posts to it. The resident is
/// created, placed in a bed and given a login in ONE server-side operation, and the temporary
/// password comes back once, in [StudentCredentialsDialog]. Nothing on this path opens a
/// browser.
///
/// ── AND WHY THE FORM IS LONGER THAN IT WAS ───────────────────────────────────────────────
///
/// The old form required only what public.students declares NOT NULL — name, phone, rent — on
/// the reasoning that a warden registering someone at the door should not be blocked by a
/// missing address. The Edge Function is stricter, and it is the authority now: guardian name
/// and phone, the permanent address, an ID proof TYPE and an ID proof FILE, and a bed are all
/// mandatory there (spec §6.4 step 3). A form that let them be skipped would collect a page of
/// answers and then be refused by the server, which is worse than asking up front.
///
/// The bed is required for a second reason of its own: it travels in the SAME call, so a
/// resident who exists but is nowhere is not a state this flow can produce.
///
/// ── WHICH BOX BECOMES THE LOGIN ──────────────────────────────────────────────────────────
///
/// The email box is the one thing here that is optional AND consequential. If it is filled in,
/// that address is the resident's login id; if it is blank, their phone number is, mapped to
/// the synthetic address in [studentLoginDomain]. There is no third state where both work:
/// answering "which account owns this phone number?" at sign-in would need a lookup on an
/// unauthenticated endpoint, and that is an enumeration oracle over a population of young
/// residents. One account, one login id, printed on the credentials screen.
///
/// It stays optional because a hostel resident may genuinely not have an email — the phone
/// mapping exists for exactly that person — and a mandatory box would be answered with an
/// invented address, which GoTrue would then hold forever.
///
/// ── EVERY MESSAGE HERE IS THE SERVER'S OWN ───────────────────────────────────────────────
///
/// The validation below duplicates supabase/functions/warden-register-student/index.ts field
/// for field and message for message. That is not duplication for its own sake: the function
/// owns the rules — it is the only copy an attacker cannot edit — and this copy exists to say
/// "the guardian's name is blank" without a round trip and 4 MB of upload. When the server
/// rejects something this misses, its `fieldErrors` land in the same map under the same keys and
/// the form cannot tell the two apart, which is right: to the warden they are the same event.
Future<bool?> showRegisterStudentSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _RegisterStudentSheet(hostelId: hostelId),
  );
}

class _RegisterStudentSheet extends ConsumerStatefulWidget {
  const _RegisterStudentSheet({required this.hostelId});

  /// ONLY scopes the free-bed picker. It is NOT sent to the server and could not be: the
  /// function takes no hostel id at all and uses the warden's own users.hostel_id, so there is
  /// nothing here to get wrong or to abuse.
  final String hostelId;

  @override
  ConsumerState<_RegisterStudentSheet> createState() => _RegisterStudentSheetState();
}

class _RegisterStudentSheetState extends ConsumerState<_RegisterStudentSheet> {
  final _form = GlobalKey<FormState>();

  /// One key per text field, so [_clear] can re-run ONE validator.
  ///
  /// A TextFormField holds the message its validator last produced until something asks it to
  /// validate again — dropping the entry from [_errors] is not enough on its own, and the
  /// warden would retype the phone number with "already has an account" still sitting under it.
  /// Validating the whole form instead would light up every other empty box the moment somebody
  /// starts typing in the first one.
  final _fieldKeys = <String, GlobalKey<FormFieldState<String>>>{
    for (final key in [
      'fullName',
      'phone',
      'monthlyFee',
      'guardianName',
      'guardianPhone',
      'permanentAddress',
      'email',
    ])
      key: GlobalKey<FormFieldState<String>>(),
  };

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _fee = TextEditingController();
  final _guardianName = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  DateTime _joining = DateTime.now();
  String? _bedId;
  String? _bedLabel;
  IdProofType? _idProofType;
  CapturedDocument? _idProof;
  CapturedDocument? _photo;
  bool _busy = false;

  /// Whether the email box currently holds anything.
  ///
  /// Not cosmetic: an email, when there is one, IS the login id, and the phone number is not.
  /// The helper text under both boxes has to move with this or the warden reads the form off
  /// the screen and hands the resident the wrong half of their credentials.
  bool _hasEmail = false;

  /// Field messages, keyed by the flat names index.ts uses — 'fullName', 'phone', 'bedId',
  /// 'idProofType', 'idProof', 'photo'. ONE MAP for both sources: what this form worked out on
  /// its own and what the server sent back are the same kind of thing to the person reading it.
  Map<String, String> _errors = const {};

  /// A refusal that is not about any one field. Rendered over the button rather than under a
  /// control it may not belong to.
  String? _banner;

  @override
  void dispose() {
    for (final c in [_name, _phone, _fee, _guardianName, _guardianPhone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── ERRORS ─────────────────────────────────────────────────────────────────

  /// Drops one field's message, because the value it described has just changed.
  void _clear(String key) {
    if (!_errors.containsKey(key)) return;
    setState(() => _errors = {
          for (final e in _errors.entries)
            if (e.key != key) e.key: e.value,
        });
    // setState assigns straight away and only schedules the rebuild, so this validator already
    // reads the map without [key] in it. See [_fieldKeys] for why one field and not the form.
    _fieldKeys[key]?.currentState?.validate();
  }

  /// The server's message for [key] if there is one, otherwise this form's own rule.
  String? _errorOr(String key, String? Function() rule) => _errors[key] ?? rule();

  // ── VALIDATION ─────────────────────────────────────────────────────────────

  /// Everything the three non-text controls can be wrong about.
  ///
  /// Kept apart from the [Form] because a dropdown, a bed picker and a file are not
  /// TextFormFields and have no validator of their own — their messages are drawn by hand.
  Map<String, String> _validateControls() {
    final errors = <String, String>{};
    if (_bedId == null) errors['bedId'] = 'Pick a free bed';
    if (_idProofType == null) errors['idProofType'] = 'Choose an ID proof type';

    // index.ts files a MISSING FILE under 'idProofType' (`v.reject("idProofType", "ID proof
    // file is required")`). This form puts it under the file control instead, where the thing
    // to do about it is. A server message still lands under whichever key the server chose.
    final idProof = _idProof;
    if (idProof == null) {
      errors['idProof'] = 'ID proof file is required';
    } else if (idProof.isTooLarge) {
      errors['idProof'] = 'File is larger than 3 MB';
    }
    final photo = _photo;
    if (photo != null && photo.isTooLarge) errors['photo'] = 'File is larger than 3 MB';
    return errors;
  }

  /// True when nothing is left to fix. Runs BEFORE anything is sent — an ID scan is the largest
  /// request this app makes, and pushing it up a stairwell 3G connection only to be told the
  /// guardian's name is blank is a minute of somebody's life for nothing.
  bool _validate() {
    final controls = _validateControls();
    setState(() => _errors = controls);
    // Reads _errors, which now holds only what this form found — the previous round's server
    // messages were cleared by the caller before this ran.
    final formOk = _form.currentState!.validate();
    return formOk && controls.isEmpty;
  }

  // ── SUBMIT ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_busy) return;
    // Last round's server messages describe a payload that is about to be replaced.
    setState(() {
      _errors = const {};
      _banner = null;
    });
    if (!_validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final name = _name.text.trim();
    final draft = StudentRegistration(
      fullName: name,
      phone: normalisePhone(_phone.text),
      email: _blank(_email.text),
      dateOfJoining: _joining,
      guardianName: _guardianName.text.trim(),
      guardianPhone: normalisePhone(_guardianPhone.text),
      permanentAddress: _address.text.trim(),
      idProofType: _idProofType!,
      idProof: _idProof!,
      photo: _photo,
      bedId: _bedId!,
      monthlyFee: double.parse(_fee.text.trim()),
    );

    final RegistrationOutcome outcome;
    try {
      outcome = await ref.read(wardenRegistrationsProvider).registerStudent(draft);
    } catch (error) {
      // Offline, session ended, not permitted, subscription lapsed, a rollback that itself
      // failed — none of it is something a text box can fix, and [AppFailure] has already
      // turned it into the right sentence. See WardenRepository.registerStudent.
      if (!mounted) return;
      setState(() => _busy = false);
      showFailureSnack(context, error);
      return;
    }
    if (!mounted) return;

    switch (outcome) {
      case RegistrationRejected(:final message, :final fieldErrors):
        setState(() {
          _busy = false;
          _errors = fieldErrors;
          // A message with a field to sit under does not also need a banner.
          _banner = fieldErrors.isEmpty ? message : null;
          // The bed was free when the picker loaded and is not now. Dropping the stale choice
          // is the difference between "fix this" and "press Register again and lose again".
          if (fieldErrors.containsKey('bedId')) {
            _bedId = null;
            _bedLabel = null;
          }
        });
        _form.currentState?.validate();

      case RegistrationSucceeded(:final student):
        setState(() => _busy = false);
        // BEFORE anything else, and awaited: the password exists in this one variable and
        // nowhere else on earth. Popping the sheet first would take the dialog's context with
        // it, and the resident would have an account nobody can sign in to.
        await StudentCredentialsDialog.show(
          context,
          credentials: student.credentials,
          bedLabel: _bedLabel,
        );
        if (!mounted) return;
        refreshResidents(ref);
        refreshBeds(ref);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name registered'),
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.of(context).pop(true);
    }
  }

  static String? _blank(String v) => v.trim().isEmpty ? null : v.trim();

  // ── PICKERS ────────────────────────────────────────────────────────────────

  Future<void> _pickJoiningDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _joining,
      // A year back covers a record being entered late; not the future, because a fee ledger
      // keyed on a joining date that has not happened yet is a ledger nobody can reconcile.
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _joining = picked);
  }

  /// THE TAP THAT DID NOTHING. This is the control the warden reported: they tapped it, and no
  /// sheet, no spinner and no message came back, with 45 free beds in the building.
  ///
  /// It used to `await ref.read(freeBedOptionsProvider(…).future)` BEFORE opening the sheet.
  /// That provider is autoDispose and nothing was listening to it, so it was torn down mid-read
  /// and threw UnmountedRefException out of `.future`; with no try/catch here the exception went
  /// to the zone and this method simply never reached its next line. The full account is at the
  /// top of assign_bed_sheet.dart.
  ///
  /// Nothing is awaited before the sheet now. [FreeBedPicker] watches the provider itself, which
  /// both keeps it alive while the picker is open and gives the load somewhere visible to
  /// happen. A tap always produces a sheet; what the sheet then says is the truth about the
  /// building or about the failure.
  Future<void> _pickBed() async {
    final chosen = await showGlassSheet<FreeBed>(
      context: context,
      builder: (_) => FreeBedPicker(hostelId: widget.hostelId, title: 'Choose a bed'),
    );
    if (chosen != null && mounted) {
      setState(() {
        _bedId = chosen.bed.id;
        _bedLabel = chosen.label;
      });
      _clear('bedId');
    }
  }

  /// Opens the camera or the photo picker and keeps the bytes.
  ///
  /// A CANCELLED PICK IS NOT A FAILURE and is not reported as one — [DocumentCapture.pick]
  /// completes with null and the previous choice, if any, is left alone. Anything the plugin
  /// actually throws (no camera, permission refused on an older Android) becomes the same
  /// snackbar every other failure uses rather than an unhandled exception on a sheet the warden
  /// is standing in.
  Future<void> _capture({required bool idProof, required CaptureSource source}) async {
    try {
      final picked = await ref.read(documentCaptureProvider).pick(source);
      if (picked == null || !mounted) return;
      setState(() {
        if (idProof) {
          _idProof = picked;
        } else {
          _photo = picked;
        }
      });
      _clear(idProof ? 'idProof' : 'photo');
    } catch (error) {
      if (!mounted) return;
      showFailureSnack(context, error);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SheetBody(
      title: 'Register resident',
      subtitle: 'Creates their record, their bed and their login',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: _fieldKeys['fullName'],
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clear('fullName'),
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => _errorOr('fullName', () {
                final text = (v ?? '').trim();
                if (text.length < 2) return 'Enter the student\'s full name';
                if (text.length > 120) return 'Keep this under 120 characters.';
                return null;
              }),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              key: _fieldKeys['phone'],
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _clear('phone'),
              decoration: InputDecoration(
                labelText: 'Phone number',
                // Not "if an account is created" any more. It always is — and which of these
                // two boxes becomes the login depends on whether the other one is filled in.
                helperText: _hasEmail
                    ? 'For contact and the fee ledger'
                    : 'This is the login id they sign in with',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              validator: (v) => _errorOr('phone', () => _phoneValidator(v)),
            ),
            const SizedBox(height: Space.sm),
            // OPTIONAL, AND DELIBERATELY SO. A hostel resident may genuinely not have an email
            // — that is the whole reason phone login exists — and a required box here would be
            // answered with an invented address. That is worse than a blank one: public.users
            // carries a UNIQUE index on lower(email) and GoTrue never releases a taken address,
            // so a borrowed or mistyped address permanently squats on somebody else's login.
            //
            // When it IS given it becomes the login, not a second way in. See
            // createStudentAuthUser in the Edge Function.
            TextFormField(
              key: _fieldKeys['email'],
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onChanged: (v) {
                _clear('email');
                final has = v.trim().isNotEmpty;
                if (has != _hasEmail) setState(() => _hasEmail = has);
              },
              decoration: InputDecoration(
                labelText: 'Email',
                helperText: _hasEmail
                    ? 'This is the login id they sign in with'
                    : 'Optional — without one they sign in with their phone number',
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
              ),
              validator: (v) => _errorOr('email', () {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                if (text.length > 160) return 'Keep this under 160 characters.';
                // The same shape index.ts's EMAIL_RE accepts, so an address is not taken here
                // and refused there.
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
                  return 'Enter a valid email';
                }
                // The phone-mapping namespace is reserved — isStudentLoginEmail() in the Edge
                // Function refuses it too. An address in it would mint the login id belonging
                // to another resident's phone number and lock that person out for good.
                if (text.toLowerCase().endsWith('@$studentLoginDomain')) {
                  return 'Enter a real email address';
                }
                return null;
              }),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              key: _fieldKeys['monthlyFee'],
              controller: _fee,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clear('monthlyFee'),
              decoration: const InputDecoration(
                labelText: 'Monthly rent',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              validator: (v) => _errorOr('monthlyFee', () {
                final amount = double.tryParse((v ?? '').trim());
                if (amount == null) return 'Enter the monthly fee';
                // 1 to 1,000,000 — the Edge Function's bounds, which are TIGHTER than the check
                // constraint on students.monthly_fee. The stricter of the two is the one that
                // decides, so it is the one this form states.
                if (amount < 1 || amount > 1000000) {
                  return 'Enter a value between 1 and 1000000.';
                }
                return null;
              }),
            ),
            const SizedBox(height: Space.sm),
            _PickerField(
              label: 'Joined on',
              value: shortDate(_joining),
              icon: Icons.event_outlined,
              onTap: _busy ? null : _pickJoiningDate,
            ),
            const SizedBox(height: Space.sm),
            _PickerField(
              label: 'Bed',
              value: _bedLabel ?? 'Choose a bed',
              icon: Icons.bed_outlined,
              errorText: _errors['bedId'],
              onTap: _busy ? null : _pickBed,
            ),

            const SectionLabel(label: 'Guardian and address'),
            TextFormField(
              key: _fieldKeys['guardianName'],
              controller: _guardianName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clear('guardianName'),
              decoration: const InputDecoration(
                labelText: 'Guardian name',
                prefixIcon: Icon(Icons.escalator_warning_outlined),
              ),
              validator: (v) => _errorOr('guardianName', () {
                final text = (v ?? '').trim();
                if (text.length < 2) return 'Enter the guardian\'s name';
                if (text.length > 120) return 'Keep this under 120 characters.';
                return null;
              }),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              key: _fieldKeys['guardianPhone'],
              controller: _guardianPhone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _clear('guardianPhone'),
              decoration: const InputDecoration(
                labelText: 'Guardian phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) => _errorOr('guardianPhone', () => _phoneValidator(v)),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              key: _fieldKeys['permanentAddress'],
              controller: _address,
              enabled: !_busy,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _clear('permanentAddress'),
              decoration: const InputDecoration(
                labelText: 'Permanent address',
                alignLabelWithHint: true,
              ),
              validator: (v) => _errorOr('permanentAddress', () {
                final text = (v ?? '').trim();
                if (text.length < 6) return 'Enter the permanent address';
                if (text.length > 600) return 'Keep this under 600 characters.';
                return null;
              }),
            ),

            const SectionLabel(label: 'ID proof'),
            _IdProofTypeField(
              value: _idProofType,
              errorText: _errors['idProofType'],
              enabled: !_busy,
              onChanged: (v) {
                setState(() => _idProofType = v);
                _clear('idProofType');
              },
            ),
            const SizedBox(height: Space.sm),
            _DocumentField(
              label: 'ID proof file',
              hint: 'Photograph the card, or pick a scan',
              document: _idProof,
              errorText: _errors['idProof'],
              enabled: !_busy,
              onPick: (source) => _capture(idProof: true, source: source),
              onClear: _idProof == null
                  ? null
                  : () {
                      setState(() => _idProof = null);
                      _clear('idProof');
                    },
            ),

            const SectionLabel(label: 'Optional'),
            _DocumentField(
              label: 'Resident photo',
              hint: 'Not required',
              document: _photo,
              errorText: _errors['photo'],
              enabled: !_busy,
              onPick: (source) => _capture(idProof: false, source: source),
              onClear: _photo == null
                  ? null
                  : () {
                      setState(() => _photo = null);
                      _clear('photo');
                    },
            ),

            const SizedBox(height: Space.lg),
            // assign-bed-review.png's billing notice, which is the design's one aside: a
            // `surface-container-highest` well, `rounded-lg`, a violet glyph, body copy. This
            // and the refusal below used to be two hand-rolled boxes at 0.08 / 0.32 — numbers
            // nobody could re-derive, and not the measured chip recipe either.
            InfoCallout(
              icon: Icons.info_outline_rounded,
              child: Text(
                'This also creates their app login. The temporary password appears once, '
                'on the next screen — copy it before you close it, because it is stored '
                'nowhere.',
                style: t.textTheme.bodySmall,
              ),
            ),
            if (_banner != null) ...[
              const SizedBox(height: Space.sm),
              InfoCallout(
                icon: Icons.error_outline_rounded,
                tone: NivoraColors.error,
                child: Text(_banner!, style: t.textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _busy ? null : _submit,
              // onPrimary, not the progress theme's colour — that is scheme.primary, which is
              // the button's own fill, so the spinner was indigo on indigo.
              child: _busy
                  ? InlineSpinner(onFill: Theme.of(context).colorScheme.onPrimary)
                  : const Text('Register resident'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Matches the web app's phone10 rule exactly: strip everything that is not a digit, drop a
/// leading 91 or 0, then insist on ten. The two clients write to one `students_phone_active_key`
/// unique index, so "9876543210" typed on a phone and "+91 98765 43210" typed on a desktop have
/// to end up as the same string or the same person registers twice.
String normalisePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  return digits;
}

/// index.ts is stricter than "ten digits": `phone10` also insists the first is 6–9, because an
/// Indian mobile number starts there and this string becomes a login id. Saying so here means a
/// landline typed at the desk is caught at the desk.
String? _phoneValidator(String? value) {
  final digits = normalisePhone(value ?? '');
  return RegExp(r'^[6-9]\d{9}$').hasMatch(digits)
      ? null
      : 'Enter a valid 10-digit phone number';
}

/// A read-only field that opens a picker. Looks like the other inputs so the form reads as one
/// thing rather than a form with two buttons in it.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.errorText,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Radii.rControl,
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          errorText: errorText,
          suffixIcon: const Icon(Icons.chevron_right_rounded),
        ),
        child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

/// The six values public.students.id_proof_type takes, from [IdProofType] rather than from a
/// list written out here — a seventh spelling on this screen would be a document type no report
/// groups with the six the web app writes.
class _IdProofTypeField extends StatelessWidget {
  const _IdProofTypeField({
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.errorText,
  });

  final IdProofType? value;
  final ValueChanged<IdProofType?> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<IdProofType>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'ID proof type',
        prefixIcon: const Icon(Icons.badge_outlined),
        errorText: errorText,
      ),
      // NOT the words the error uses. A hint and a complaint that read identically
      // leave the warden unable to tell whether the form is asking or telling.
      hint: const Text('Choose one'),
      items: [
        for (final type in IdProofType.values)
          DropdownMenuItem(value: type, child: Text(type.label)),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// One file, captured in the app.
///
/// TWO ENTRY POINTS, NOT ONE. A warden at the desk photographs the card in front of them; a
/// warden entering a record later already has the scan in the gallery. Offering only the camera
/// means the second case retakes a photo of a screen.
class _DocumentField extends StatelessWidget {
  const _DocumentField({
    required this.label,
    required this.hint,
    required this.document,
    required this.enabled,
    required this.onPick,
    this.onClear,
    this.errorText,
  });

  final String label;
  final String hint;
  final CapturedDocument? document;
  final bool enabled;
  final ValueChanged<CaptureSource> onPick;
  final VoidCallback? onClear;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final doc = document;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.attach_file_rounded),
        errorText: errorText,
        suffixIcon: doc == null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Take a photo',
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: enabled ? () => onPick(CaptureSource.camera) : null,
                  ),
                  IconButton(
                    tooltip: 'Choose a file',
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: enabled ? () => onPick(CaptureSource.gallery) : null,
                  ),
                ],
              )
            : IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded),
                onPressed: enabled ? onClear : null,
              ),
      ),
      // The size is shown because the 3 MB ceiling is the server's and a warden who has just
      // attached a 6 MB scan should learn it here, not after the upload.
      child: Text(
        doc == null ? hint : '${doc.name} · ${doc.sizeLabel}',
        style: t.textTheme.bodyLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
