// The owner/warden half of the 1.3.0 round: join requests, deleting a staff account, plan &
// billing, and the layouts at 1.4x on a 360dp phone. Built against docs/self-signup-api.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/data/models/people.dart';
import 'package:mobile/data/repositories/people_repository.dart';
import 'package:mobile/data/repositories/signup_repository.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/plan/plan_billing_screen.dart';
import 'package:mobile/features/owner/staff/owner_staff_screen.dart';
import 'package:mobile/features/owner/staff/staff_models.dart';
import 'package:mobile/features/owner/staff/staff_providers.dart';
import 'package:mobile/features/shell/join_requests.dart';

const _hostelId = '3f1c9e2a-0000-4000-8000-00000000abcd';

final _hostel = Hostel(
  id: _hostelId,
  name: 'Sunrise Residency',
  ownerUserId: 'owner-1',
  totalFloors: 3,
  totalRooms: 12,
  bedsPerRoomDefault: 3,
  status: HostelStatus.active,
  createdAt: DateTime.utc(2026, 3, 1),
  updatedAt: DateTime.utc(2026, 3, 1),
);

const _owner = ApnivaasSession(
  userId: 'owner-1',
  role: UserRole.owner,
  fullName: 'Lakshmi Rao',
  status: 'active',
  mustChangePassword: false,
  hostelId: _hostelId,
);

ReviewJoinRequest _request({String id = 'r-1'}) => ReviewJoinRequest.fromJson({
      'request_id': id,
      'hostel_id': _hostelId,
      'hostel_name': 'Sunrise Residency',
      'user_id': 'tenant-1',
      'full_name': 'Arjun Mehta',
      'phone': '9876543210',
      'email': null,
      'avatar_path': null,
      'gender': 'male',
      'date_of_birth': '2003-05-14',
      'emergency_contact_name': 'Sunita Mehta',
      'emergency_contact_phone': '9123456780',
      'message': 'I start at the college next month.',
      'status': 'pending',
      'created_at': '2026-10-24T10:00:00Z',
      'documents': [
        {'id': 'd-1', 'kind': 'aadhaar_masked', 'storage_path': 'tenant-1/document/a.jpg', 'created_at': '2026-10-24T09:00:00Z'},
        {'id': 'd-2', 'kind': 'pan', 'storage_path': 'tenant-1/document/b.pdf', 'created_at': '2026-10-24T09:00:00Z'},
      ],
    });

final _catalog = [
  for (final r in [
    {'plan_id': 'monthly', 'name': 'Monthly', 'months': 1, 'bonus_months': 0, 'total_months': 1, 'price_per_month': 1099, 'amount': 1099, 'saving_vs_monthly': 0, 'sort_order': 1},
    {'plan_id': 'quarterly', 'name': 'Quarterly', 'months': 3, 'bonus_months': 0, 'total_months': 3, 'price_per_month': 999, 'amount': 2997, 'saving_vs_monthly': 300, 'sort_order': 2},
    {'plan_id': 'yearly', 'name': 'Yearly', 'months': 12, 'bonus_months': 1, 'total_months': 13, 'price_per_month': 959, 'amount': 11508, 'saving_vs_monthly': 2779, 'sort_order': 3},
  ])
    PlanOption.fromJson(r),
];

class _FakePeople implements PeopleApi {
  int pending = 0;
  List<ReviewJoinRequest> requests = [];
  final decisions = <({String id, bool accept, String? note})>[];
  Object? decideError;
  PlanStatus status = PlanStatus.fromJson(const {
    'hostel_id': _hostelId,
    'hostel_name': 'Sunrise Residency',
    'state': 'trial',
    'end_date': '2026-11-24',
  });
  final orders = <({String hostelId, String planId})>[];
  final verified = <({String orderId, String paymentId, String signature})>[];
  final deleted = <String>[];

  @override
  Future<int> pendingJoinRequestCount() async => pending;
  @override
  Future<List<ReviewJoinRequest>> joinRequests({String status = 'pending'}) async => requests;
  @override
  Future<void> decideJoinRequest(String requestId, {required bool accept, String? note}) async {
    if (decideError != null) throw decideError!;
    decisions.add((id: requestId, accept: accept, note: note));
    requests = [];
    pending = 0;
  }

  @override
  Future<String?> signedUrl(String bucket, String path) async => null;
  @override
  Future<Map<String, String>> avatarPaths(List<String> userIds) async => const {};
  @override
  Future<String?> myAvatarPath() async => null;
  @override
  Future<void> removeMyAvatar() async {}
  @override
  Future<void> deleteStaffAccount(String userId) async => deleted.add(userId);
  @override
  Future<List<PlanOption>> planCatalog() async => _catalog;
  @override
  Future<PlanStatus> planStatus(String hostelId) async => status;
  @override
  Future<PlanOrder> createPlanOrder({required String hostelId, required String planId}) async {
    orders.add((hostelId: hostelId, planId: planId));
    return PlanOrder.fromJson(const {
      'order_id': 'order_1',
      'key_id': 'rzp_test_1',
      'amount_paise': 1150800,
      'currency': 'INR',
      'plan_name': 'Yearly',
      'hostel_name': 'Sunrise Residency',
    });
  }

