library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../data/warden_providers.dart';
import '../widgets/warden_ui.dart';
import 'assign_bed_sheet.dart';
import 'sheet_scaffold.dart';

/// Register a resident.
///
/// WHAT THIS SCREEN PROMISES AND WHAT IT DOES NOT. It puts a person on the roster, optionally
/// in a bed, and on this month's fee ledger. It does NOT create an app login — see
/// WardenRepository.registerStudent for why (the login needs the service-role key, which is
/// server-only and cannot be in an APK). The notice at the foot of the form says so in plain
/// words, because a warden who believes they handed out credentials will not chase the missing
/// account until the resident complains they cannot sign in.
///
/// REQUIRED FIELDS DIFFER FROM THE WEB FORM, deliberately. The web's four-step wizard requires
/// guardian details, a permanent address and an uploaded ID proof; the database requires none
/// of them (all four columns are nullable). A warden registering someone at the door on a phone
/// has the name, the number and the rent — demanding an address scan at that moment means the
/// record does not get created at all. What the database insists on, this form insists on;
/// everything else can be filled in later from either client.
Future<bool?> showRegisterStudentSheet(BuildContext context, {required String hostelId}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _RegisterStudentSheet(hostelId: hostelId),
  );
}

class _RegisterStudentSheet extends ConsumerStatefulWidget {
  const _RegisterStudentSheet({required this.hostelId});
  final String hostelId;

  @override
  ConsumerState<_RegisterStudentSheet> createState() => _RegisterStudentSheetState();
}

class _RegisterStudentSheetState extends ConsumerState<_RegisterStudentSheet> {
  final _form = GlobalKey<FormState>();
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
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _fee, _guardianName, _guardianPhone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final repo = ref.read(wardenRepositoryProvider);
    final ok = await runAction(
      context,
      success: '${_name.text.trim()} registered',
      action: () => repo.registerStudent(
        hostelId: widget.hostelId,
        fullName: _name.text.trim(),
        phone: normalisePhone(_phone.text),
        monthlyFee: double.parse(_fee.text.trim()),
        dateOfJoining: _joining,
        bedId: _bedId,
        email: _blank(_email.text),
        guardianName: _blank(_guardianName.text),
        guardianPhone: _guardianPhone.text.trim().isEmpty
            ? null
            : normalisePhone(_guardianPhone.text),
        permanentAddress: _blank(_address.text),
      ),
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshResidents(ref);
      refreshBeds(ref);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  static String? _blank(String v) => v.trim().isEmpty ? null : v.trim();

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

  Future<void> _pickBed() async {
    final beds = await ref.read(freeBedOptionsProvider(widget.hostelId).future);
    if (!mounted) return;
    final chosen = await showGlassSheet<FreeBed>(
      context: context,
      builder: (_) => FreeBedPicker(
        beds: beds,
        title: 'Choose a bed',
        subtitle: '${beds.length} free',
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        _bedId = chosen.bed.id;
        _bedLabel = chosen.label;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SheetBody(
      title: 'Register resident',
      subtitle: 'Name, number and rent are all the database requires',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Enter the resident\'s full name' : null,
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Phone number',
                helperText: 'Unique per resident, and their login id if an account is created',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: _phoneValidator,
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _fee,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Monthly rent',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim());
                if (amount == null) return 'Enter the monthly rent';
                // Mirrors the check constraint on students.monthly_fee, so the form says it
                // rather than the server rejecting a filled-in page.
                if (amount < 0 || amount > 10000000) return 'Enter an amount up to ₹1,00,00,000';
                return null;
              },
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
              value: _bedLabel ?? 'Not assigned yet',
              icon: Icons.bed_outlined,
              onTap: _busy ? null : _pickBed,
              onClear: _bedId == null
                  ? null
                  : () => setState(() {
                        _bedId = null;
                        _bedLabel = null;
                      }),
            ),

            const SectionLabel(label: 'Optional'),
            TextFormField(
              controller: _guardianName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Guardian name',
                prefixIcon: Icon(Icons.escalator_warning_outlined),
              ),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _guardianPhone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Guardian phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? null : _phoneValidator(v),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                return text.contains('@') && text.length > 4 ? null : 'Enter a valid email';
              },
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _address,
              enabled: !_busy,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Permanent address',
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: context.tones.chipFill(NivoraColors.info),
                borderRadius: Radii.rControl,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: IconSize.sm, color: context.tones.info),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      'This creates the resident record only. An app login for them has to be '
                      'issued from the web console — the mobile app is not allowed to create '
                      'accounts.',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
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

String? _phoneValidator(String? value) {
  final digits = normalisePhone(value ?? '');
  return digits.length == 10 ? null : 'Enter a valid 10-digit phone number';
}

/// A read-only field that opens a picker. Looks like the other inputs so the form reads as one
/// thing rather than a form with two buttons in it.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Radii.rControl,
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: onClear == null
              ? const Icon(Icons.chevron_right_rounded)
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                ),
        ),
        child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
