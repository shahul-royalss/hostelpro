library;

import 'enums.dart';
import 'parse.dart';

/// The single row public.rpc_hostel_stats(hostel, 'YYYY-MM') returns.
///
/// EVERY FIELD HERE IS COUNTED BY POSTGRES. Nothing on this class is derived from a sample, a
/// cache or a guess, which is the point: a dashboard that invents a number is worse than a
/// dashboard with a gap. If a figure a screen wants is not on this class, the honest move is to
/// add it to the RPC, not to compute an approximation in Dart.
///
/// SECURITY INVOKER, so RLS applies to the counts. That means a STUDENT calling this gets
/// stats over the one row they can see, which is meaningless. Only staff dashboards should
/// call it.
class HostelStats {
  const HostelStats({
    required this.totalBeds,
    required this.occupiedBeds,
    required this.activeStudents,
    required this.openComplaints,
    required this.feesCollected,
    required this.feesPending,
    required this.studentsPaid,
    required this.studentsUnpaid,
    required this.pendingLeaves,
    required this.visitorsToday,
    required this.pendingTasks,
    required this.revenueToday,
    required this.expensesToday,
    required this.revenueMonth,
    required this.expensesMonth,
    required this.subscriptionState,
    this.subscriptionDaysLeft,
  });

  final int totalBeds;
  final int occupiedBeds;

  /// Residents with status <> 'vacated'. Not necessarily equal to [occupiedBeds]: a resident
  /// can be registered before being placed in a bed.
  final int activeStudents;
  final int openComplaints;

  /// Sum of amount_paid across this month's ledger.
  final double feesCollected;

  /// Sum of (due − paid), floored at zero per resident.
  final double feesPending;
  final int studentsPaid;
  final int studentsUnpaid;
  final int pendingLeaves;

  /// Counted against the IST calendar day, matching how the hostel thinks about "today".
  final int visitorsToday;
  final int pendingTasks;
  final double revenueToday;
  final double expensesToday;
  final double revenueMonth;
  final double expensesMonth;

  /// Null when the hostel has never had a subscription row at all. Negative once it has
  /// lapsed — the RPC returns `max(end_date) - current_date`, unclamped, so "-3" means three
  /// days expired and should be shown as such rather than as zero.
  final int? subscriptionDaysLeft;
  final SubscriptionState subscriptionState;

  int get freeBeds => totalBeds - occupiedBeds;

  /// 0.0 to 1.0, or null when there are no beds to divide by. Null rather than 0 on purpose:
  /// "no beds configured" and "nobody has moved in" are different situations.
  double? get occupancyRate =>
      totalBeds == 0 ? null : occupiedBeds / totalBeds;

  factory HostelStats.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_hostel_stats';
    return HostelStats(
      totalBeds: reqInt(row, src, 'total_beds'),
      occupiedBeds: reqInt(row, src, 'occupied_beds'),
      activeStudents: reqInt(row, src, 'active_students'),
      openComplaints: reqInt(row, src, 'open_complaints'),
      feesCollected: reqDouble(row, src, 'fees_collected'),
      feesPending: reqDouble(row, src, 'fees_pending'),
      studentsPaid: reqInt(row, src, 'students_paid'),
      studentsUnpaid: reqInt(row, src, 'students_unpaid'),
      pendingLeaves: reqInt(row, src, 'pending_leaves'),
      visitorsToday: reqInt(row, src, 'visitors_today'),
      pendingTasks: reqInt(row, src, 'pending_tasks'),
      revenueToday: reqDouble(row, src, 'revenue_today'),
      expensesToday: reqDouble(row, src, 'expenses_today'),
      revenueMonth: reqDouble(row, src, 'revenue_month'),
      expensesMonth: reqDouble(row, src, 'expenses_month'),
      subscriptionDaysLeft: optInt(row, src, 'subscription_days_left'),
      subscriptionState: wireOrThrow(
        SubscriptionState.values,
        row['subscription_state'],
        src,
        'subscription_state',
      ),
    );
  }
}

/// One row of public.rpc_room_occupancy(hostel).
///
/// [occupied] counts beds whose student_id is set, not students whose room_id points here.
/// Those can differ for a resident registered without a bed, and the bed count is the one that
/// matches what a warden sees when they walk the floor.
class RoomOccupancy {
  const RoomOccupancy({
    required this.roomId,
    required this.floorId,
    required this.floorNumber,
    required this.roomNumber,
    required this.capacity,
    required this.occupied,
  });

  final String roomId;
  final String floorId;
  final int floorNumber;
  final String roomNumber;
  final int capacity;
  final int occupied;

