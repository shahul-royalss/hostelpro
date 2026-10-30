/// R4.2: the owner or a warden edits every detail a tenant gave at sign-up, through
/// `wd_update_tenant_profile`. Only changed fields are sent; the server re-validates each one
/// and never touches the role, the PG, the login email or the sign-in identifier.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/tenant_admin.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../data/repositories/tenant_admin_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../common/form_parts.dart';
import '../data/warden_providers.dart';

/// True when something was saved.
Future<bool> showEditTenantSheet(
  BuildContext context, {
  required String studentId,
  required String studentName,
}) async =>
    await showApnivaasSheet<bool>(
      context: context,
      title: 'Edit details',
      subtitle: 'What $studentName gave when signing up. Their sign-in stays as it is.',
      builder: (_) => _EditTenant(studentId: studentId),
    ) ??
    false;

class _EditTenant extends ConsumerWidget {
  const _EditTenant({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(tenantProfileProvider(studentId));
    return profile.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.lg),
        child: ListSkeleton(rows: 4, leading: false, semanticLabel: 'Loading details'),
      ),
      error: (e, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormNote(e is SignupFailure ? e.message : 'Could not load the details.'),
          TextButton(
            onPressed: () => ref.invalidate(tenantProfileProvider(studentId)),
            child: const Text('Try again'),
          ),
        ],
      ),
      data: (p) => p == null
          ? const FormNote('This resident is not visible any more.')
          : TenantDetailsForm(profile: p),
    );
  }
}

/// The form itself; public so it can be tested with a profile in hand.
class TenantDetailsForm extends ConsumerStatefulWidget {
  const TenantDetailsForm({super.key, required this.profile});
  final TenantProfile profile;

  @override
  ConsumerState<TenantDetailsForm> createState() => _TenantDetailsFormState();
}

enum _F { fullName, phone, email, gender, dob, eName, ePhone, address, city, pincode }

const _hintToField = {
  'full_name': _F.fullName,
  'phone': _F.phone,
  'email': _F.email,
  'gender': _F.gender,
  'date_of_birth': _F.dob,
  'emergency_contact_name': _F.eName,
  'emergency_contact_phone': _F.ePhone,
  'address': _F.address,
  'city': _F.city,
  'pincode': _F.pincode,
};

final _phoneRe = RegExp(r'^[6-9]\d{9}$');
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _pinRe = RegExp(r'^[1-9]\d{5}$');

/// Digits only, a leading 91 / 0 dropped, as the server normalises it.
String _digits(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return d;
}

class _TenantDetailsFormState extends ConsumerState<TenantDetailsForm> {
  late final TenantProfile p = widget.profile;
  late final _c = <_F, TextEditingController>{
    _F.fullName: TextEditingController(text: p.fullName),
    _F.phone: TextEditingController(text: p.phone),
    _F.email: TextEditingController(text: p.email ?? ''),
    _F.eName: TextEditingController(text: p.emergencyName ?? ''),
    _F.ePhone: TextEditingController(text: p.emergencyPhone ?? ''),
    _F.address: TextEditingController(text: p.address ?? ''),
    _F.city: TextEditingController(text: p.city ?? ''),
    _F.pincode: TextEditingController(text: p.pincode ?? ''),
  };
  late String? _gender = p.gender;
  late DateTime? _dob = p.dateOfBirth;
  final _errors = <_F, String>{};
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(_F f) => _c[f]!.text.trim();

  /// A changed optional text: the new value, '' to clear, or null when unchanged.
  String? _changed(_F f, String? before) {
    final now = _t(f);
    return now == (before ?? '').trim() ? null : now;
  }

  Map<_F, String> _validate() {
    final e = <_F, String>{};
    final name = _t(_F.fullName);
    if (name.length < 2 || name.length > 80) e[_F.fullName] = 'Enter the full name (2 to 80 characters).';
    final phone = _digits(_t(_F.phone));
    if (!_phoneRe.hasMatch(phone)) e[_F.phone] = 'Enter a valid 10-digit mobile number.';
    final email = _t(_F.email);
    if (email.isNotEmpty && (email.length > 254 || !_emailRe.hasMatch(email))) {
      e[_F.email] = 'Enter a valid email address.';
    }
    final eName = _t(_F.eName);
    if (eName.isNotEmpty && (eName.length < 2 || eName.length > 80)) {
      e[_F.eName] = "Enter the emergency contact's name (2 to 80 characters).";
    }
    final ePhone = _t(_F.ePhone);
    if (ePhone.isNotEmpty) {
      final d = _digits(ePhone);
      if (!_phoneRe.hasMatch(d)) {
        e[_F.ePhone] = 'Enter a valid 10-digit number for the emergency contact.';
      } else if (d == phone) {
        e[_F.ePhone] = "The emergency contact needs a different number from the resident's.";
      }
    }
    final addr = _t(_F.address);
    if (addr.isNotEmpty && (addr.length < 5 || addr.length > 500)) {
      e[_F.address] = 'Enter the full address (5 to 500 characters).';
    }
    if (p.hasAccount) {
      final city = _t(_F.city);
      if (city.isNotEmpty && (city.length < 2 || city.length > 80)) {
        e[_F.city] = 'Enter the city (2 to 80 characters).';
      }
      final pin = _t(_F.pincode);
      if (pin.isNotEmpty && !_pinRe.hasMatch(pin)) e[_F.pincode] = 'Enter a valid 6-digit pincode.';
    }
    return e;
  }

