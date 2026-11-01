import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/i18n/i18n.dart';
import 'package:mobile/core/i18n/language.dart';
import 'package:mobile/core/i18n/strings_hi.dart';
import 'package:mobile/core/i18n/strings_kn.dart';
import 'package:mobile/core/i18n/strings_ml.dart';
import 'package:mobile/core/i18n/strings_ta.dart';
import 'package:mobile/core/i18n/strings_te.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/pg_profile.dart';
import 'package:mobile/features/onboarding/language_screen.dart';
import 'package:mobile/features/student/pg/pg_profile_page.dart' show BedAvailability;
import 'package:mobile/shared/clay/clay.dart';

/// Round 5: the six languages, the first-launch choice, and the kit speaking the choice.

class _MemoryStorage implements LanguageStorage {
  _MemoryStorage([this.value]);
  AppLanguage? value;
  final writes = <AppLanguage>[];

  @override
  Future<AppLanguage?> read() async => value;

  @override
  Future<void> write(AppLanguage language) async {
    writes.add(language);
    value = language;
  }
}

const _tables = {
  'hi': hindiStrings,
  'te': teluguStrings,
  'ta': tamilStrings,
  'ml': malayalamStrings,
  'kn': kannadaStrings,
};

Widget _app(Widget home, {Locale locale = const Locale('en'), List<Object> overrides = const []}) =>
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: ApnivaasTheme.light(),
        locale: locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: home),
      ),
    );

