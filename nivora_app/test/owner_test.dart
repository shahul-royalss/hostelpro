// Unit tests for the owner feature's logic — the parts that decide what an owner READS.
//
// Every sentence on the owner dashboard is built by a pure function in lib/features/owner, and
// this file is why: the wording is the product. "₹33,800" is not information and "₹33,800 still
// to collect from 6 residents" is, so the difference between them belongs under test rather
// than under a screenshot. The same goes for the decisions nobody would find by tapping around
// a seeded demo — a hostel switcher pointing at a PG that was transferred away, a subscription
// that expired three days ago, an error that must not offer a retry button.
//
// Nothing here touches the network. The database's own numbers are pasted in from a real
// signed-in read against the live project (see the group 'the demo hostel, in words').
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/models/models.dart';
import 'package:mobile/features/owner/owner_format.dart';
import 'package:mobile/features/owner/owner_insights.dart';
import 'package:mobile/features/owner/owner_providers.dart';
import 'package:mobile/features/owner/widgets/cashflow_chart.dart';

final DateTime _t0 = DateTime.utc(2026, 8, 24, 10);

HostelStats _stats({
  int totalBeds = 36,
  int occupiedBeds = 24,
  int activeStudents = 24,
  int openComplaints = 0,
  double feesCollected = 0,
  double feesPending = 0,
  int studentsPaid = 0,
  int studentsUnpaid = 0,
  int pendingLeaves = 0,
  int visitorsToday = 0,
  int pendingTasks = 0,
  double revenueToday = 0,
  double expensesToday = 0,
  double revenueMonth = 0,
  double expensesMonth = 0,
  SubscriptionState subscriptionState = SubscriptionState.active,
  int? subscriptionDaysLeft = 300,
}) {
  return HostelStats(
    totalBeds: totalBeds,
    occupiedBeds: occupiedBeds,
    activeStudents: activeStudents,
    openComplaints: openComplaints,
    feesCollected: feesCollected,
    feesPending: feesPending,
    studentsPaid: studentsPaid,
    studentsUnpaid: studentsUnpaid,
    pendingLeaves: pendingLeaves,
    visitorsToday: visitorsToday,
    pendingTasks: pendingTasks,
    revenueToday: revenueToday,
    expensesToday: expensesToday,
    revenueMonth: revenueMonth,
    expensesMonth: expensesMonth,
    subscriptionState: subscriptionState,
    subscriptionDaysLeft: subscriptionDaysLeft,
  );
}

Hostel _hostel(String id, {String? name}) => Hostel(
      id: id,
      name: name ?? id,
      ownerUserId: 'owner-1',
      totalFloors: 3,
      totalRooms: 12,
      bedsPerRoomDefault: 3,
      status: HostelStatus.active,
      createdAt: _t0,
      updatedAt: _t0,
    );

Complaint _complaint(String id, DateTime at, {ComplaintStatus status = ComplaintStatus.open}) =>
    Complaint(
      id: id,
      hostelId: 'h1',
      studentId: 's1',
      category: ComplaintCategory.wifi,
      title: 'Complaint $id',
      status: status,
      createdAt: at,
      updatedAt: at,
    );