  int get free => capacity - occupied;
  bool get isFull => occupied >= capacity;
  bool get isEmpty => occupied == 0;

  factory RoomOccupancy.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_room_occupancy';
    return RoomOccupancy(
      roomId: reqString(row, src, 'room_id'),
      floorId: reqString(row, src, 'floor_id'),
      floorNumber: reqInt(row, src, 'floor_number'),
      roomNumber: reqString(row, src, 'room_number'),
      capacity: reqInt(row, src, 'capacity'),
      occupied: reqInt(row, src, 'occupied'),
    );
  }
}

/// The single row public.rpc_sa_dashboard() returns — platform-wide, Super Admin only.
///
/// The RPC ends in `where app.is_super_admin()`, so for anyone else it returns ZERO ROWS rather
/// than an error. The repository turns that into null, and a screen must treat null as "not
/// permitted", never as "the platform has no hostels".
class SaStats {
  const SaStats({
    required this.totalHostels,
    required this.totalOwners,
    required this.totalStudents,
    required this.activeSubs,
    required this.expiringSubs,
    required this.expiredSubs,
    required this.monthlySubscriptionRevenue,
  });

  final int totalHostels;
  final int totalOwners;
  final int totalStudents;
  final int activeSubs;
  final int expiringSubs;
  final int expiredSubs;

  /// Subscriptions created this calendar month, summed.
  final double monthlySubscriptionRevenue;

  factory SaStats.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_sa_dashboard';
    return SaStats(
      totalHostels: reqInt(row, src, 'total_hostels'),
      totalOwners: reqInt(row, src, 'total_owners'),
      totalStudents: reqInt(row, src, 'total_students'),
      activeSubs: reqInt(row, src, 'active_subs'),
      expiringSubs: reqInt(row, src, 'expiring_subs'),
      expiredSubs: reqInt(row, src, 'expired_subs'),
      monthlySubscriptionRevenue: reqDouble(row, src, 'monthly_subscription_revenue'),
    );
  }
}

/// One row of public.rpc_sa_hostels() — the Super Admin's hostel table.
///
/// Every subscription field is nullable because the LEFT JOIN LATERAL finds nothing for a
/// hostel created but never subscribed.
class SaHostelRow {
  const SaHostelRow({
    required this.hostelId,
    required this.hostelName,
    required this.hostelStatus,
    required this.ownerId,
    required this.ownerName,
    required this.subState,
    required this.totalBeds,
    required this.occupiedBeds,
    required this.activeStudents,
    required this.openComplaints,
    required this.createdAt,
    this.address,
    this.ownerEmail,
    this.ownerPhone,
    this.subStart,
    this.subEnd,
    this.subAmount,
    this.daysLeft,
  });

  final String hostelId;
  final String hostelName;
  final HostelStatus hostelStatus;
  final String? address;
  final String ownerId;
  final String ownerName;
  final String? ownerEmail;
  final String? ownerPhone;
  final DateTime? subStart;
  final DateTime? subEnd;
  final double? subAmount;
  final SubscriptionState subState;

  /// Negative once expired; null when there has never been a subscription.
  final int? daysLeft;
  final int totalBeds;
  final int occupiedBeds;
  final int activeStudents;
  final int openComplaints;
  final DateTime createdAt;

  factory SaHostelRow.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_sa_hostels';
    return SaHostelRow(
      hostelId: reqString(row, src, 'hostel_id'),
      hostelName: reqString(row, src, 'hostel_name'),
      hostelStatus: wireOrThrow(HostelStatus.values, row['hostel_status'], src, 'hostel_status'),
      address: optString(row, 'address'),
      ownerId: reqString(row, src, 'owner_id'),
      ownerName: reqString(row, src, 'owner_name'),
      ownerEmail: optString(row, 'owner_email'),
      ownerPhone: optString(row, 'owner_phone'),
      subStart: optDate(row, src, 'sub_start'),
      subEnd: optDate(row, src, 'sub_end'),
      subAmount: optDouble(row, src, 'sub_amount'),
      subState: wireOrThrow(SubscriptionState.values, row['sub_state'], src, 'sub_state'),
      daysLeft: optInt(row, src, 'days_left'),
      totalBeds: reqInt(row, src, 'total_beds'),
      occupiedBeds: reqInt(row, src, 'occupied_beds'),
      activeStudents: reqInt(row, src, 'active_students'),
      openComplaints: reqInt(row, src, 'open_complaints'),
      createdAt: reqTimestamp(row, src, 'created_at'),
    );
  }
}