  TenantProfilePatch _patch() {
    final phone = _digits(_t(_F.phone));
    final dobChanged = _dob != null &&
        (p.dateOfBirth == null || !DateUtils.isSameDay(_dob, p.dateOfBirth));
    return TenantProfilePatch(
      fullName: _t(_F.fullName) == p.fullName.trim() ? null : _t(_F.fullName),
      phone: phone == _digits(p.phone) ? null : phone,
      email: _changed(_F.email, p.email),
      emergencyName: _changed(_F.eName, p.emergencyName),
      emergencyPhone: _changed(_F.ePhone, p.emergencyPhone),
      address: _changed(_F.address, p.address),
      gender: p.hasAccount && _gender != null && _gender != p.gender ? _gender : null,
      dateOfBirth: p.hasAccount && dobChanged ? _dob : null,
      city: p.hasAccount ? _changed(_F.city, p.city) : null,
      pincode: p.hasAccount ? _changed(_F.pincode, p.pincode) : null,
    );
  }

  Future<void> _save() async {
    final errors = _validate();
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _error = null;
    });
    if (errors.isNotEmpty) return;
    final patch = _patch();
    if (patch.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(tenantAdminApiProvider).updateProfile(p.studentId, patch);
      ref.invalidate(tenantProfileProvider(p.studentId));
      ref.invalidate(studentProvider(p.studentId));
      refreshResidents(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        final field = _hintToField[f.field];
        if (field != null) {
          _errors[field] = f.message;
        } else {
          _error = f.message;
        }
      });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final last = DateTime(now.year - 10, now.month, now.day);
    final first = DateTime(now.year - 100, now.month, now.day + 1);
    var initial = _dob ?? DateTime(now.year - 20, now.month, now.day);
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  Widget _field(
    _F f,
    String label, {
    TextInputType? keyboard,
    int? maxLength,
    int maxLines = 1,
    String? helper,
    List<TextInputFormatter>? formatters,
    TextCapitalization caps = TextCapitalization.none,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: TextField(
          key: ValueKey('tenant-${f.name}'),
          controller: _c[f],
          enabled: !_busy,
          keyboardType: keyboard,
          maxLength: maxLength,
          minLines: 1,
          maxLines: maxLines,
          inputFormatters: formatters,
          textCapitalization: caps,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 2,
            counterText: '',
            errorText: _errors[f],
            errorMaxLines: 3,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_F.fullName, 'Full name', maxLength: 80, caps: TextCapitalization.words),
          _field(_F.phone, 'Mobile number',
              keyboard: TextInputType.phone,
              maxLength: 16,
              formatters: digits,
              helper: p.hasAccount ? 'Changing it does not change how they sign in.' : null),
          _field(_F.email, 'Email (shown to staff)',
              keyboard: TextInputType.emailAddress, maxLength: 254),
          if (p.hasAccount) ...[
            Text('Gender', style: t.textTheme.labelLarge),
            const SizedBox(height: Space.xxs),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final (value, label) in const [
                  ('male', 'Male'),
                  ('female', 'Female'),
                  ('other', 'Other'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _gender == value,
                    onSelected: _busy ? null : (_) => setState(() => _gender = value),
                  ),
              ],
            ),
            if (_errors[_F.gender] != null) FormNote(_errors[_F.gender]!),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              key: const ValueKey('tenant-dob'),
              onPressed: _busy ? null : _pickDob,
              icon: const Icon(Icons.cake_outlined, size: IconSize.md),
              label: Text(
                _dob == null
                    ? 'Date of birth: not given'
                    : 'Date of birth: ${DateFormat('d MMM yyyy').format(_dob!)}',
                maxLines: 2,
              ),
            ),
            if (_errors[_F.dob] != null) FormNote(_errors[_F.dob]!),
            const SizedBox(height: Space.sm),
          ],
          _field(_F.eName, 'Emergency contact name', maxLength: 80, caps: TextCapitalization.words),
          _field(_F.ePhone, 'Emergency contact number',
              keyboard: TextInputType.phone, maxLength: 16, formatters: digits),
          _field(_F.address, 'Address',
              keyboard: TextInputType.streetAddress,
              maxLength: 500,
              maxLines: 3,
              caps: TextCapitalization.sentences),
          if (p.hasAccount) ...[
            _field(_F.city, 'City', maxLength: 80, caps: TextCapitalization.words),
            _field(_F.pincode, 'Pincode',
                keyboard: TextInputType.number,
                maxLength: 6,
                formatters: [FilteringTextInputFormatter.digitsOnly]),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: Space.sm),
              child: InfoNote(
                icon: Icons.info_outline_rounded,
                message: 'Gender, date of birth, city and pincode are saved on the app '
                    'account, and this resident has none.',
              ),
            ),
          if (_error != null) ...[FormNote(_error!), const SizedBox(height: Space.xs)],
          BusyFilledButton(
            label: 'Save details',
            busy: _busy,
            busyLabel: 'Saving…',
            onPressed: _save,
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
