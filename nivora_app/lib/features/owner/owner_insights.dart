library;

import '../../data/models/models.dart';
import 'owner_format.dart';

/// Turning counted numbers into sentences.
///
/// THE RULE THIS FILE EXISTS TO ENFORCE. A bare number is not information. "₹33,800" tells an
/// owner nothing they can act on; "₹33,800 still to collect from 6 residents" tells them who to
/// ring this afternoon. Every string below is built from fields that Postgres counted — there
/// is no estimate, no extrapolation and no average invented to make a sentence read better.
///
/// It is all pure functions over [HostelStats] and model rows, deliberately, so the wording
/// that a user actually reads is covered by unit tests rather than by opening the app and
/// squinting at it.

// ─────────────────────────────────────────────────────────────────────────────
// COLLECTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// The share of this month's money that is already in, 0.0–1.0.
///
/// Denominator is collected + outstanding, NOT `sum(amount_due)` — which the RPC does not
/// return. The two differ only when somebody overpays, and inventing a "billed" total the
/// database never computed is exactly the kind of number this app must not display.
///
/// Null when there is nothing to collect at all (no residents, or no fees set), because a
/// meter at 0% and a meter with no scale mean different things.
double? collectedShare(HostelStats s) {
  final total = s.feesCollected + s.feesPending;
  if (total <= 0) return null;
  return (s.feesCollected / total).clamp(0.0, 1.0);
}

/// What the hero figure means, in one line.
String collectionsCaption(HostelStats s) {
  if (s.feesPending <= 0 && s.studentsUnpaid == 0) {
    return s.studentsPaid == 0
        ? 'Nothing has been billed this month yet.'
        : 'Every resident has paid this month.';
  }
  if (s.feesPending <= 0) {
    // Nothing outstanding in rupees, but the ledger still has residents without a payment row.
    return '${countLabel(s.studentsUnpaid, 'resident')} still to record a payment.';
  }
  return '${money(s.feesPending)} still to collect '
      'from ${countLabel(s.studentsUnpaid, 'resident')}.';
}

// ─────────────────────────────────────────────────────────────────────────────
// OCCUPANCY
// ─────────────────────────────────────────────────────────────────────────────

/// "24 of 36 beds filled" — the figure itself.
String occupancyHeadline(HostelStats s) =>
    '${s.occupiedBeds} of ${s.totalBeds} beds filled';

/// What that occupancy means. Null occupancy rate (no beds configured) is its own sentence:
/// "0% full" would read as a business failure when the truth is an unfinished setup.
String occupancyCaption(HostelStats s) {
  final rate = s.occupancyRate;
  if (rate == null) return 'No beds have been set up for this PG yet.';
  if (s.freeBeds == 0) return '${percentLabel(rate)} occupancy — every bed is taken.';
  return '${percentLabel(rate)} occupancy — '
      '${countLabel(s.freeBeds, 'bed')} vacant.';
}

// ─────────────────────────────────────────────────────────────────────────────
// WHAT NEEDS THE OWNER TODAY
// ─────────────────────────────────────────────────────────────────────────────

/// The kinds of thing that can be waiting. The widget maps these to an icon and a tone, so
/// this file stays free of anything visual and stays testable without a widget tree.
enum AttentionKind { unpaidFees, openComplaints, openTasks, pendingLeaves, unhousedResidents }

class AttentionItem {
  const AttentionItem({required this.kind, required this.title, this.detail});

  final AttentionKind kind;
  final String title;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is AttentionItem &&
      other.kind == kind &&
      other.title == title &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, title, detail);
}

