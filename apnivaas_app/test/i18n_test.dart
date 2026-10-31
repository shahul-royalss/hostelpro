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

  group('free beds on a PG page', () {
    PgPublicProfile profile(int free, List<({int sharing, int free})> by) => PgPublicProfile(
        hostelId: 'h', name: 'Sunrise PG', bedsTotal: 8, bedsFree: free, freeBySharing: by);

    test('read from st_pg_profile; a full type is left out', () {
      final p = PgPublicProfile.tryParse({
        'hostel_id': 'h',
        'name': 'Sunrise PG',
        'beds_total': 8,
        'beds_free': 3,
        'free_by_sharing': [
          {'sharing': 2, 'free': 1},
          {'sharing': 3, 'free': 2},
          {'sharing': 4, 'free': 0},
        ],
      })!;
      expect(p.bedsTotal, 8);
      expect(p.bedsFree, 3);
      expect(p.freeBySharing, [(sharing: 2, free: 1), (sharing: 3, free: 2)]);
      expect(PgPublicProfile.tryParse({'hostel_id': 'h', 'name': 'Old server'})!.bedsFree, isNull);
    });

    testWidgets('counts by room type, in the chosen language', (tester) async {
      await tester.pumpWidget(_app(BedAvailability(
          profile: profile(3, const [(sharing: 1, free: 1), (sharing: 3, free: 2)]))));
      await tester.pumpAndSettle();
      expect(find.text('3 beds free'), findsOneWidget);
      expect(find.text('Single room · 1 free'), findsOneWidget);
      expect(find.text('3 sharing · 2 free'), findsOneWidget);

      await tester.pumpWidget(_app(
          BedAvailability(profile: profile(3, const [(sharing: 3, free: 2)])),
          locale: const Locale('hi')));
      await tester.pumpAndSettle();
      expect(find.text('3 बेड ख़ाली'), findsOneWidget);
      expect(find.text('3 शेयरिंग · 2 ख़ाली'), findsOneWidget);
    });

    testWidgets('a full PG says so, and still lets the tenant ask', (tester) async {
      await tester.pumpWidget(_app(BedAvailability(profile: profile(0, const []))));
      await tester.pumpAndSettle();
      expect(find.text('No beds free right now'), findsOneWidget);
      expect(find.textContaining('You can still ask to join'), findsOneWidget);
    });
  });
}