  @override
  Future<PlanActivation> verifyPlanPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    verified.add((orderId: orderId, paymentId: paymentId, signature: signature));
    return PlanActivation.fromJson(const {'outcome': 'paid', 'period_end': '2027-12-24'});
  }

  @override
  Future<List<DemoRequestRow>> demoRequests({String? status}) async => const [];
  @override
  Future<void> updateDemoRequest(String id, {required String status, String? note}) async {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  _FakePeople people, {
  List<Object> extra = const [],
  Size size = const Size(800, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    // A fresh container per pump, so a test can change the fake and pump again.
    key: UniqueKey(),
    retry: (_, _) => null,
    overrides: [
      sessionProvider.overrideWithValue(_owner),
      peopleApiProvider.overrideWithValue(people),
      activeHostelIdProvider.overrideWithValue(_hostelId),
      myHostelsProvider.overrideWith((ref) => [_hostel]),
      ...extra.cast(),
    ],
    child: MaterialApp(
      theme: ApnivaasTheme.light(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  ));
  await _tick(tester);
}

Future<void> _tick(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('rows from the contract', () {
    test('a join request keeps its documents and works out the age', () {
      final r = _request();
      expect(r.documents.map((d) => d.label), ['Masked Aadhaar', 'PAN card']);
      expect(r.documents.last.isPdf, isTrue);
      expect(r.ageOn(DateTime(2026, 10, 25)), 23);
      expect(r.ageOn(DateTime(2026, 5, 13)), 22);
      expect(r.genderLabel, 'Male');
      expect(r.isPending, isTrue);
    });

    test('plan status reads every state, and an unknown one safely', () {
      PlanState s(String v) => PlanStatus.fromJson({'state': v}).state;
      expect(s('trial'), PlanState.trial);
      expect(s('expiring'), PlanState.expiring);
      expect(s('expired'), PlanState.expired);
      expect(s('weird'), PlanState.unknown);
      expect(PlanStatus.fromJson(const {'state': 'expired'}).ended, isTrue);
    });

    test('an order with no id or key is not opened', () {
      expect(PlanOrder.fromJson(const {'order_id': 'order_1', 'key_id': '', 'amount_paise': 100}).usable, isFalse);
      expect(PlanOrder.fromJson(const {'order_id': 'order_1', 'key_id': 'k', 'amount_paise': 100}).usable, isTrue);
    });
  });

  group('join requests', () {
    testWidgets('the entry is absent with nothing waiting and counts when something is', (tester) async {
      final people = _FakePeople();
      await _pump(tester, const Scaffold(body: JoinRequestsEntry()), people);
      expect(find.text('Join requests'), findsNothing);

      people
        ..pending = 2
        ..requests = [_request(), _request(id: 'r-2')];
      await _pump(tester, const Scaffold(body: JoinRequestsEntry()), people);
      expect(find.text('Join requests'), findsOneWidget);
      expect(find.text('2 people are waiting for your answer'), findsOneWidget);

      await tester.tap(find.text('Join requests'));
      await _tick(tester);
      expect(find.byType(JoinRequestCard), findsNWidgets(2));
    });

    testWidgets('the card shows who is asking, with their details and documents', (tester) async {
      final people = _FakePeople()..requests = [_request()];
      await _pump(tester, const JoinRequestsScreen(), people);
      expect(find.text('Arjun Mehta'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Sunita Mehta · 9123456780'), findsOneWidget);
      expect(find.textContaining('I start at the college'), findsOneWidget);
      expect(find.text('Masked Aadhaar'), findsOneWidget);
      expect(find.text('PAN card'), findsOneWidget);
      // Email null is "unreachable": shown as not given, never invented.
      expect(find.text('Not given'), findsOneWidget);
    });

    testWidgets('decline sends the note, and the list empties', (tester) async {
      final people = _FakePeople()..requests = [_request()];
      await _pump(tester, const JoinRequestsScreen(), people);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await _tick(tester);
      await tester.enterText(find.byType(TextField), '  No beds this month ');
      await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
      await _tick(tester);
      expect(people.decisions.single, (id: 'r-1', accept: false, note: 'No beds this month'));
      expect(find.text('No requests waiting'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown word for word', (tester) async {
      final people = _FakePeople()
        ..requests = [_request()]
        ..decideError = const SignupFailure('Subscription expired — hostel is read-only.', code: 'P0001');
      await _pump(tester, const JoinRequestsScreen(), people);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await _tick(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept request'));
      await _tick(tester);
      expect(find.text('Subscription expired — hostel is read-only.'), findsOneWidget);
      expect(people.decisions, isEmpty);
    });
  });

  group('plan & billing', () {
    testWidgets('three plans with the per-month price and saving; yearly is picked first', (tester) async {
      final people = _FakePeople();
      await _pump(tester, const PlanBillingScreen(hostelId: _hostelId), people);
      expect(find.text('Free trial'), findsOneWidget);
      expect(find.text('Trial ends 24 Nov 2026'), findsOneWidget);
      expect(find.text('₹1,099'), findsOneWidget);
      expect(find.text('₹999'), findsOneWidget);
      expect(find.text('₹959'), findsOneWidget);
      expect(find.text('Save ₹300'), findsOneWidget);
      expect(find.text('Save ₹2,779'), findsOneWidget);
      expect(find.text('₹11,508 for 12 months + 1 month free'), findsOneWidget);
      expect(find.text('Pay ₹11,508'), findsOneWidget);

      await tester.tap(find.text('Quarterly'));
      await tester.pump();
      expect(find.text('Pay ₹2,997'), findsOneWidget);
    });

    testWidgets('pay sends only the plan id, then verifies what checkout returned', (tester) async {
      final people = _FakePeople();
      final checkouts = <PlanOrder>[];
      await _pump(
        tester,
        const PlanBillingScreen(hostelId: _hostelId),
        people,
        extra: [
          planCheckoutProvider.overrideWithValue((order) async {
            checkouts.add(order);
            return const PlanCheckoutPaid(orderId: 'order_1', paymentId: 'pay_9', signature: 'sig');
          }),
        ],
      );
      await tester.tap(find.text('Pay ₹11,508'));
      await _tick(tester);
      expect(people.orders.single, (hostelId: _hostelId, planId: 'yearly'));
      expect(checkouts.single.amountPaise, 1150800);
      expect(people.verified.single, (orderId: 'order_1', paymentId: 'pay_9', signature: 'sig'));
      expect(find.textContaining('Payment received'), findsOneWidget);
    });

    testWidgets('a cancelled checkout verifies nothing', (tester) async {
      final people = _FakePeople();
      await _pump(
        tester,
        const PlanBillingScreen(hostelId: _hostelId),
        people,
        extra: [
          planCheckoutProvider.overrideWithValue((_) async => const PlanCheckoutCancelled()),
        ],
      );
      await tester.tap(find.text('Pay ₹11,508'));
      await _tick(tester);
      expect(people.verified, isEmpty);
      expect(find.text('Payment cancelled. Nothing was charged.'), findsOneWidget);
    });

    testWidgets('the home banner appears only once the plan has ended', (tester) async {
      final people = _FakePeople();
      await _pump(tester, const Scaffold(body: PlanEndedBanner(hostelId: _hostelId)), people);
      expect(find.text('Your plan has ended — choose a plan'), findsNothing);

      people.status = PlanStatus.fromJson(const {'hostel_id': _hostelId, 'state': 'expired'});
      await _pump(tester, const Scaffold(body: PlanEndedBanner(hostelId: _hostelId)), people);
      expect(find.text('Your plan has ended — choose a plan'), findsOneWidget);
    });
  });

  testWidgets('deleting a staff account needs the permanent-action tick', (tester) async {
    final people = _FakePeople();
    final member = StaffMember(
      id: 'staff-9',
      role: StaffRole.warden,
      fullName: 'Ravi Kulkarni',
      status: StaffStatus.active,
      createdAt: DateTime.utc(2026, 3, 1),
      email: 'ravi@example.com',
      activeHostelId: _hostelId,
      activeHostelName: 'Sunrise Residency',
      hostelIds: const [_hostelId],
    );
    await _pump(
      tester,
      const OwnerStaffScreen(),
      people,
      extra: [ownerStaffProvider.overrideWith((ref, id) => [member])],
    );
    await tester.tap(find.text('Delete account'));
    await _tick(tester, frames: 4);
    expect(find.textContaining('This is permanent and cannot be undone'), findsOneWidget);
    final delete = find.widgetWithText(FilledButton, 'Delete permanently');
    expect(tester.widget<FilledButton>(delete).onPressed, isNull);

    await tester.tap(find.text('I understand this cannot be undone'));
    await tester.pump();
    await tester.tap(delete);
    await _tick(tester);
    expect(people.deleted, ['staff-9']);
    expect(find.text('Account deleted.'), findsOneWidget);
  });

  group('fits at 1.4x on a 360dp phone', () {
    for (final (name, screen) in [
      ('join requests', const JoinRequestsScreen() as Widget),
      ('plan & billing', const PlanBillingScreen(hostelId: _hostelId)),
    ]) {
      testWidgets(name, (tester) async {
        final people = _FakePeople()..requests = [_request()];
        await _pump(tester, screen, people, size: const Size(360, 780), textScale: 1.4);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
