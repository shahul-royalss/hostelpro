/// Tell us about your PG — an owner's step 4 (docs/self-signup-onboarding-spec.md, Flow 3).
///
/// One call, `ow_create_first_hostel`. The server checks every field again and refuses in its
/// own sentences; a sentence whose `hint` names a field is shown under that field.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/device/signup_device.dart';
import '../../../data/models/signup.dart';
import '../../../data/repositories/signup_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../auth/auth_scaffold.dart';
import '../../auth/verify_email_screen.dart';
import '../../common/form_parts.dart';
import '../signup_widgets.dart';

const propertyTypes = <String, String>{
  'pg': 'PG',
  'hostel': 'Hostel',
  'co_living': 'Co-living',
  'flats': 'Flats',
};

const genderPolicies = <String, String>{'boys': 'Boys', 'girls': 'Girls', 'coed': 'Co-ed'};

/// What the owner typed, handed on so Book a demo can prefill the PG name and city.
typedef CreatedPg = ({FirstHostel hostel, String name, String city, bool alreadySetUp});

class PgDetailsScreen extends ConsumerStatefulWidget {
  const PgDetailsScreen({super.key, required this.onCreated});

  final ValueChanged<CreatedPg> onCreated;

  @override
  ConsumerState<PgDetailsScreen> createState() => _PgDetailsScreenState();
}