/// Only the things that are actually outstanding, in the order an owner cares about them.
///
/// An empty list is a real answer and the screen says so ("Nothing is waiting on you") rather
/// than drawing five cards of zeroes. Zeroes as decoration are what turn a dashboard into
/// wallpaper: if every tile always shows a number, none of them mean anything.
List<AttentionItem> attentionItems(HostelStats s) {
  final items = <AttentionItem>[];

  if (s.studentsUnpaid > 0) {
    items.add(AttentionItem(
      kind: AttentionKind.unpaidFees,
      title: '${countLabel(s.studentsUnpaid, 'resident')} have not paid',
      detail: s.feesPending > 0 ? '${money(s.feesPending)} outstanding' : null,
    ));
  }
  if (s.openComplaints > 0) {
    items.add(AttentionItem(
      kind: AttentionKind.openComplaints,
      title: '${countLabel(s.openComplaints, 'complaint')} still open',
    ));
  }
  if (s.pendingLeaves > 0) {
    items.add(AttentionItem(
      kind: AttentionKind.pendingLeaves,
      title: '${countLabel(s.pendingLeaves, 'leave request')} waiting',
    ));
  }
  if (s.pendingTasks > 0) {
    items.add(AttentionItem(
      kind: AttentionKind.openTasks,
      title: '${countLabel(s.pendingTasks, 'task')} not done',
    ));
  }
  // A resident with no bed is invisible on the room grid and easy to lose. The subtraction is
  // safe: app.students_bed_guard clears bed_id the moment a student is vacated, so occupied
  // beds can never exceed the count of residents who are still here.
  final unhoused = s.activeStudents - s.occupiedBeds;
  if (unhoused > 0) {
    items.add(AttentionItem(
      kind: AttentionKind.unhousedResidents,
      title: '${countLabel(unhoused, 'resident')} without a bed',
      detail: 'Registered but not placed in a room',
    ));
  }
  return items;
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBSCRIPTION
// ─────────────────────────────────────────────────────────────────────────────

/// What to say about the subscription, or null when it is simply fine.
///
/// Only Super Admin can write `public.subscriptions` (rls-policies.sql), so the next step is
/// never a button in this app — it is a phone call. Saying "Renew now" here would be a dead
/// end, and a dead end is worse than a plain statement of fact.
({String title, String detail, bool severe})? subscriptionNotice(HostelStats s) {
  switch (s.subscriptionState) {
    case SubscriptionState.active:
      return null;
    case SubscriptionState.expiring:
      final days = s.subscriptionDaysLeft;
      return (
        title: days == null
            ? 'Subscription ending soon'
            : days <= 0
                ? 'Subscription ends today'
                : 'Subscription ends in ${countLabel(days, 'day')}',
        detail: 'Nivora renews subscriptions — contact your account manager to extend it.',
        severe: false,
      );
    case SubscriptionState.expired:
      final days = s.subscriptionDaysLeft;
      return (
        title: days == null
            ? 'No subscription on this PG'
            : 'Subscription expired ${countLabel(-days, 'day')} ago',
        detail: 'The PG is read-only until it is renewed: staff can look, but nothing can be '
            'recorded. Contact Nivora to restore it.',
        severe: true,
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAILURE → WHAT TO DO NEXT
// ─────────────────────────────────────────────────────────────────────────────

/// An error state that says what to do next, per failure kind.
///
/// "Something went wrong. Retry." is the wrong screen for five of the nine failures this app
/// can produce: there is nothing to retry when RLS refused the row, when the subscription has
/// lapsed, or when the session has ended. [AppFailure] already carries that distinction from
/// the SQLSTATE — this turns it into a sentence and a decision about whether to offer the
/// button at all.
///
/// The switch is exhaustive over a sealed type on purpose: a tenth failure kind added to the
/// data layer becomes a compile error here rather than a silently generic message.
({String title, String next, bool canRetry}) errorGuidance(Object error) {
  final failure = AppFailure.from(error);
  return switch (failure) {
    OfflineFailure() => (
        title: 'No connection',
        next: 'Your phone cannot reach Nivora right now. Reconnect, then pull down to refresh.',
        canRetry: true,
      ),
    AccessDeniedFailure() => (
        title: 'Not your PG',
        next: 'This PG is not registered to your account. Ask Nivora to check who owns it.',
        canRetry: false,
      ),
    ReadOnlyFailure() => (
        title: 'Subscription lapsed',
        next: 'Reading still works; recording does not. Contact Nivora to renew.',
        canRetry: false,
      ),
    NotFoundFailure() => (
        title: 'No longer there',
        next: 'That record has been removed. Go back and pick it again from the list.',
        canRetry: false,
      ),
    SignedOutFailure() => (
        title: 'Session ended',
        next: 'Sign out and sign in again to continue.',
        canRetry: false,
      ),
    ServerFailure() => (
        title: 'Nivora is struggling',
        next: 'The server did not answer in time. Try again in a moment.',
        canRetry: true,
      ),
    ConflictFailure() => (title: 'Already recorded', next: failure.message, canRetry: false),
    InvalidInputFailure() => (title: 'Not accepted', next: failure.message, canRetry: false),
    UnexpectedFailure() => (
        title: 'That did not load',
        next: 'Something unexpected happened on the way. Try again.',
        canRetry: true,
      ),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT ACTIVITY
// ─────────────────────────────────────────────────────────────────────────────

enum ActivityKind { complaint, notice }

/// One line of the activity feed. A view model, not a database row: it exists to put two
/// genuinely different tables onto one timeline without pretending they are the same thing.
class ActivityItem {
  const ActivityItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.at,
    this.detail,
    this.complaintStatus,
  });

  final ActivityKind kind;
  final String id;
  final String title;
  final String? detail;

  /// UTC, as Postgres sent it. Formatted at the point of display.
  final DateTime at;

  /// Set only for [ActivityKind.complaint], so the row can carry a status chip.
  final ComplaintStatus? complaintStatus;
}

/// Merges complaints and notices into one newest-first timeline.
///
/// Both lists arrive already filtered by RLS — an owner sees their hostel's complaints and
/// their hostel's notices, and nothing here narrows that further. Sorting two already-sorted
/// lists is cheap and honest; what it must NOT do is invent activity for tables the owner
/// cannot read, which is why fee payments and audit rows are absent.
List<ActivityItem> buildActivityFeed({
  required List<Complaint> complaints,
  required List<Notice> notices,
  int limit = 6,
}) {
  final items = <ActivityItem>[
    for (final c in complaints)
      ActivityItem(
        kind: ActivityKind.complaint,
        id: c.id,
        title: c.title,
        detail: c.category.label,
        at: c.createdAt,
        complaintStatus: c.status,
      ),
    for (final n in notices)
      ActivityItem(
        kind: ActivityKind.notice,
        id: n.id,
        title: n.title,
        detail: 'Notice to ${n.audience.label.toLowerCase()}',
        at: n.createdAt,
      ),
  ];
  items.sort((a, b) => b.at.compareTo(a.at));
  return items.length <= limit ? items : items.sublist(0, limit);
}
