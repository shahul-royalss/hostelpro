import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart' show sessionProvider;
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/device/signup_device.dart';
import 'package:mobile/data/models/pg_profile.dart';
import 'package:mobile/data/people_providers.dart' show signedUrlProvider;
import 'package:mobile/data/repositories/pg_profile_repository.dart';
import 'package:mobile/data/repositories/signup_repository.dart' show SignupFailure;
import 'package:mobile/features/owner/profile/owner_reviews_screen.dart';
import 'package:mobile/features/owner/profile/pg_profile_editor_screen.dart';
import 'package:mobile/features/student/pg/review_screen.dart';

/// The owner's PG profile editor, the owner's reviews list and the tenant's review (R5).

const _hostelId = 'h-1';

class _FakePgApi implements PgProfileApi {
  _FakePgApi(this.profile);

  OwnerPgProfile profile;
  final uploads = <PgMediaKind>[];
  final saves = <Map<String, Object?>>[];
  final rules = <String>[];
  final reviewSaves = <({int rating, String? comment})>[];
  List<PgReview> allReviews = const [];
  MyReview? mine;

  /// Thrown by the next save, then cleared.
  Object? saveError;

  @override
  Future<OwnerPgProfile> ownerProfile(String hostelId) async => profile;

  @override
  Future<String> uploadMedia(String hostelId, PgMediaKind kind, Uint8List jpeg) async {
    uploads.add(kind);
    return '$hostelId/${kind.name}/new${uploads.length}.jpg';
  }

  @override
  Future<OwnerPgProfile> saveProfile({
    required String hostelId,
    required String name,
    required String? description,
    required List<String> amenities,
    required String? logoPath,
    required List<String> coverPaths,
    bool? listed,
    double? latitude,
    double? longitude,
  }) async {
    final e = saveError;
    if (e != null) {
      saveError = null;
      throw e;
    }
    saves.add({
      'name': name,
      'description': description,
      'amenities': amenities,
      'logo': logoPath,
      'covers': coverPaths,
      'listed': listed,
      'lat': latitude,
      'lng': longitude,
    });
    return profile = OwnerPgProfile(
      hostelId: hostelId,
      name: name,
      description: description,
      amenities: [...amenities]..sort(),
      logoPath: logoPath,
      coverPaths: coverPaths,
      listed: listed ?? profile.listed,
      latitude: latitude ?? profile.latitude,
      longitude: longitude ?? profile.longitude,
    );
  }

  @override
  Future<void> updateRules(String hostelId, String value) async => rules.add(value);

  @override
  Future<PgPublicProfile> pgProfile(String hostelId) async => PgPublicProfile(
        hostelId: hostelId,
        name: profile.name,
        ratingAvg: allReviews.isEmpty ? null : 4.3,
        ratingCount: allReviews.length,
      );

  @override
  Future<List<PgReview>> reviews(String hostelId, {int limit = 20, int offset = 0}) async =>
      allReviews.skip(offset).take(limit).toList();

  @override
  Future<MyReview?> myReview() async => mine;

  @override
  Future<MyReview?> saveReview({required int rating, String? comment}) async {
    reviewSaves.add((rating: rating, comment: comment));
    return mine = MyReview(reviewId: 'r-1', rating: rating, comment: comment);
  }
}

class _FakePhotos implements SignupPhotoSource {
  int picks = 0;

  @override
  Future<PickedImage?> pick(
    CaptureSource source, {
    required ExplainFirst explainCamera,
    bool forDocument = false,
  }) async {
    picks++;
    return PickedImage(bytes: Uint8List.fromList([picks]), name: 'p$picks.jpg');
  }
}

class _FakeLocator implements DeviceLocator {
  @override
  Future<LocationOutcome> locate({required ExplainFirst explain}) async =>
      const LocationFix(12.9352, 77.6245);
}

OwnerPgProfile _profile({int covers = 1, String? logo, String? rules}) => OwnerPgProfile(
      hostelId: _hostelId,
      name: 'Sunrise PG',
      description: 'Ten minutes from the metro.',
      amenities: const ['wifi'],
      logoPath: logo,
      coverPaths: [for (var i = 0; i < covers; i++) '$_hostelId/cover/c$i.jpg'],
      listed: true,
      rules: rules,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  _FakePgApi api, {
  _FakePhotos? photos,
  double textScale = 1.0,
  Size size = const Size(800, 2400),
  bool pushed = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      sessionProvider.overrideWithValue(null),
      pgProfileApiProvider.overrideWithValue(api),
      signupPhotoSourceProvider.overrideWithValue(photos ?? _FakePhotos()),
      deviceLocatorProvider.overrideWithValue(_FakeLocator()),
      // Nothing is decoded in a test: the encoders hand the picked bytes straight back.
      pgLogoEncoderProvider.overrideWithValue((b) async => b),
      pgCoverEncoderProvider.overrideWithValue((b) async => b),
      signedUrlProvider.overrideWith((ref, key) async => null),
    ],
    child: MaterialApp(
      theme: ApnivaasTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => screen)),
                    child: const Text('Open'),
                  ),
                ),
              ),
            )
          : screen,
    ),
  ));
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(of: find.text('Save changes'), matching: find.byType(FilledButton)));

