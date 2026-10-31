/// Owner → PG profile (R5): the logo, up to six photos, name, description, amenities, house
/// rules and map pin that people see on the PG's page, and whether it shows in Find a PG.
///
/// Photos are shrunk and re-encoded on this phone (which drops EXIF, so no GPS tag rides
/// along), uploaded only when Save is pressed, then attached with `ow_update_pg_profile`, which
/// checks every key against the bucket. A key that went up stays on its photo, so retrying a
/// failed save does not upload it twice.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/device/signup_device.dart';
import '../../../data/media/avatar_image.dart' show squareAvatarJpeg;
import '../../../data/media/pg_photo_image.dart' show pgCoverJpeg;
import '../../../data/models/failure.dart';
import '../../../data/models/pg_profile.dart';
import '../../../data/providers.dart' show hostelProvider;
import '../../../data/repositories/pg_profile_repository.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../common/form_parts.dart';
import '../../signup/signup_widgets.dart' show askInWords;
import '../../student/pg/pg_profile_page.dart';
import '../../student/pg/pg_widgets.dart';
import '../../student/stay_screens.dart' show stayErrorText;
import '../owner_providers.dart' show myHostelsProvider;
import '../widgets/owner_header.dart';
import 'owner_reviews_screen.dart';

typedef PgPhotoEncoder = Future<Uint8List> Function(Uint8List picked);

/// Square 512 px JPEG for the round logo. A provider so a test can hand over bytes without
/// decoding an image.
final pgLogoEncoderProvider = Provider<PgPhotoEncoder>((_) => squareAvatarJpeg);

/// Longest side 1600 px, under 2 MB.
final pgCoverEncoderProvider = Provider<PgPhotoEncoder>((_) => pgCoverJpeg);

/// The server keeps up to 20,000 characters of rules; a phone screen of them is plenty here.
const pgRulesMax = 2000;

