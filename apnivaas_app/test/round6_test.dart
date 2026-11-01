// Round 6 (2026-11-01): the login screen's three round buttons and language switch, a back
// control on the sign-up steps, the update popup that opens the Play Store, the PG page's map
// card that opens Google Maps, and Find a PG's opening list and browse-only mode.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/google_id_token.dart';
import 'package:mobile/core/auth/social_sign_in.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/version/app_release.dart';
import 'package:mobile/core/version/release_check.dart';
import 'package:mobile/core/version/update_banner.dart';
import 'package:mobile/data/device/apps_launcher.dart';
import 'package:mobile/data/models/signup.dart';
import 'package:mobile/data/repositories/signup_repository.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/common/map_pin.dart';
import 'package:mobile/features/signup/signup_widgets.dart';
import 'package:mobile/features/signup/tenant/find_pg_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth extends AuthController {
  _Auth(this._client);
  final SupabaseClient _client;

  @override
  Future<AuthPhase> build() {
    clientOverride = _client;
    return super.build();
  }
}

class _Google implements GoogleIdTokenSource {
  @override
  bool get isAvailable => true;
  @override
  Future<GoogleTokenOutcome> request() async => const GoogleTokenCancelled();
  @override
  Future<GoogleTokenOutcome> requestQuietly() async => const GoogleTokenCancelled();
  @override
  Future<void> forget() async {}
}

class _Launcher implements AppsLauncher {
  int stores = 0;
  final maps = <(double, double, String?)>[];

  @override
  Future<PlayUpdate> checkUpdate() async => PlayUpdate.none;

  @override
  Future<bool> openStore() async {
    stores++;
    return true;
  }

  @override
  Future<bool> openMap({required double latitude, required double longitude, String? label}) async {
    maps.add((latitude, longitude, label));
    return true;
  }
}

class _Api implements SignupApi {
  final calls = <String>[];

  @override
  Future<List<HostelHit>> browseHostels() async {
    calls.add('browse');
    return const [HostelHit(hostelId: 'h1', name: 'Lakeview PG', propertyType: 'pg')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _round(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  setUp(() => UpdateBannerHost.prompted = null);

  group('login', () {
    late SupabaseClient client;
    setUp(() {
      client = SupabaseClient('https://stub.supabase.co', 'anon-key',
          httpClient: MockClient((r) async => http.Response('{}', 200, request: r)));
      addTearDown(client.dispose);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _Auth(client)),
          googleIdTokenSourceProvider.overrideWithValue(_Google()),
          facebookCredentialSourceProvider.overrideWithValue(const SocialSignInNotConfigured(
              enabledByFlag: true, message: SocialSignInWords.facebookNotSetUp)),
          truecallerCredentialSourceProvider.overrideWithValue(const SocialSignInNotConfigured(
              enabledByFlag: true, message: SocialSignInWords.truecallerNotSetUp)),
        ],
        child: MaterialApp(theme: ApnivaasTheme.light(), home: const LoginScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Google, Facebook and Truecaller sit side by side', (tester) async {
      await pump(tester);
      expect(_round('Continue with Google'), findsOneWidget);
      expect(_round('Continue with Facebook'), findsOneWidget);
      expect(_round('Continue with Truecaller'), findsOneWidget);
    });

    testWidgets('a provider that answers in words says so under the form', (tester) async {
      await pump(tester);
      await tester.tap(_round('Continue with Truecaller'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(SocialSignInWords.truecallerNotSetUp), findsOneWidget);
    });

    testWidgets('the language switch opens the six languages', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('login-language')));
      await tester.pumpAndSettle();
      expect(find.text('हिन्दी'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
    });
  });

  group('sign-up back', () {
    testWidgets('the arrow and Android back both go back', (tester) async {
      var backs = 0;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ApnivaasTheme.light(),
          home: SignupPage(onBack: () => backs++, children: const [Text('Step')]),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('signup-back')));
      expect(backs, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backs, 2, reason: 'the system back runs the same step back, not an app exit');
      expect(find.text('Step'), findsOneWidget);
    });

    testWidgets('a step with no back still has no arrow', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: SignupPage(children: [Text('Step')])),
      ));
      await tester.pump();
      expect(find.byKey(const Key('signup-back')), findsNothing);
    });
  });

  group('update popup', () {
    Future<_Launcher> pump(WidgetTester tester, UpdateOffer offer) async {
      final launcher = _Launcher();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          updateOfferProvider.overrideWithValue(offer),
          appsLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: ApnivaasTheme.light(),
          home: const UpdateBannerHost(child: Scaffold(body: Text('Home'))),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return launcher;
    }

    testWidgets('a newer build pops up once and Update now opens the Play Store', (tester) async {
      final launcher =
          await pump(tester, const UpdateOffer(status: UpdateStatus.available, versionCode: 15));
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-now')));
      await tester.pumpAndSettle();
      expect(launcher.stores, 1);
      expect(find.byKey(const Key('update-now')), findsNothing);
      // The bar stays until the update happens, and a rebuild does not pop up again.
      expect(find.text('Tap to update on Google Play'), findsOneWidget);
    });

    testWidgets('Later waves this version away', (tester) async {
      await pump(tester, const UpdateOffer(status: UpdateStatus.available, versionCode: 15));
      await tester.tap(find.byKey(const Key('update-later')));
      await tester.pumpAndSettle();
      expect(find.text('Tap to update on Google Play'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a mandatory build has no Later', (tester) async {
      await pump(tester, const UpdateOffer(status: UpdateStatus.required, versionCode: 15));
      expect(find.text('Update required'), findsWidgets);
      expect(find.byKey(const Key('update-later')), findsNothing);
    });

    testWidgets('up to date: nothing at all', (tester) async {
      await pump(tester, const UpdateOffer(status: UpdateStatus.upToDate));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  testWidgets('the PG page map opens the pin in Google Maps', (tester) async {
    final launcher = _Launcher();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mapTilesProvider.overrideWithValue(false),
        appsLauncherProvider.overrideWithValue(launcher),
      ],
      child: MaterialApp(
        theme: ApnivaasTheme.light(),
        home: const Scaffold(
          body: PgLocationCard(latitude: 18.520432, longitude: 73.856744, name: 'Lakeview PG'),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pg-open-map')));
    await tester.pump();
    expect(launcher.maps, [(18.520432, 73.856744, 'Lakeview PG')]);
  });

  group('Find a PG', () {
    testWidgets('lists PGs before anything is typed; browse-only has no request button',
        (tester) async {
      final api = _Api();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [signupApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: ApnivaasTheme.light(),
          home: FindPgScreen(browseOnly: true, onRequested: (_) {}, onEditDetails: () {}),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(api.calls, ['browse']);
      expect(find.text('PGs on Apnivaas'), findsOneWidget);
      expect(find.text('Lakeview PG'), findsOneWidget);
      expect(find.text('Request to join'), findsNothing);
      expect(find.textContaining('ask your owner to check you out first'), findsOneWidget);
    });
  });
}