Notice _notice(String id, DateTime at) => Notice(
      id: id,
      hostelId: 'h1',
      authorUserId: 'owner-1',
      title: 'Notice $id',
      body: 'body',
      audience: NoticeAudience.all,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  group('money reads the way an Indian owner reads it', () {
    test('grouping is lakh-first, not thousand-first', () {
      // The whole reason the en_IN pattern is pinned: 1,20,000 and 120,000 are the same number
      // and look like a factor of ten apart.
      expect(money(50200), '₹50,200');
      expect(money(120000), '₹1,20,000');
      expect(money(1250000), '₹12,50,000');
    });

    test('paise are dropped and negatives keep their sign', () {
      expect(money(7000), '₹7,000');
      expect(money(-5200), '-₹5,200');
      expect(money(0), '₹0');
    });

    test('chart-axis money uses k / L / Cr', () {
      expect(moneyShort(950), '₹950');
      expect(moneyShort(1500), '₹1.5k');
      expect(moneyShort(50200), '₹50k');
      expect(moneyShort(120000), '₹1.2L');
      expect(moneyShort(1500000), '₹15L');
      expect(moneyShort(-2500), '-₹2.5k');
    });

    test('a percentage is rounded, not truncated', () {
      expect(percentLabel(0.669), '67%');
      expect(percentLabel(1), '100%');
      expect(percentLabel(0), '0%');
    });
  });

  group('dates and counts', () {
    test('a period month becomes a month a person would say', () {
      expect(monthLabel('2026-08'), 'August 2026');
      expect(monthNameOnly('2026-01'), 'January');
    });

    test('a malformed period month is shown as itself, not as a wrong month', () {
      expect(monthLabel('August'), 'August');
      expect(monthLabel('2026-13'), '2026-13');
      expect(monthLabel(''), '');
    });

    test('relative time shortens as it ages', () {
      final now = DateTime(2026, 8, 24, 18);
      expect(relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 12)), now: now), '12m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 5)), now: now), '5h ago');
      expect(relativeTime(now.subtract(const Duration(days: 3)), now: now), '3d ago');
      expect(relativeTime(DateTime(2026, 8, 1, 9), now: now), '1 Aug');
    });

    test('a device clock running behind the server does not print the future', () {
      final now = DateTime(2026, 8, 24, 18);
      expect(relativeTime(now.add(const Duration(minutes: 3)), now: now), 'just now');
    });

    test('counts are pluralised once, here', () {
      expect(countLabel(1, 'resident'), '1 resident');
      expect(countLabel(6, 'resident'), '6 residents');
      expect(countLabel(0, 'bed'), '0 beds');
      expect(countLabel(2, 'complaint'), '2 complaints');
    });

    test('the greeting follows the local clock and the name is just the first word', () {
      expect(greetingFor(DateTime(2026, 8, 24, 8)), 'Good morning');
      expect(greetingFor(DateTime(2026, 8, 24, 13)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 8, 24, 21)), 'Good evening');
      expect(firstName('Ananya Rao'), 'Ananya');
      expect(firstName('  '), 'there');
      expect(firstName(null), 'there');
    });
  });

  group('collections', () {
    test('the meter divides by what was collected plus what is outstanding', () {
      final s = _stats(feesCollected: 50200, feesPending: 33800);
      expect(collectedShare(s), closeTo(0.5976, 0.0001));
    });

    test('nothing to collect at all is null, not zero', () {
      // 0% and "there is no scale" are different situations and must draw differently.
      expect(collectedShare(_stats()), isNull);
    });

    test('an overpayment cannot push the meter past full', () {
      expect(collectedShare(_stats(feesCollected: 9000, feesPending: 0)), 1.0);
    });

    test('the caption names the money AND the people', () {
      final s = _stats(feesCollected: 50200, feesPending: 33800, studentsPaid: 6, studentsUnpaid: 6);
      expect(collectionsCaption(s), '₹33,800 still to collect from 6 residents.');
    });

    test('a fully collected month says so instead of showing a zero', () {
      final s = _stats(feesCollected: 84000, studentsPaid: 12);
      expect(collectionsCaption(s), 'Every resident has paid this month.');
    });

    test('a month with nothing billed is not called a success', () {
      expect(collectionsCaption(_stats()), 'Nothing has been billed this month yet.');
    });
  });

  group('occupancy', () {
    test('the figure and its meaning', () {
      final s = _stats(totalBeds: 36, occupiedBeds: 24);
      expect(occupancyHeadline(s), '24 of 36 beds filled');
      expect(occupancyCaption(s), '67% occupancy — 12 beds vacant.');
    });

    test('a full house is stated, not described as zero vacancy', () {
      final s = _stats(totalBeds: 36, occupiedBeds: 36);
      expect(occupancyCaption(s), '100% occupancy — every bed is taken.');
    });

    test('a PG with no beds set up is an unfinished setup, not 0% occupancy', () {
      final s = _stats(totalBeds: 0, occupiedBeds: 0);
      expect(occupancyCaption(s), 'No beds have been set up for this PG yet.');
    });
  });

  group('what needs the owner', () {
    test('a clear morning produces an empty list, not a wall of zeroes', () {
      expect(attentionItems(_stats(activeStudents: 24, occupiedBeds: 24)), isEmpty);
    });

    test('only the non-zero things appear, money first', () {
      final s = _stats(
        activeStudents: 24,
        occupiedBeds: 24,
        studentsUnpaid: 6,
        feesPending: 33800,
        openComplaints: 3,
        pendingTasks: 1,
      );
      final items = attentionItems(s);
      expect(items.map((i) => i.kind).toList(), [
        AttentionKind.unpaidFees,
        AttentionKind.openComplaints,
        AttentionKind.openTasks,
      ]);
      expect(items.first.title, '6 residents have not paid');
      expect(items.first.detail, '₹33,800 outstanding');
    });

    test('residents registered without a bed are surfaced', () {
      final s = _stats(activeStudents: 27, occupiedBeds: 24);
      final item = attentionItems(s).single;
      expect(item.kind, AttentionKind.unhousedResidents);
      expect(item.title, '3 residents without a bed');
    });
  });

  group('subscription', () {
    test('an active subscription says nothing at all', () {
      expect(subscriptionNotice(_stats()), isNull);
    });

    test('expiring counts down and points at the only party who can renew', () {
      final notice = subscriptionNotice(
        _stats(subscriptionState: SubscriptionState.expiring, subscriptionDaysLeft: 12),
      )!;
      expect(notice.title, 'Subscription ends in 12 days');
      expect(notice.severe, isFalse);
      expect(notice.detail, contains('Nivora'));
    });

    test('a negative days_left is read as days ago, exactly as the RPC means it', () {
      final notice = subscriptionNotice(
        _stats(subscriptionState: SubscriptionState.expired, subscriptionDaysLeft: -3),
      )!;
      expect(notice.title, 'Subscription expired 3 days ago');
      expect(notice.severe, isTrue);
      expect(notice.detail, contains('read-only'));
    });

    test('a hostel that never had a subscription is not "expired 0 days ago"', () {
      final notice = subscriptionNotice(
        _stats(subscriptionState: SubscriptionState.expired, subscriptionDaysLeft: null),
      )!;
      expect(notice.title, 'No subscription on this PG');
    });
  });

  group('errors say what to do next', () {
    test('offline is worth retrying', () {
      final g = errorGuidance(const OfflineFailure('x'));
      expect(g.canRetry, isTrue);
      expect(g.next, contains('Reconnect'));
    });

    test('a refusal by row-level security is not', () {
      // Offering a retry here trains staff to tap a button that can never work.
      expect(errorGuidance(const AccessDeniedFailure('x')).canRetry, isFalse);
      expect(errorGuidance(const ReadOnlyFailure('x')).canRetry, isFalse);
      expect(errorGuidance(const SignedOutFailure('x')).canRetry, isFalse);
    });

    test("the database's own user-facing message is passed through unrewritten", () {
      // Every raise_exception in db/schema.sql is written FOR a user; rewording it here would
      // lose the only specific thing the server said.
      final g = errorGuidance(const InvalidInputFailure('That student has been checked out.'));
      expect(g.next, 'That student has been checked out.');
    });

    test('an unrecognised throw still lands somewhere sensible', () {
      final g = errorGuidance(StateError('boom'));
      expect(g.title, 'That did not load');
      expect(g.canRetry, isTrue);
    });
  });

  group('recent activity', () {
    test('two tables become one timeline, newest first', () {
      final feed = buildActivityFeed(
        complaints: [
          _complaint('c1', DateTime.utc(2026, 8, 24, 9)),
          _complaint('c2', DateTime.utc(2026, 8, 22, 9)),
        ],
        notices: [_notice('n1', DateTime.utc(2026, 8, 23, 9))],
      );
      expect(feed.map((i) => i.id).toList(), ['c1', 'n1', 'c2']);
      expect(feed.first.kind, ActivityKind.complaint);
      expect(feed.first.complaintStatus, ComplaintStatus.open);
      expect(feed[1].detail, 'Notice to everyone');
    });

    test('the feed is capped so the dashboard cannot become a list screen', () {
      final feed = buildActivityFeed(
        complaints: [
          for (var i = 0; i < 20; i++) _complaint('c$i', DateTime.utc(2026, 8, 20 - (i % 19))),
        ],
        notices: const [],
        limit: 6,
      );
      expect(feed, hasLength(6));
    });

    test('no activity is an empty list, never a fabricated row', () {
      expect(buildActivityFeed(complaints: const [], notices: const []), isEmpty);
    });
  });

  group('which PG is being looked at', () {
    final owned = [_hostel('a', name: 'Sunrise'), _hostel('b', name: 'Moonlight')];

    test('while the list is loading, whatever we already have is kept', () {
      expect(
        resolveActiveHostelId(chosen: null, sessionHostelId: 'a', owned: null),
        'a',
      );
      expect(
        resolveActiveHostelId(chosen: 'b', sessionHostelId: 'a', owned: null),
        'b',
      );
    });

    test('a tapped choice wins over the session default', () {
      expect(resolveActiveHostelId(chosen: 'b', sessionHostelId: 'a', owned: owned), 'b');
    });

    test('a choice that no longer exists falls back rather than showing an empty PG', () {
      // The failure this prevents: a PG transferred to another owner leaves a dashboard of
      // zeroes with nothing on screen to explain why.
      expect(resolveActiveHostelId(chosen: 'gone', sessionHostelId: 'a', owned: owned), 'a');
    });

    test('an owner whose session hostel is not one they own still gets a PG', () {
      expect(resolveActiveHostelId(chosen: null, sessionHostelId: 'zzz', owned: owned), 'a');
    });

    test('owning nothing and belonging nowhere is null, and the screen says so', () {
      expect(
        resolveActiveHostelId(chosen: null, sessionHostelId: null, owned: const []),
        isNull,
      );
    });
  });

  group('chart scale', () {
    test('the top gridline is a number a person would have chosen', () {
      expect(niceCeiling(8137.5), 10000);
      expect(niceCeiling(4200), 5000);
      expect(niceCeiling(1100), 2000);
      expect(niceCeiling(950), 1000);
      expect(niceCeiling(1), 1);
    });

    test('an empty day does not collapse the axis', () {
      expect(niceCeiling(0), 1);
      expect(niceCeiling(-5), 1);
    });
  });

  group('the demo hostel, in words', () {
    // Sunrise Residency, read from the live project with the owner account: 12 of 36 beds,
    // ₹50,200 collected against ₹33,800 pending, 6 residents paid and 6 not, 3 open complaints,
    // 1 task, ₹45,200 revenue and ₹50,400 expenses this month. These are the exact sentences
    // that PG's owner sees.
    final sunrise = _stats(
      totalBeds: 36,
      occupiedBeds: 12,
      activeStudents: 12,
      openComplaints: 3,
      feesCollected: 50200,
      feesPending: 33800,
      studentsPaid: 6,
      studentsUnpaid: 6,
      pendingLeaves: 1,
      pendingTasks: 1,
      revenueMonth: 45200,
      expensesMonth: 50400,
    );

    test('the hero and its meaning', () {
      expect(money(sunrise.feesCollected), '₹50,200');
      expect(collectionsCaption(sunrise), '₹33,800 still to collect from 6 residents.');
    });

    test('occupancy', () {
      expect(occupancyHeadline(sunrise), '12 of 36 beds filled');
      expect(occupancyCaption(sunrise), '33% occupancy — 24 beds vacant.');
    });

    test('what is waiting on the owner', () {
      expect(
        attentionItems(sunrise).map((i) => i.title).toList(),
        [
          '6 residents have not paid',
          '3 complaints still open',
          '1 leave request waiting',
          '1 task not done',
        ],
      );
    });

    test('the month is running at a loss and the figure says so', () {
      expect(money(sunrise.revenueMonth - sunrise.expensesMonth), '-₹5,200');
    });
  });
}
