import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/tenant_admin.dart';
import 'package:mobile/data/models/upi.dart';
import 'package:mobile/data/repositories/signup_repository.dart';
import 'package:mobile/data/repositories/tenant_admin_repository.dart';
import 'package:mobile/data/repositories/upi_repository.dart';
import 'package:mobile/features/student/pay_upi.dart';
import 'package:mobile/features/warden/actions/rent_sheet.dart';
import 'package:mobile/features/warden/home/rent_needed.dart';
import 'package:mobile/features/warden/students/edit_tenant_sheet.dart';

/// Round 4 app side: rent (R4.1), tenant details (R4.2) and UPI intents (R4.3).

class _FakeTenantAdmin implements TenantAdminApi {
  List<RentlessResident> rentless = const [];
  final rentCalls = <({String id, double fee, int? day})>[];
  final patches = <Map<String, dynamic>>[];
  Object? updateError;

  @override
  Future<List<RentlessResident>> residentsNeedingRent({String? hostelId}) async => rentless;

  @override
  Future<RentChange> setRent(String studentId, {required double monthlyFee, int? dueDay}) async {
    rentCalls.add((id: studentId, fee: monthlyFee, day: dueDay));
    rentless = [for (final r in rentless) if (r.studentId != studentId) r];
    return RentChange(monthlyFee: monthlyFee, rentDueDay: dueDay, appliesFrom: '2026-12');
  }

  @override
  Future<TenantProfile?> profile(String studentId) async => null;

  @override
  Future<void> updateProfile(String studentId, TenantProfilePatch patch) async {
    if (updateError != null) throw updateError!;
    patches.add(patch.toParams(studentId));
  }
}

class _FakeLauncher implements UpiLauncher {
  _FakeLauncher(this.installed, {this.response});
  final Set<UpiApp> installed;
  final String? response;
  final launches = <({Uri uri, UpiApp? app})>[];

  @override
  Future<Set<UpiApp>> installedApps() async => installed;

  @override
  Future<UpiLaunchResult> launch(Uri uri, {UpiApp? app}) async {
    launches.add((uri: uri, app: app));
    return UpiLaunchResult(opened: true, response: UpiResponse.parse(response));
  }
}

Future<void> _pump(WidgetTester tester, Widget home, List<Object> overrides,
    {double textScale = 1.0, Size size = const Size(800, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: ApnivaasTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: home),
    ),
  ));
  await tester.pumpAndSettle();
}

TenantProfile _profile({bool hasAccount = true}) => TenantProfile(
      studentId: 's-1',
      fullName: 'Arjun Mehta',
      phone: '9876543210',
      hasAccount: hasAccount,
      email: 'arjun@example.com',
      gender: 'male',
      emergencyName: 'Sunita Mehta',
      emergencyPhone: '9123456780',
      address: '12 MG Road, Pune',
      city: 'Pune',
      pincode: '411001',
    );