class PgProfileEditorScreen extends ConsumerWidget {
  const PgProfileEditorScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => PgProfileEditorScreen(hostelId: hostelId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(ownerPgProfileProvider(hostelId));
    // Kept through a refresh: the form is keyed to the PG, not to a load, so the refresh a
    // save triggers never resets what is on screen.
    final value = profile.value;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerSubpageHeader(title: 'PG profile', subtitle: value?.name ?? 'What tenants see'),
          Expanded(
            child: value != null
                ? _Editor(key: ValueKey(hostelId), hostelId: hostelId, initial: value)
                : profile.hasError
                    ? ListView(
                        padding: OwnerRhythm.pagePadding,
                        children: [
                          EmptyState.error(
                            message: stayErrorText(profile.error!),
                            onRetry: () => ref.invalidate(ownerPgProfileProvider(hostelId)),
                          ),
                        ],
                      )
                    : ListView(
                        padding: OwnerRhythm.pagePadding,
                        children: const [
                          ListSkeleton(rows: 4, semanticLabel: 'Loading your PG profile'),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

/// A photo on the form: one already saved ([path] only), or one picked on this phone
/// ([bytes]) that gets its [path] when it is uploaded.
final class _Photo {
  _Photo.saved(String this.path) : bytes = null;
  _Photo.picked(Uint8List this.bytes);

  String? path;
  final Uint8List? bytes;
}

enum _PhotoAction {
  camera(Icons.photo_camera_rounded, 'Take a photo'),
  gallery(Icons.photo_library_rounded, 'Choose from gallery'),
  makeMain(Icons.star_outline_rounded, 'Make it the main photo'),
  remove(Icons.delete_outline_rounded, 'Remove');

  const _PhotoAction(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.hostelId, required this.initial});

  final String hostelId;
  final OwnerPgProfile initial;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  /// What the server holds; the form is dirty wherever it differs.
  late OwnerPgProfile _base = widget.initial;
  late final _name = TextEditingController(text: _base.name);
  late final _description = TextEditingController(text: _base.description ?? '');
  late final _rules = TextEditingController(text: _base.rules ?? '');
  late final Set<String> _amenities = {..._base.amenities};
  late bool _listed = _base.listed;
  late _Photo? _logo = _base.logoPath == null ? null : _Photo.saved(_base.logoPath!);
  late final List<_Photo> _covers = [for (final p in _base.coverPaths) _Photo.saved(p)];

  /// A new pin, sent with the next save.
  LocationFix? _pin;

  String? _nameError, _descriptionError, _rulesError, _photoError, _pinNote, _error;

  /// What the save is doing, on its button; null when not saving.
  String? _progress;
  bool _picking = false;
  bool _locating = false;

  bool get _saving => _progress != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  bool get _profileChanged {
    final b = _base;
    return _name.text.trim() != b.name ||
        _description.text.trim() != (b.description ?? '') ||
        _listed != b.listed ||
        _pin != null ||
        _amenities.length != b.amenities.toSet().length ||
        !b.amenities.every(_amenities.contains) ||
        _logo?.path != b.logoPath ||
        (_logo != null && _logo!.path == null) ||
        _covers.any((c) => c.path == null) ||
        !listEquals([for (final c in _covers) c.path], b.coverPaths);
  }

  bool get _rulesChanged => _rules.text.trim() != (_base.rules ?? '');

  bool get _dirty => _profileChanged || _rulesChanged;

  Future<bool> _explainCamera() => askInWords(
        context,
        title: 'Use the camera?',
        message: 'Apnivaas will ask to use your camera so you can photograph your PG now. It is '
            'used only for the pictures you take. You can choose existing photos instead.',
      );

  Future<_PhotoAction?> _ask(String title, List<_PhotoAction> actions) =>
      showApnivaasSheet<_PhotoAction>(
        context: context,
        title: title,
        // The sheet's ground is a coloured box; the tiles' ink needs a Material above it.
        builder: (ctx) => Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in actions)
                ListTile(
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  onTap: () => Navigator.of(ctx).pop(a),
                ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      );

  /// Camera or gallery, then shrunk and re-encoded. Null when the owner backed out.
  Future<Uint8List?> _photoFrom(_PhotoAction source, {required bool logo}) async {
    setState(() {
      _picking = true;
      _photoError = null;
    });
    try {
      final picked = await ref.read(signupPhotoSourceProvider).pick(
            source == _PhotoAction.camera ? CaptureSource.camera : CaptureSource.gallery,
            explainCamera: _explainCamera,
            // The document setting: 1600 px and the rear camera, which suits a building.
            forDocument: true,
          );
      if (picked == null || !mounted) return null;
      return await ref.read(logo ? pgLogoEncoderProvider : pgCoverEncoderProvider)(picked.bytes);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _photoError = f.message);
    } on FormatException catch (f) {
      if (mounted) setState(() => _photoError = f.message);
    } catch (_) {
      if (mounted) setState(() => _photoError = 'That photo could not be used. Please try again.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    return null;
  }

  Future<void> _editLogo() async {
    final action = await _ask('Logo', [
      _PhotoAction.camera,
      _PhotoAction.gallery,
      if (_logo != null) _PhotoAction.remove,
    ]);
    if (action == null || !mounted) return;
    if (action == _PhotoAction.remove) {
      setState(() => _logo = null);
      return;
    }
    final jpeg = await _photoFrom(action, logo: true);
    if (jpeg != null && mounted) setState(() => _logo = _Photo.picked(jpeg));
  }

  Future<void> _addCover() async {
    final action = await _ask('Add a photo', [_PhotoAction.camera, _PhotoAction.gallery]);
    if (action == null || !mounted) return;
    final jpeg = await _photoFrom(action, logo: false);
    if (jpeg != null && mounted && _covers.length < pgMaxCovers) {
      setState(() => _covers.add(_Photo.picked(jpeg)));
    }
  }

  Future<void> _editCover(int index) async {
    final action = await _ask('Photo ${index + 1} of ${_covers.length}', [
      if (index > 0) _PhotoAction.makeMain,
      _PhotoAction.remove,
    ]);
    if (action == null || !mounted || index >= _covers.length) return;
    setState(() {
      final photo = _covers.removeAt(index);
      if (action == _PhotoAction.makeMain) _covers.insert(0, photo);
    });
  }

  Future<void> _usePin() async {
    setState(() {
      _locating = true;
      _pinNote = null;
    });
    final outcome = await ref.read(deviceLocatorProvider).locate(
          explain: () => askInWords(
            context,
            title: 'Use your location?',
            message: 'Stand at your PG. Apnivaas will ask your phone for your exact location to '
                'pin it on the map, so tenants nearby can find it. They see how far away it is, '
                'never the pin itself.',
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
          _pinNote = message;
      }
    });
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard your changes?'),
        content: const Text('The changes to this PG profile have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final description = _description.text.trim();
    final rules = _rules.text.trim();
    setState(() {
      _nameError = name.length < 2 || name.length > 120
          ? 'Enter a PG name between 2 and 120 characters.'
          : null;
      _descriptionError = description.length > pgDescriptionMax
          ? 'Keep the description under 500 characters.'
          : null;
      _rulesError =
          rules.length > pgRulesMax ? 'Keep the house rules under 2,000 characters.' : null;
      _photoError = null;
      _pinNote = null;
      _error = null;
    });
    if (_nameError != null || _descriptionError != null || _rulesError != null) return;

    // Read once: a save that outlives this screen still lands, and still refreshes.
    final api = ref.read(pgProfileApiProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final id = widget.hostelId;
    final profileChanged = _profileChanged, rulesChanged = _rulesChanged;
    final pending = [
      if (_logo case final logo? when logo.path == null) (logo, PgMediaKind.logo),
      for (final c in _covers)
        if (c.path == null) (c, PgMediaKind.cover),
    ];
    void step(String words) {
      if (mounted) setState(() => _progress = words);
    }

    try {
      for (final (i, (photo, kind)) in pending.indexed) {
        step(pending.length == 1
            ? 'Uploading the photo…'
            : 'Uploading photo ${i + 1} of ${pending.length}…');
        photo.path = await api.uploadMedia(id, kind, photo.bytes!);
      }
      step('Saving…');
      if (profileChanged) {
        final saved = await api.saveProfile(
          hostelId: id,
          name: name,
          description: description.isEmpty ? null : description,
          amenities: orderedAmenities(_amenities),
          logoPath: _logo?.path,
          coverPaths: [for (final c in _covers) c.path!],
          listed: _listed,
          latitude: _pin?.latitude,
          longitude: _pin?.longitude,
        );
        // Gone mid-save: the controllers are disposed, and only the refresh below matters.
        if (mounted) _adopt(saved.withRules(_base.rules));
      }
      if (rulesChanged) {
        await api.updateRules(id, rules);
        _base = _base.withRules(rules.isEmpty ? null : rules);
      }
      container
        ..invalidate(ownerPgProfileProvider(id))
        ..invalidate(pgPublicProfileProvider(id))
        ..invalidate(hostelProvider(id))
        ..invalidate(myHostelsProvider);
      if (mounted) setState(() => _progress = null);
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Saved. People looking for a PG see the new profile.'),
      ));
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        switch (f.field) {
          case 'name':
            _nameError = f.message;
          case 'description':
            _descriptionError = f.message;
          case 'logo':
            _photoError = f.message;
            // The key was refused, so the photo goes up again under a new one.
            if (_logo?.bytes != null) _logo!.path = null;
          case 'covers':
            _photoError = f.message;
            for (final c in _covers) {
              if (c.bytes != null) c.path = null;
            }
          case 'location':
            _pinNote = f.message;
          default:
            _error = f.message;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = stayErrorText(e);
        });
      }
    }
  }

  /// Takes the server's copy of a saved profile as the new baseline, and shows what it
  /// normalised (a tidied name, the sorted amenities) without disturbing the photos on screen.
  void _adopt(OwnerPgProfile saved) {
    _base = saved;
    _pin = null;
    if (_name.text.trim() != saved.name) _name.text = saved.name;
    if (_description.text.trim() != (saved.description ?? '')) {
      _description.text = saved.description ?? '';
    }
    _amenities
      ..clear()
      ..addAll(saved.amenities);
    _listed = saved.listed;
    if (_logo?.path != saved.logoPath) {
      _logo = saved.logoPath == null ? null : _Photo.saved(saved.logoPath!);
    }
    if (!listEquals([for (final c in _covers) c.path], saved.coverPaths)) {
      _covers
        ..clear()
        ..addAll(saved.coverPaths.map(_Photo.saved));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final saving = _saving;
    final dirty = _dirty;
    final locked = saving || _picking;
    final pinned = _pin != null || _base.hasPin;
    return PopScope(
      canPop: !dirty || saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: OwnerRhythm.pagePadding,
              children: [
                const _Group(title: 'Logo and photos'),
                _LogoRow(photo: _logo, onTap: locked ? null : _editLogo),
                const SizedBox(height: Space.md),
                _CoverGrid(
                  covers: _covers,
                  onAdd: locked ? null : _addCover,
                  onTap: locked ? null : _editCover,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Up to $pgMaxCovers photos; the first is the main one. Photos are made smaller '
                  'and their location tags removed before upload.',
                  style: muted,
                ),
                if (_picking) ...[
                  const SizedBox(height: Space.xs),
                  const LinearProgressIndicator(semanticsLabel: 'Preparing the photo'),
                ],
                if (_photoError != null) ...[
                  const SizedBox(height: Space.xs),
                  FormNote(_photoError!),
                ],
                const SizedBox(height: OwnerRhythm.sectionGap),
                const _Group(title: 'About your PG'),
                TextField(
                  controller: _name,
                  enabled: !saving,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'PG name',
                    errorText: _nameError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() => _nameError = null),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _description,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: pgDescriptionMax,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    alignLabelWithHint: true,
                    errorText: _descriptionError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() => _descriptionError = null),
                ),
                const SizedBox(height: OwnerRhythm.sectionGap),
                const _Group(title: 'Amenities'),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: [
                    for (final MapEntry(:key, :value) in pgAmenities.entries)
                      FilterChip(
                        avatar: Icon(amenityIcon(key), size: IconSize.sm),
                        label: Text(value),
                        showCheckmark: false,
                        selected: _amenities.contains(key),
                        onSelected: saving
                            ? null
                            : (on) => setState(
                                  () => on ? _amenities.add(key) : _amenities.remove(key),
                                ),
                      ),
                  ],
                ),
                const SizedBox(height: OwnerRhythm.sectionGap),
                const _Group(title: 'House rules'),
                TextField(
                  controller: _rules,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 10,
                  maxLength: pgRulesMax,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'House rules (optional)',
                    alignLabelWithHint: true,
                    errorText: _rulesError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() => _rulesError = null),
                ),
                const SizedBox(height: OwnerRhythm.sectionGap),
                const _Group(title: 'Finding your PG'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _listed,
                  onChanged: saving ? null : (v) => setState(() => _listed = v),
                  title: const Text('Show in Find a PG'),
                  subtitle: const Text('People looking for a PG can see this page and ask to '
                      'join. Your residents and staff see it either way.'),
                ),
                const SizedBox(height: Space.sm),
                FlatSurface(
                  borderRadius: Radii.rSurface,
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.place_outlined, color: t.colorScheme.primary),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pin != null
                                      ? 'New pin, saved with your changes'
                                      : _base.hasPin
                                          ? 'Pinned on the map'
                                          : 'Not on the map yet',
                                  style: t.textTheme.titleSmall,
                                ),
                                const SizedBox(height: Space.hair),
                                Text(
                                  'Tenants nearby see how far your PG is, never the pin. '
                                  'Stand at the PG to set it.',
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      OutlinedButton.icon(
                        onPressed: saving || _locating ? null : _usePin,
                        icon: _locating
                            ? const SizedBox.square(
                                dimension: IconSize.sm,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded, size: IconSize.sm),
                        label: Text(pinned ? 'Move the pin to where I am' : 'Pin where I am now'),
                      ),
                      if (_pinNote != null) ...[
                        const SizedBox(height: Space.xs),
                        FormNote(_pinNote!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: OwnerRhythm.sectionGap),
                ListGroup(
                  children: [
                    ListRow(
                      icon: ClayIcons.reviews,
                      title: 'Reviews',
                      subtitle: 'What residents say about this PG',
                      onTap: () => Navigator.of(context)
                          .push(OwnerReviewsScreen.route(widget.hostelId)),
                    ),
                    ListRow(
                      icon: ClayIcons.rooms,
                      title: 'See your PG\'s page',
                      subtitle: 'As people looking for a PG see it',
                      onTap: () => Navigator.of(context)
                          .push(PgProfilePage.route(widget.hostelId, title: _base.name)),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  FormNote(_error!),
                ],
                const SizedBox(height: Space.lg),
                const InfoNote(
                  icon: Icons.lock_outline_rounded,
                  message: 'People looking for a PG see the photos, name, description, '
                      'amenities, rules and reviews. Your phone number, the full address and '
                      'the map pin stay private.',
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.md),
              child: BusyFilledButton(
                label: 'Save changes',
                busy: saving,
                busyLabel: _progress,
                onPressed: dirty && !_picking ? _save : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group's heading, with the owner pages' rhythm under it.
class _Group extends StatelessWidget {
  const _Group({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: OwnerRhythm.headingGap),
        child: SectionHeader(title: title, size: SectionHeaderSize.card),
      );
}

class _LogoRow extends StatelessWidget {
  const _LogoRow({required this.photo, required this.onTap});

  final _Photo? photo;
  final VoidCallback? onTap;

  static const _size = 72.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: photo == null ? 'Add a logo' : 'Change or remove the logo',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.rSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xxs),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PgLogo(path: photo?.path, bytes: photo?.bytes, size: _size),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(Space.xxs),
                      decoration: BoxDecoration(
                        color: t.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.colorScheme.surface, width: 2),
                      ),
                      child: Icon(Icons.photo_camera_rounded,
                          size: 14, color: t.colorScheme.onPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(photo == null ? 'Add a logo' : 'Logo', style: t.textTheme.titleSmall),
                    const SizedBox(height: Space.hair),
                    Text('Shown round, beside your PG\'s name', style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverGrid extends StatelessWidget {
  const _CoverGrid({required this.covers, required this.onAdd, required this.onTap});

  final List<_Photo> covers;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final radius = BorderRadius.circular(Radii.control);
    final placeholder = ColoredBox(color: t.colorScheme.surfaceContainerHighest);
    final tap = onTap;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.xs,
      crossAxisSpacing: Space.xs,
      childAspectRatio: 4 / 3,
      children: [
        for (var i = 0; i < covers.length; i++)
          Semantics(
            button: true,
            enabled: tap != null,
            label: 'Photo ${i + 1} of ${covers.length}${i == 0 ? ', the main photo' : ''}',
            hint: 'Opens options',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PgMediaImage(
                    path: covers[i].path,
                    bytes: covers[i].bytes,
                    fallback: placeholder,
                    cacheWidth: 400,
                  ),
                  if (i == 0)
                    Positioned(
                      left: Space.xxs,
                      top: Space.xxs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.xs, vertical: Space.hair),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: radius,
                        ),
                        child: Text('Main',
                            style: t.textTheme.labelSmall?.copyWith(color: Colors.white)),
                      ),
                    ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: tap == null ? null : () => tap(i)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (covers.length < pgMaxCovers)
          Semantics(
            button: true,
            enabled: onAdd != null,
            label: 'Add a photo',
            excludeSemantics: true,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onAdd,
                borderRadius: radius,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: t.colorScheme.outlineVariant),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xs),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: t.colorScheme.primary),
                            const SizedBox(height: Space.xxs),
                            Text('Add photo', style: t.textTheme.labelMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