Future<void> _chooseFromGallery(WidgetTester tester, Finder opener) async {
  await tester.ensureVisible(opener);
  await tester.tap(opener);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose from gallery'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

void main() {
  group('owner PG profile editor', () {
    testWidgets('new photos go up first, then the profile is saved with their keys',
        (tester) async {
      final api = _FakePgApi(_profile());
      await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api);

      expect(find.text('Sunrise PG'), findsWidgets);
      expect(_saveButton(tester).onPressed, isNull, reason: 'nothing has changed yet');

      await tester.tap(find.widgetWithText(FilterChip, 'Food'));
      await tester.pump();
      await _chooseFromGallery(tester, find.text('Add photo'));
      await _chooseFromGallery(tester, find.text('Add a logo'));
      expect(_saveButton(tester).onPressed, isNotNull);

      await _save(tester);

      expect(api.uploads, [PgMediaKind.logo, PgMediaKind.cover]);
      expect(api.saves, hasLength(1));
      final saved = api.saves.single;
      expect(saved['amenities'], ['wifi', 'food'], reason: 'display order, as the server sorts');
      expect(saved['logo'], '$_hostelId/logo/new1.jpg');
      expect(saved['covers'], ['$_hostelId/cover/c0.jpg', '$_hostelId/cover/new2.jpg']);
      expect(saved['listed'], isTrue);
      expect(saved['lat'], isNull, reason: 'the pin is kept unless a new one is dropped');
      expect(api.rules, isEmpty, reason: 'the rules did not change');
      expect(find.textContaining('Saved.'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull, reason: 'the saved copy is the new baseline');
    });

    testWidgets('a refused name lands under the name field', (tester) async {
      final api = _FakePgApi(_profile())
        ..saveError = const SignupFailure('Enter a PG name between 2 and 120 characters.',
            field: 'name');
      await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api);

      await tester.enterText(find.widgetWithText(TextField, 'PG name'), 'Sunrise PG Annexe');
      await tester.pump();
      await _save(tester);

      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'PG name'));
      expect(field.decoration?.errorText, 'Enter a PG name between 2 and 120 characters.');
      expect(api.saves, isEmpty);
      expect(_saveButton(tester).onPressed, isNotNull, reason: 'the owner can try again');
    });

    testWidgets('a refused logo key is uploaded again under a new key', (tester) async {
      final api = _FakePgApi(_profile())
        ..saveError = const SignupFailure('Upload the logo again.', field: 'logo');
      await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api);

      await _chooseFromGallery(tester, find.text('Add a logo'));
      await _save(tester);
      expect(find.text('Upload the logo again.'), findsOneWidget);

      await _save(tester);
      expect(api.uploads, [PgMediaKind.logo, PgMediaKind.logo]);
      expect(api.saves.single['logo'], '$_hostelId/logo/new2.jpg');
    });

    testWidgets('six photos hide Add; a photo can become the main one or be removed',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final api = _FakePgApi(_profile(covers: 6, logo: '$_hostelId/logo/l.jpg'));
      await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api);

      expect(find.text('Add photo'), findsNothing);

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Photo 3 of 6')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make it the main photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Photo 6 of 6')));
      await tester.pumpAndSettle();
      expect(find.text('Make it the main photo'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Add photo'), findsOneWidget, reason: 'room for one more');

      await tester.tap(find.bySemanticsLabel('Change or remove the logo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      await _save(tester);
      expect(api.uploads, isEmpty);
      expect(api.saves.single['covers'], [
        '$_hostelId/cover/c2.jpg',
        '$_hostelId/cover/c0.jpg',
        '$_hostelId/cover/c1.jpg',
        '$_hostelId/cover/c3.jpg',
        '$_hostelId/cover/c4.jpg',
      ]);
      expect(api.saves.single['logo'], isNull);
      semantics.dispose();
    });

    testWidgets('rules have their own call; a new pin and the listing switch are sent',
        (tester) async {
      final api = _FakePgApi(_profile(rules: 'No smoking.'));
      await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api);

      await tester.enterText(
          find.widgetWithText(TextField, 'House rules (optional)'), 'Gate closes at 10:30 pm.');
      await tester.pump();
      await _save(tester);
      expect(api.rules, ['Gate closes at 10:30 pm.']);
      expect(api.saves, isEmpty, reason: 'only the rules changed');
      // The floating "Saved" note sits over the save bar until it times out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pin where I am now'));
      await tester.tap(find.text('Pin where I am now'));
      await tester.pumpAndSettle();
      expect(find.text('New pin, saved with your changes'), findsOneWidget);
      await tester.tap(find.text('Show in Find a PG'));
      await tester.pump();
      await _save(tester);

      expect(api.saves.single['lat'], 12.9352);
      expect(api.saves.single['lng'], 77.6245);
      expect(api.saves.single['listed'], isFalse);
      expect(find.text('Pinned on the map'), findsOneWidget);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      final api = _FakePgApi(_profile());
      await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api, pushed: true);

      await tester.enterText(find.widgetWithText(TextField, 'PG name'), 'Sunrise PG Annexe');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(api.saves, isEmpty);
    });

    for (final (scale, size) in [(1.0, const Size(320, 3200)), (1.4, const Size(360, 3600))]) {
      testWidgets('fits at ${scale}x on ${size.width.toInt()}dp', (tester) async {
        final api = _FakePgApi(_profile(covers: 5, logo: '$_hostelId/logo/l.jpg'));
        await _pump(tester, const PgProfileEditorScreen(hostelId: _hostelId), api,
            textScale: scale, size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('Add photo'), findsOneWidget);
      });
    }
  });

  group('owner reviews', () {
    List<PgReview> reviews(int n) => [
          for (var i = 0; i < n; i++)
            PgReview(
              reviewId: 'r$i',
              reviewerName: 'Resident $i',
              rating: 1 + i % 5,
              comment: i.isEven ? 'Clean rooms and good food.' : null,
            ),
        ];

    testWidgets('twenty at a time, with the server\'s average', (tester) async {
      final api = _FakePgApi(_profile())..allReviews = reviews(25);
      await _pump(tester, const OwnerReviewsScreen(hostelId: _hostelId), api,
          size: const Size(800, 6000));

      expect(find.text('4.3 out of 5'), findsOneWidget);
      expect(find.text('From 25 reviews'), findsOneWidget);
      expect(find.text('Resident 19'), findsOneWidget);
      expect(find.text('Resident 20'), findsNothing);

      await tester.tap(find.text('Show more reviews'));
      await tester.pumpAndSettle();
      expect(find.text('Resident 24'), findsOneWidget);
      expect(find.text('Show more reviews'), findsNothing);
    });

    testWidgets('no reviews yet says how they arrive', (tester) async {
      await _pump(tester, const OwnerReviewsScreen(hostelId: _hostelId), _FakePgApi(_profile()));
      expect(find.text('No ratings yet'), findsOneWidget);
      expect(find.text('No reviews yet'), findsOneWidget);
    });
  });

  group('tenant review', () {
    testWidgets('stars and words are posted, then can be updated', (tester) async {
      final api = _FakePgApi(_profile());
      await _pump(tester, const ReviewScreen(hostelId: _hostelId), api);

      await tester.tap(find.byTooltip('4 stars'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  Quiet and clean.  ');
      await tester.pump();
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      expect(api.reviewSaves.single.rating, 4);
      expect(api.reviewSaves.single.comment, '  Quiet and clean.  ',
          reason: 'the repository trims; the screen sends what was typed');
    });

    testWidgets('no stars is caught before anything is sent', (tester) async {
      final api = _FakePgApi(_profile());
      await _pump(tester, const ReviewScreen(hostelId: _hostelId), api);

      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();
      expect(find.text('Choose 1 to 5 stars.'), findsOneWidget);
      expect(api.reviewSaves, isEmpty);
    });

    testWidgets('an existing review is prefilled', (tester) async {
      final api = _FakePgApi(_profile())
        ..mine = const MyReview(reviewId: 'r-1', rating: 2, comment: 'Noisy at night.');
      await _pump(tester, const ReviewScreen(hostelId: _hostelId), api);

      expect(find.text('Noisy at night.'), findsOneWidget);
      expect(find.text('Update review'), findsOneWidget);
    });
  });
}