void main() {
  group('R4.3 UPI intent', () {
    test('a personal UPI ID gets pa, pn, am, cu and tn only', () {
      final uri = buildUpiUri(
        vpa: ' Owner.Name@OKHDFCBANK ',
        payeeName: 'Ravi & Sons',
        amount: 6500,
        note: 'Rent November 2026 Sunrise Boys PG — Koramangala Block A',
      );
      final q = uri.queryParameters;
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(q.keys.toSet(), {'pa', 'pn', 'am', 'cu', 'tn'});
      for (final banned in ['mc', 'tr', 'mode', 'orgid']) {
        expect(q.containsKey(banned), isFalse, reason: banned);
      }
      expect(q['pa'], 'owner.name@okhdfcbank');
      expect(q['am'], '6500.00');
      expect(q['cu'], 'INR');
      expect(q['tn']!.length, lessThanOrEqualTo(40));
      expect(RegExp(r'^[\x20-\x7E]*$').hasMatch(q['tn']!), isTrue);
      expect(uri.toString(), contains('pn=Ravi%20%26%20Sons'));
      expect(uri.toString(), isNot(contains('+')));
    });

    test('VPA validation', () {
      expect(isValidVpa('name@okhdfcbank'), isTrue);
      expect(isValidVpa('98765.43210@ybl'), isTrue);
      expect(isValidVpa('a@b'), isFalse);
      expect(isValidVpa('name@ok1bank'), isFalse);
      expect(isValidVpa('name'), isFalse);
      expect(isValidVpa('na me@paytm'), isTrue, reason: 'spaces are removed first');
      expect(isValidVpa('name@paytm?x=1'), isFalse);
    });

    test('the response string is read as a hint only', () {
      final ok = UpiResponse.parse(
          'txnId=AXI123&responseCode=00&Status=SUCCESS&txnRef=ABC&ApprovalRefNo=412345678901');
      expect(ok.saysSuccess, isTrue);
      expect(ok.utr, '412345678901');
      final bad = UpiResponse.parse('Status=FAILURE&txnRef=x');
      expect(bad.saysFailure, isTrue);
      expect(bad.utr, isNull);
      expect(UpiResponse.parse(null).status, isNull);
      expect(UpiResponse.parse('garbage').status, isNull);
      expect(UpiResponse.parse('status=<script>').status, isNull);
    });

    testWidgets('installed apps get their own buttons; the response prefills the UTR',
        (tester) async {
      final launcher = _FakeLauncher({UpiApp.phonepe, UpiApp.gpay},
          response: 'Status=SUCCESS&ApprovalRefNo=412345678901');
      await _pump(
        tester,
        const UpiPaySheet(
          settings: UpiSettings(hostelId: 'h', vpa: 'owner@ybl', payeeName: 'Ravi Kumar'),
          amount: 6500,
          periodMonth: '2026-11',
        ),
        [upiLauncherProvider.overrideWithValue(launcher)],
      );
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('Paytm'), findsNothing);
      expect(find.text('Other UPI app'), findsOneWidget);
      expect(find.text('Copy UPI ID and pay by hand'), findsOneWidget);

      await tester.tap(find.text('PhonePe'));
      await tester.pumpAndSettle();
      expect(launcher.launches.single.app, UpiApp.phonepe);
      expect(launcher.launches.single.uri.queryParameters['pa'], 'owner@ybl');
      // Never marked paid on the device's word: the UTR step always follows.
      expect(find.text('Enter the UTR'), findsOneWidget);
      expect(find.widgetWithText(TextField, '412345678901'), findsOneWidget);
      expect(find.text('Send for confirmation'), findsOneWidget);
    });

    testWidgets('no named app installed: the chooser and copy fallback remain', (tester) async {
      final launcher = _FakeLauncher(const {});
      await _pump(
        tester,
        const UpiPaySheet(
          settings: UpiSettings(hostelId: 'h', vpa: 'owner@ybl', payeeName: 'Ravi Kumar'),
          amount: 100,
          periodMonth: '2026-11',
        ),
        [upiLauncherProvider.overrideWithValue(launcher)],
      );
      expect(find.text('Open UPI app'), findsOneWidget);
      await tester.tap(find.text('Open UPI app'));
      await tester.pumpAndSettle();
      expect(launcher.launches.single.app, isNull);
    });
  });

  group('R4.1 rent', () {
    test('rent and due day bounds', () {
      expect(parseRent('6,500'), 6500);
      expect(parseRent('0'), isNull);
      expect(parseRent('1000001'), isNull);
      expect(parseRent('10.555'), isNull);
      expect(parseRent('abc'), isNull);
      expect(parseDueDay('28'), 28);
      expect(parseDueDay('29'), isNull);
      expect(parseDueDay('0'), isNull);
      expect(appliesFromLabel('2026-12'), 'December 2026');
    });

    test('rpc rows decode', () {
      final rows = RentlessResident.listFrom([
        {
          'student_id': 's-1',
          'hostel_id': 'h-1',
          'full_name': 'Arjun',
          'room_number': '101',
          'bed_number': 2,
          'has_account': true,
        },
        {'student_id': null},
      ]);
      expect(rows.single.bedNumber, 2);
      final change = RentChange.fromJson(
          {'monthly_fee': 7000, 'rent_due_day': 5, 'applies_from': '2026-12'},
          fallbackFee: 1);
      expect(change.appliesFrom, '2026-12');
      expect(RentChange.fromJson({'applies_from': 'x'}, fallbackFee: 9).monthlyFee, 9);
    });

    testWidgets('the list opens the editor; saving says when the rent applies', (tester) async {
      final api = _FakeTenantAdmin()
        ..rentless = const [
          RentlessResident(studentId: 's-1', hostelId: 'h-1', fullName: 'Arjun Mehta'),
          RentlessResident(studentId: 's-2', hostelId: 'h-1', fullName: 'Kiran Rao'),
        ];
      await _pump(
        tester,
        const Column(children: [RentNeededEntry(hostelId: 'h-1')]),
        [tenantAdminApiProvider.overrideWithValue(api)],
      );
      expect(find.text('Set rent for 2 new residents'), findsOneWidget);
      await tester.tap(find.text('Set rent for 2 new residents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arjun Mehta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Set rent'));
      await tester.pumpAndSettle();
      expect(find.text(rentRangeMessage), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('rent-amount')), '7000');
      await tester.tap(find.widgetWithText(FilledButton, 'Set rent'));
      await tester.pumpAndSettle();
      // Empty due day keeps the PG's day.
      expect(api.rentCalls.single, (id: 's-1', fee: 7000.0, day: null));
      expect(find.text('Rent saved. The new rent applies from December 2026.'), findsOneWidget);
      expect(find.text('Arjun Mehta'), findsNothing);
    });
  });

  group('R4.2 tenant details', () {
    test('a patch carries only what changed', () {
      const p = TenantProfilePatch(email: '', city: 'Pune');
      expect(p.toParams('s'), {'p_student_id': 's', 'p_email': '', 'p_city': 'Pune'});
      expect(const TenantProfilePatch().isEmpty, isTrue);
      expect(
          TenantProfilePatch(dateOfBirth: DateTime(2003, 4, 9)).toParams('s')['p_date_of_birth'],
          '2003-04-09');
    });

    test('the prefill falls back to the roster guardian', () {
      final p = TenantProfile.from(
          {'id': 's', 'user_id': null, 'full_name': 'A', 'phone': '9', 'guardian_name': 'G'},
          null)!;
      expect(p.hasAccount, isFalse);
      expect(p.emergencyName, 'G');
    });

    testWidgets('only changed fields are sent', (tester) async {
      final api = _FakeTenantAdmin();
      await _pump(tester, TenantDetailsForm(profile: _profile()),
          [tenantAdminApiProvider.overrideWithValue(api)]);
      await tester.enterText(find.byKey(const ValueKey('tenant-city')), 'Mumbai');
      await tester.enterText(find.byKey(const ValueKey('tenant-email')), '');
      await tester.tap(find.text('Female'));
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(api.patches.single,
          {'p_student_id': 's-1', 'p_email': '', 'p_gender': 'female', 'p_city': 'Mumbai'});
    });

    testWidgets('a server refusal lands under its field', (tester) async {
      final api = _FakeTenantAdmin()
        ..updateError = const SignupFailure(
            'Another resident or account already uses this phone number.',
            field: 'phone');
      await _pump(tester, TenantDetailsForm(profile: _profile()),
          [tenantAdminApiProvider.overrideWithValue(api)]);
      await tester.enterText(find.byKey(const ValueKey('tenant-phone')), '9000000001');
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(find.text('Another resident or account already uses this phone number.'),
          findsOneWidget);
    });

    testWidgets('the emergency number must differ from the resident\'s', (tester) async {
      final api = _FakeTenantAdmin();
      await _pump(tester, TenantDetailsForm(profile: _profile()),
          [tenantAdminApiProvider.overrideWithValue(api)]);
      await tester.enterText(find.byKey(const ValueKey('tenant-ePhone')), '+91 98765 43210');
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(find.text("The emergency contact needs a different number from the resident's."),
          findsOneWidget);
      expect(api.patches, isEmpty);
    });

    testWidgets('no app account: account-only fields are hidden; fits at 1.4x on 360dp',
        (tester) async {
      await _pump(tester, TenantDetailsForm(profile: _profile(hasAccount: false)),
          [tenantAdminApiProvider.overrideWithValue(_FakeTenantAdmin())],
          textScale: 1.4, size: const Size(360, 1600));
      expect(find.byKey(const ValueKey('tenant-city')), findsNothing);
      expect(find.text('Female'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
