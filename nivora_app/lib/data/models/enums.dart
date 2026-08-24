library;

import 'parse.dart';

/// Every Postgres enum this app reads, mirrored one-for-one.
///
/// PARSED BY VALUE, NEVER BY INDEX — the same rule `UserRole` in core/auth/session.dart
/// states. Enum ordering in Postgres is not a contract: `alter type ... add value ... before`
/// reorders it, and an index-based parse would silently start reporting every `occupied` bed
/// as `free`. Matching on the wire string cannot do that.
///
/// A value this build does not recognise returns null from `tryParse` rather than guessing.
/// Required columns then throw through [wireOrThrow], which is deliberate: a bed whose status
/// cannot be represented must not be drawn as if it were free.

/// Contract for an enum that carries the exact string Postgres stores.
abstract interface class WireValue {
  /// The literal enum label in the database. Never send anything else.
  String get wire;

  /// Human-facing text. Lives here so one screen cannot spell it differently from another.
  String get label;
}

/// Matches by value; null when this build has never heard of [raw].
T? wireOrNull<T extends WireValue>(List<T> values, String? raw) {
  if (raw == null) return null;
  for (final v in values) {
    if (v.wire == raw) return v;
  }
  return null;
}

/// For NOT NULL columns. Throws rather than substituting a default, because every plausible
/// default here is a lie the UI would then present as fact.
///
/// Raises the same [RowShapeError] the rest of the row parsing does, so "this row does not
/// match schema.sql" is one type to catch rather than two — and so the message distinguishes a
/// null in a NOT NULL column from a value the build has simply never heard of. Those have
/// different causes and different fixes.
T wireOrThrow<T extends WireValue>(
  List<T> values,
  Object? raw,
  String source,
  String column,
) {
  if (raw == null) {
    throw RowShapeError(source, column, 'null, but schema.sql declares it NOT NULL');
  }
  if (raw is! String) {
    throw RowShapeError(source, column, 'expected an enum label, got ${raw.runtimeType}');
  }
  final match = wireOrNull(values, raw);
  if (match != null) return match;
  throw RowShapeError(
    source,
    column,
    '"$raw" is not a value this build knows — the database has an enum value '
    'the app has not been updated for',
  );
}

/// public.bed_status
enum BedStatus implements WireValue {
  free('free', 'Free'),
  occupied('occupied', 'Occupied');

  const BedStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static BedStatus? tryParse(String? v) => wireOrNull(BedStatus.values, v);
}

/// public.student_status
enum StudentStatus implements WireValue {
  active('active', 'Active'),
  onLeave('on_leave', 'On leave'),
  vacated('vacated', 'Checked out');

  const StudentStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  /// The database's own definition of "still a resident" — `status <> 'vacated'` appears in
  /// the unique indexes, the RLS policies and every stats RPC. Kept as one getter so a screen
  /// cannot invent a different definition.
  bool get isResident => this != StudentStatus.vacated;

  static StudentStatus? tryParse(String? v) => wireOrNull(StudentStatus.values, v);
}

/// public.fee_status. Computed by a trigger from amount_due/amount_paid, never set by hand.
enum FeeStatus implements WireValue {
  paid('paid', 'Paid'),
  partial('partial', 'Partly paid'),
  unpaid('unpaid', 'Unpaid');

  const FeeStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static FeeStatus? tryParse(String? v) => wireOrNull(FeeStatus.values, v);
}

/// public.payment_mode
enum PaymentMode implements WireValue {
  cash('cash', 'Cash'),
  upi('upi', 'UPI'),
  bank('bank', 'Bank transfer');

  const PaymentMode(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static PaymentMode? tryParse(String? v) => wireOrNull(PaymentMode.values, v);
}

/// public.complaint_status
enum ComplaintStatus implements WireValue {
  open('open', 'Open'),
  inProgress('in_progress', 'In progress'),
  resolved('resolved', 'Resolved');

  const ComplaintStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  bool get isOpen => this != ComplaintStatus.resolved;

  static ComplaintStatus? tryParse(String? v) => wireOrNull(ComplaintStatus.values, v);
}

/// public.complaint_category
enum ComplaintCategory implements WireValue {
  food('food', 'Food'),
  cleaning('cleaning', 'Cleaning'),
  maintenance('maintenance', 'Maintenance'),
  wifi('wifi', 'Wi-Fi'),
  roommate('roommate', 'Roommate'),
  other('other', 'Other');

  const ComplaintCategory(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static ComplaintCategory? tryParse(String? v) => wireOrNull(ComplaintCategory.values, v);
}

/// public.task_status
enum TaskStatus implements WireValue {
  pending('pending', 'Pending'),
  inProgress('in_progress', 'In progress'),
  done('done', 'Done');

  const TaskStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  bool get isOpen => this != TaskStatus.done;

  static TaskStatus? tryParse(String? v) => wireOrNull(TaskStatus.values, v);
}

/// public.expense_category
enum ExpenseCategory implements WireValue {
  groceries('groceries', 'Groceries'),
  staff('staff', 'Staff'),
  electricity('electricity', 'Electricity'),
  water('water', 'Water'),
  maintenance('maintenance', 'Maintenance'),
  other('other', 'Other');

  const ExpenseCategory(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static ExpenseCategory? tryParse(String? v) => wireOrNull(ExpenseCategory.values, v);
}

/// public.revenue_source
enum RevenueSource implements WireValue {
  fees('fees', 'Fees'),
  mess('mess', 'Mess'),
  other('other', 'Other');

  const RevenueSource(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static RevenueSource? tryParse(String? v) => wireOrNull(RevenueSource.values, v);
}

/// public.announcement_audience. The audience filter is enforced by RLS (§4.6); this enum only
/// lets an author pick one and lets a reader see which group a notice was addressed to.
enum NoticeAudience implements WireValue {
  all('all', 'Everyone'),
  manager('manager', 'Managers'),
  warden('warden', 'Wardens'),
  students('students', 'Students');

  const NoticeAudience(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static NoticeAudience? tryParse(String? v) => wireOrNull(NoticeAudience.values, v);
}

/// public.hostel_status
enum HostelStatus implements WireValue {
  active('active', 'Active'),
  readonly('readonly', 'Read-only'),
  suspended('suspended', 'Suspended');

  const HostelStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static HostelStatus? tryParse(String? v) => wireOrNull(HostelStatus.values, v);
}

/// public.subscription_status. 'expiring' means 15 days or fewer remain — the threshold lives
/// in app.subscription_state(), not here, so this type only names the states.
enum SubscriptionState implements WireValue {
  active('active', 'Active'),
  expiring('expiring', 'Expiring soon'),
  expired('expired', 'Expired');

  const SubscriptionState(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  /// Writes are blocked server-side once this is `expired` (Hard rule §4.4). Screens use it to
  /// explain the refusal in advance; they do not use it to decide whether to allow the write.
  bool get blocksWrites => this == SubscriptionState.expired;

  static SubscriptionState? tryParse(String? v) => wireOrNull(SubscriptionState.values, v);
}