class _PgDetailsScreenState extends ConsumerState<PgDetailsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _locality = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  final _floors = TextEditingController(text: '1');
  final _rooms = TextEditingController();
  final _beds = TextEditingController(text: '2');
  String? _type = 'pg';
  String? _gender;
  LocationFix? _pin;
  bool _locating = false;
  String? _locationNote;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    for (final c in [_name, _address, _locality, _city, _pincode, _floors, _rooms, _beds]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _locationNote = null;
    });
    final outcome = await ref.read(deviceLocatorProvider).locate(
          explain: () => askInWords(
            context,
            title: 'Use your location?',
            message: 'Apnivaas will ask your phone for your exact location to pin your PG '
                'on the map, so tenants nearby can find it. You can skip this and type the '
                'address only.',
          ),
        );
    if (!mounted) return;
    setState(() {
      _locating = false;
      switch (outcome) {
        case LocationFix():
          _pin = outcome;
        case LocationSkipped():
          break;
        case LocationUnavailable(:final message):
          _locationNote = message;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    final typeOk = _type != null, genderOk = _gender != null;
    if (!(_form.currentState?.validate() ?? false) || !typeOk || !genderOk) {
      setState(() => _fieldErrors = {
            if (!typeOk) 'property_type': 'Choose PG, Hostel, Co-living or Flats.',
            if (!genderOk) 'gender_policy': 'Choose Boys, Girls or Co-ed.',
          });
      return;
    }
    setState(() => _busy = true);
    final name = _name.text.trim(), city = _city.text.trim();
    try {
      final hostel = await ref.read(signupApiProvider).createFirstHostel(
            name: name,
            propertyType: _type!,
            genderPolicy: _gender!,
            address: _address.text.trim(),
            locality: _locality.text.trim(),
            city: city,
            pincode: _pincode.text.trim(),
            floors: int.parse(_floors.text.trim()),
            rooms: int.parse(_rooms.text.trim()),
            bedsPerRoom: int.parse(_beds.text.trim()),
            latitude: _pin?.latitude,
            longitude: _pin?.longitude,
          );
      if (!mounted) return;
      widget.onCreated((hostel: hostel, name: name, city: city, alreadySetUp: false));
    } on SignupFailure catch (f) {
      if (!mounted) return;
      // A double tap (or a retry after a lost answer) lands here; it is success.
      if (f.message == 'Your PG is already set up.') {
        widget.onCreated((
          hostel: const FirstHostel(hostelId: '', name: ''),
          name: name,
          city: city,
          alreadySetUp: true,
        ));
        return;
      }
      setState(() {
        _busy = false;
        final field = f.field;
        if (field != null && _knownFields.contains(field)) {
          _fieldErrors = {field: f.message};
          _form.currentState?.validate();
        } else {
          _error = f.message;
        }
      });
    }
  }

  static const _knownFields = {
    'name', 'property_type', 'gender_policy', 'address', 'locality', 'city', 'pincode', //
    'floors', 'rooms', 'beds_per_room', 'latitude', 'longitude',
  };

  String? _server(String field) => _fieldErrors[field];

  String? _range(String? v, int min, int max, String sentence) {
    final n = int.tryParse((v ?? '').trim());
    return (n == null || n < min || n > max) ? sentence : null;
  }

  String? _length(String? v, int min, int max, String sentence) {
    final n = (v ?? '').trim().length;
    return (n < min || n > max) ? sentence : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    Widget gap() => const SizedBox(height: Space.sm);
    return SignupPage(
      showSignOut: true,
      children: [
        const SizedBox(height: Space.md),
        const StepIndicator(step: 4),
        const SizedBox(height: Space.md),
        const AuthHeading(
          title: 'Tell us about your PG',
          message: 'Your first month is free. You can change these later.',
          icon: ClayIcons.rooms,
        ),
        const SizedBox(height: Space.md),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'PG name'),
                validator: (v) =>
                    _server('name') ??
                    _length(v, 2, 120, 'Enter the PG name (2 to 120 characters).'),
              ),
              GroupLabel('Type of property', error: _fieldErrors['property_type']),
              ChoicePills<String>(
                options: propertyTypes,
                selected: _type,
                enabled: !_busy,
                onSelected: (v) => setState(() => _type = v),
              ),
              GroupLabel('For', error: _fieldErrors['gender_policy']),
              ChoicePills<String>(
                options: genderPolicies,
                selected: _gender,
                enabled: !_busy,
                onSelected: (v) => setState(() => _gender = v),
              ),
              gap(),
              TextFormField(
                controller: _address,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Full address'),
                validator: (v) =>
                    _server('address') ??
                    _length(v, 5, 500, 'Enter the full address (5 to 500 characters).'),
              ),
              gap(),
              TextFormField(
                controller: _locality,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Locality'),
                validator: (v) =>
                    _server('locality') ??
                    _length(v, 2, 120, 'Enter the locality (2 to 120 characters).'),
              ),
              gap(),
              TextFormField(
                controller: _city,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'City'),
                validator: (v) =>
                    _server('city') ?? _length(v, 2, 80, 'Enter the city (2 to 80 characters).'),
              ),
              gap(),
              TextFormField(
                controller: _pincode,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [...digits, LengthLimitingTextInputFormatter(6)],
                decoration: const InputDecoration(labelText: 'Pincode'),
                validator: (v) =>
                    _server('pincode') ??
                    (RegExp(r'^[1-9]\d{5}$').hasMatch((v ?? '').trim())
                        ? null
                        : 'Enter a valid 6-digit pincode.'),
              ),
              gap(),
              // Three short numbers. They wrap onto their own lines when the text is large,
              // rather than squeezing three labels into a 360dp row.
              LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth / MediaQuery.textScalerOf(context).scale(1) > 330;
                final fields = [
                  TextFormField(
                    controller: _floors,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Floors'),
                    validator: (v) =>
                        _server('floors') ?? _range(v, 1, 50, 'Floors must be between 1 and 50.'),
                  ),
                  TextFormField(
                    controller: _rooms,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Rooms'),
                    validator: (v) =>
                        _server('rooms') ?? _range(v, 1, 500, 'Rooms must be between 1 and 500.'),
                  ),
                  TextFormField(
                    controller: _beds,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Beds per room'),
                    validator: (v) =>
                        _server('beds_per_room') ??
                        _range(v, 1, 20, 'Beds per room must be between 1 and 20.'),
                  ),
                ];
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [fields[0], gap(), fields[1], gap(), fields[2]],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: Space.xs),
                    Expanded(child: fields[1]),
                    const SizedBox(width: Space.xs),
                    Expanded(child: fields[2]),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        _LocationRow(
          pinned: _pin != null,
          busy: _locating,
          onUse: _busy || _locating ? null : _useLocation,
          onClear: _busy ? null : () => setState(() => _pin = null),
        ),
        if (_locationNote != null) ...[
          const SizedBox(height: Space.xs),
          FormNote(_locationNote!, tone: FormNoteTone.warning),
        ],
        if (_server('latitude') ?? _server('longitude') case final pinError?) ...[
          const SizedBox(height: Space.xs),
          FormNote(pinError),
        ],
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          FormNote(_error!),
          if (_error == 'Verify your email address before adding a PG.')
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const VerifyEmailScreen()),
                ),
                child: const Text('Verify my email'),
              ),
            ),
        ],
        const SizedBox(height: Space.md),
        BusyFilledButton(label: 'Create my PG', busy: _busy, onPressed: _busy ? null : _submit),
        const SizedBox(height: Space.xs),
        Text(
          'Your PG goes live today on a free month. No payment now.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.pinned,
    required this.busy,
    required this.onUse,
    required this.onClear,
  });

  final bool pinned;
  final bool busy;
  final VoidCallback? onUse;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (pinned) {
      return Row(
        children: [
          Icon(Icons.place_rounded, color: t.colorScheme.primary),
          const SizedBox(width: Space.xs),
          Expanded(child: Text('Map pin added from your location', style: t.textTheme.bodyMedium)),
          TextButton(onPressed: onClear, child: const Text('Remove')),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: onUse,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.my_location_rounded),
      label: const Text('Use my current location (optional)'),
    );
  }
}
