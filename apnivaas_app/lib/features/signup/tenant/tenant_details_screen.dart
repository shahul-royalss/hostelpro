/// Your details — a tenant's step 4 (docs/self-signup-onboarding-spec.md, Flows 4 and 7):
/// name, phone, gender, date of birth, emergency contact, a profile photo (needed before a join
/// request) and an optional ID document.
///
/// The photo and the document upload the moment they are picked, so a failure is said next to
/// the thing that failed. The text fields save through `me_update_profile` on Continue.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/device/signup_device.dart';
import '../../../data/media/avatar_image.dart';
import '../../../data/models/failure.dart';
import '../../../data/models/signup.dart';
import '../../../data/repositories/signup_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../auth/auth_scaffold.dart';
import '../../common/form_parts.dart';
import '../signup_widgets.dart';

const genders = <String, String>{'male': 'Male', 'female': 'Female', 'other': 'Other'};

/// Turns picked bytes into the avatar JPEG. A seam so widget tests skip the image codec.
typedef AvatarEncoder = Future<Uint8List> Function(Uint8List picked);

final avatarEncoderProvider = Provider<AvatarEncoder>((_) => squareAvatarJpeg);

class TenantDetailsScreen extends ConsumerStatefulWidget {
  const TenantDetailsScreen({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<TenantDetailsScreen> createState() => _TenantDetailsScreenState();
}

class _TenantDetailsScreenState extends ConsumerState<TenantDetailsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  String? _gender;
  DateTime? _dob;
  bool _hasPhoto = false;
  Uint8List? _photoPreview;
  bool _photoBusy = false;
  String? _photoError;
  String _docKind = 'aadhaar_masked';
  bool _docBusy = false;
  int _docsAdded = 0;
  String? _docError;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _name.text = session?.fullName ?? '';
    _phone.text = session?.phone ?? '';
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ref.read(signupApiProvider).myProfile();
      if (!mounted) return;
      setState(() {
        if ((me.fullName ?? '').isNotEmpty && _name.text.isEmpty) _name.text = me.fullName!;
        if ((me.phone ?? '').isNotEmpty && _phone.text.isEmpty) _phone.text = me.phone!;
        _gender ??= genders.containsKey(me.gender) ? me.gender : null;
        _dob ??= me.dateOfBirth;
        if (_emName.text.isEmpty) _emName.text = me.emergencyName ?? '';
        if (_emPhone.text.isEmpty) _emPhone.text = me.emergencyPhone ?? '';
        _hasPhoto = _hasPhoto || me.avatarPath != null;
      });
    } catch (_) {
      // A prefill, not a requirement: the form works empty.
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _emName, _emPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _explainCamera() => askInWords(
        context,
        title: 'Use the camera?',
        message: 'Apnivaas will ask to use your camera so you can take this photo now. It is '
            'used only for the picture you take. You can choose an existing photo instead.',
      );

  Future<CaptureSource?> _chooseSource() => showApnivaasSheet<CaptureSource>(
        context: context,
        title: 'Add a photo',
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(CaptureSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(CaptureSource.gallery),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      );

  Future<void> _addPhoto() async {
    final source = await _chooseSource();
    if (source == null || !mounted) return;
    setState(() {
      _photoBusy = true;
      _photoError = null;
    });
    try {
      final picked = await ref
          .read(signupPhotoSourceProvider)
          .pick(source, explainCamera: _explainCamera);
      if (picked == null) {
        if (mounted) setState(() => _photoBusy = false);
        return;
      }
      final jpeg = await ref.read(avatarEncoderProvider)(picked.bytes);
      await ref.read(signupApiProvider).uploadAvatar(jpeg);
      if (!mounted) return;
      setState(() {
        _photoBusy = false;
        _hasPhoto = true;
        _photoPreview = jpeg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoBusy = false;
        _photoError = switch (e) {
          SignupFailure(:final message) => message,
          AppFailure(:final message) => message,
          FormatException(:final message) => message,
          _ => 'That photo could not be used. Please try again.',
        };
      });
    }
  }

  Future<void> _addDocument() async {
    final source = await _chooseSource();
    if (source == null || !mounted) return;
    setState(() {
      _docBusy = true;
      _docError = null;
    });
    try {
      final picked = await ref
          .read(signupPhotoSourceProvider)
          .pick(source, explainCamera: _explainCamera, forDocument: true);
      if (picked == null) {
        if (mounted) setState(() => _docBusy = false);
        return;
      }
      await ref.read(signupApiProvider).addDocument(kind: _docKind, bytes: picked.bytes);
      if (!mounted) return;
      setState(() {
        _docBusy = false;
        _docsAdded++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _docBusy = false;
        _docError = switch (e) {
          SignupFailure(:final message) => message,
          AppFailure(:final message) => message,
          _ => 'That file could not be used. Please try again.',
        };
      });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 10, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref.read(signupApiProvider).updateProfile(
            fullName: _t(_name),
            phone: _t(_phone),
            gender: _gender,
            dateOfBirth: _dob,
            emergencyName: _t(_emName),
            emergencyPhone: _t(_emPhone),
          );
      // The name and phone live on the session too; a background re-read keeps headers right.
      ref.read(authControllerProvider.notifier).reload();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSaved();
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        final field = switch (f.field) {
          'full_name' || 'name' => 'full_name',
          'phone' => 'phone',
          'gender' => 'gender',
          'date_of_birth' => 'date_of_birth',
          'emergency_contact_name' => 'emergency_contact_name',
          'emergency_contact_phone' => 'emergency_contact_phone',
          _ => null,
        };
        if (field == null) {
          _error = f.message;
        } else {
          _fieldErrors = {field: f.message};
          _form.currentState?.validate();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final busy = _busy || _photoBusy || _docBusy;
    Widget gap() => const SizedBox(height: Space.sm);
    String? server(String f) => _fieldErrors[f];
    final phoneChars = [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))];

    return SignupPage(
      showSignOut: true,
      children: [
        const SizedBox(height: Space.md),
        const StepIndicator(step: 4),
        const SizedBox(height: Space.md),
        const AuthHeading(
          title: 'Your details',
          message: 'Your PG sees these when you ask to join.',
          icon: ClayIcons.kyc,
        ),
        const SizedBox(height: Space.md),
        _PhotoCard(
          hasPhoto: _hasPhoto,
          preview: _photoPreview,
          busy: _photoBusy,
          onPressed: busy ? null : _addPhoto,
        ),
        if (_photoError != null) ...[const SizedBox(height: Space.xs), FormNote(_photoError!)],
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
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) {
                  final n = (v ?? '').trim().length;
                  return server('full_name') ??
                      (n < 2 || n > 80 ? 'Enter your full name (2 to 80 characters).' : null);
                },
              ),
              gap(),
              TextFormField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneChars,
                decoration: const InputDecoration(labelText: 'Mobile number'),
                validator: (v) =>
                    server('phone') ??
                    (looksLikeIndianMobile(v ?? '') ? null : 'Enter a valid 10-digit mobile number.'),
              ),
              GroupLabel('Gender', error: server('gender')),
              ChoicePills<String>(
                options: genders,
                selected: _gender,
                enabled: !_busy,
                onSelected: (g) => setState(() => _gender = g),
              ),
              GroupLabel('Date of birth', error: server('date_of_birth')),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickDob,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: AlignmentDirectional.centerStart,
                ),
                icon: const Icon(Icons.cake_outlined),
                label: Text(_dob == null ? 'Choose a date' : DateFormat('d MMMM yyyy').format(_dob!)),
              ),
              const GroupLabel('Emergency contact'),
              TextFormField(
                controller: _emName,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: "Contact's name"),
                validator: (v) {
                  final n = (v ?? '').trim().length;
                  return server('emergency_contact_name') ??
                      (n != 0 && (n < 2 || n > 80)
                          ? "Enter the emergency contact's name (2 to 80 characters)."
                          : null);
                },
              ),
              gap(),
              TextFormField(
                controller: _emPhone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneChars,
                decoration: const InputDecoration(labelText: "Contact's mobile number"),
                validator: (v) {
                  final s = (v ?? '').trim();
                  return server('emergency_contact_phone') ??
                      (s.isNotEmpty && !looksLikeIndianMobile(s)
                          ? 'Enter a valid 10-digit number for the emergency contact.'
                          : null);
                },
              ),
            ],
          ),
        ),
        const GroupLabel('ID document (optional)'),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Upload a '),
            TextSpan(text: 'masked', style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const TextSpan(
              text: ' Aadhaar (download it from the UIDAI site with only the last 4 digits '
                  'showing) or another ID.',
            ),
          ]),
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.xs),
        DropdownButtonFormField<String>(
          initialValue: _docKind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Type of document'),
          items: [
            for (final e in documentKinds.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: busy ? null : (v) => setState(() => _docKind = v ?? _docKind),
        ),
        const SizedBox(height: Space.xs),
        OutlinedButton.icon(
          onPressed: busy ? null : _addDocument,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: _docBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file_rounded),
          label: Text(_docsAdded == 0 ? 'Add a document' : 'Add another document'),
        ),
        if (_docsAdded > 0) ...[
          const SizedBox(height: Space.xs),
          FormNote(
            _docsAdded == 1 ? 'Document added.' : '$_docsAdded documents added.',
            tone: FormNoteTone.success,
          ),
        ],
        if (_docError != null) ...[const SizedBox(height: Space.xs), FormNote(_docError!)],
        if (_error != null) ...[const SizedBox(height: Space.sm), FormNote(_error!)],
        const SizedBox(height: Space.lg),
        if (!_hasPhoto) ...[
          const InfoNote(message: 'Add a profile photo before you ask a PG to take you in.'),
          const SizedBox(height: Space.sm),
        ],
        BusyFilledButton(label: 'Continue', busy: _busy, onPressed: busy ? null : _continue),
      ],
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.hasPhoto,
    required this.preview,
    required this.busy,
    required this.onPressed,
  });

  final bool hasPhoto;
  final Uint8List? preview;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Row(
      children: [
        Semantics(
          label: hasPhoto ? 'Profile photo added' : 'No profile photo yet',
          child: CircleAvatar(
            radius: 36,
            backgroundColor: scheme.surfaceContainerHigh,
            foregroundImage: preview == null ? null : MemoryImage(preview!),
            child: busy
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(
                    hasPhoto ? Icons.check_circle_rounded : Icons.person_rounded,
                    size: 32,
                    color: hasPhoto ? scheme.primary : scheme.onSurfaceVariant,
                  ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Profile photo', style: t.textTheme.titleMedium),
              Text(
                hasPhoto ? 'Your PG will see this photo.' : 'A clear photo of your face.',
                style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Space.xxs),
              TextButton(
                onPressed: onPressed,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(hasPhoto ? 'Change photo' : 'Add photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