void main() {
  group('the tables', () {
    test('every language carries exactly the same keys', () {
      final keys = hindiStrings.keys.toSet();
      for (final MapEntry(:key, :value) in _tables.entries) {
        expect(value.keys.toSet().difference(keys), isEmpty, reason: '$key has extra keys');
        expect(keys.difference(value.keys.toSet()), isEmpty, reason: '$key is missing keys');
      }
    });

    test('every placeholder survives translation, and nothing is left blank', () {
      final slot = RegExp(r'\{\w+\}');
      for (final MapEntry(key: code, value: table) in _tables.entries) {
        for (final MapEntry(:key, :value) in table.entries) {
          expect(value.trim(), isNotEmpty, reason: '$code: "$key" is blank');
          final want = slot.allMatches(key).map((m) => m[0]).toSet();
          final got = slot.allMatches(value).map((m) => m[0]).toSet();
          expect(got, want, reason: '$code: "$key"');
        }
      }
    });

    test('the six languages, each named in its own script', () {
      expect(AppLanguage.values.map((l) => l.code), ['en', 'hi', 'te', 'ta', 'ml', 'kn']);
      expect(AppLanguage.tryParse('ta'), AppLanguage.tamil);
      expect(AppLanguage.tryParse('xx'), isNull);
    });
  });

  group('translate', () {
    test('English is the key and costs nothing', () {
      expect(translate('Pending fees', 'en'), 'Pending fees');
      expect(translate('Something no table has', 'hi'), 'Something no table has');
    });

    test('an exact sentence', () {
      expect(translate('Pending fees', 'hi'), 'बकाया फ़ीस');
      expect(translate('Sign in', 'te'), 'సైన్ ఇన్');
    });

    test('a sentence with a figure, and a month inside it', () {
      expect(translate('Collected in August', 'hi'), 'अगस्त में वसूला गया');
      expect(translate('Pay ₹6,200 now', 'ta'), 'இப்போது ₹6,200 செலுத்து');
      expect(translate('2 sharing · 1 free', 'kn'), '2 ಶೇರಿಂಗ್ · 1 ಖಾಲಿ');
    });

    test('a figure slot never swallows words', () {
      expect(translate('Tap to open', 'hi'), 'Tap to open');
      expect(translate('3 open', 'hi'), '3 खुली');
    });

    test('arguments fill their slots in every language', () {
      expect(translate('Choose a new password for {email}.', 'en', {'email': 'a@b.co'}),
          'Choose a new password for a@b.co.');
      expect(translate('Choose a new password for {email}.', 'ml', {'email': 'a@b.co'}),
          'a@b.co എന്നതിന് പുതിയ പാസ്‌വേഡ് തിരഞ്ഞെടുക്കുക.');
    });
  });

  group('the kit speaks the chosen language', () {
    testWidgets('a section header and a tile, in Hindi and in English', (tester) async {
      const body = Column(children: [
        SectionHeader(title: 'Quick actions'),
        StatTile(icon: ClayIcons.invoice, label: 'Pending fees', value: '₹0'),
      ]);
      await tester.pumpWidget(_app(body, locale: const Locale('hi')));
      await tester.pumpAndSettle();
      expect(find.text('तुरंत काम'), findsOneWidget);
      expect(find.text('बकाया फ़ीस'), findsOneWidget);

      await tester.pumpWidget(_app(body));
      await tester.pumpAndSettle();
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Pending fees'), findsOneWidget);
    });
  });

  group('first launch', () {
    testWidgets('the language is asked first, and kept', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final storage = _MemoryStorage();
      await tester.pumpWidget(_app(
        const LanguageGate(child: Text('the tour')),
        overrides: [languageStorageProvider.overrideWithValue(storage)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('the tour'), findsNothing);
      expect(find.text('Choose your language'), findsOneWidget);
      for (final l in AppLanguage.values) {
        expect(find.text(l.nativeName), findsOneWidget);
      }

      await tester.tap(find.text('తెలుగు'));
      await tester.pump();
      // Previewed in the choice before it is kept.
      expect(find.text('మీ భాషను ఎంచుకోండి'), findsOneWidget);
      await tester.ensureVisible(find.text('కొనసాగించండి'));
      await tester.tap(find.text('కొనసాగించండి'));
      await tester.pumpAndSettle();

      expect(storage.writes, [AppLanguage.telugu]);
      expect(find.text('the tour'), findsOneWidget);
    });

    testWidgets('a phone that has chosen goes straight on', (tester) async {
      await tester.pumpWidget(_app(
        const LanguageGate(child: Text('the tour')),
        overrides: [languageStorageProvider.overrideWithValue(_MemoryStorage(AppLanguage.hindi))],
      ));
      await tester.pumpAndSettle();
      expect(find.text('the tour'), findsOneWidget);
    });
  });

  group('beds on a PG page: available or not, never how many (round 6)', () {
    PgPublicProfile profile(bool open) =>
        PgPublicProfile(hostelId: 'h', name: 'Sunrise PG', bedsAvailable: open);

    test('read from st_pg_profile, with the map pin', () {
      final p = PgPublicProfile.tryParse({
        'hostel_id': 'h',
        'name': 'Sunrise PG',
        'beds_available': true,
        'latitude': 12.971599,
        'longitude': 77.594566,
      })!;
      expect(p.bedsAvailable, isTrue);
      expect(p.hasPin, isTrue);
      expect(p.latitude, closeTo(12.971599, 1e-9));
      final old = PgPublicProfile.tryParse({'hostel_id': 'h', 'name': 'Old server'})!;
      expect(old.bedsAvailable, isNull);
      expect(old.hasPin, isFalse);
    });

    testWidgets('a PG with room says so with no number, in the chosen language', (tester) async {
      await tester.pumpWidget(_app(BedAvailability(profile: profile(true))));
      await tester.pumpAndSettle();
      expect(find.text('Beds available'), findsOneWidget);
      expect(find.textContaining(RegExp(r'[0-9]')), findsNothing);

      await tester.pumpWidget(
          _app(BedAvailability(profile: profile(true)), locale: const Locale('hi')));
      await tester.pumpAndSettle();
      expect(find.text('बेड ख़ाली हैं'), findsOneWidget);
    });

    testWidgets('a full PG says so, and still lets the tenant ask', (tester) async {
      await tester.pumpWidget(_app(BedAvailability(profile: profile(false))));
      await tester.pumpAndSettle();
      expect(find.text('No beds free right now'), findsOneWidget);
      expect(find.textContaining('You can still ask to join'), findsOneWidget);
    });
  });
}
