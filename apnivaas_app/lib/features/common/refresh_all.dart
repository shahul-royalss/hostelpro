/// PULL TO REFRESH RE-READS EVERYTHING (round 5: "when any account user refreshes their
/// dashboard all syncing must be done perfectly and effectively").
///
/// Every role's home used to re-read only the figures it drew, so a badge, a count on another
/// tab, the photo in the header or the account itself could stay as it was until the next
/// sign-in. This throws away every read the app holds. Invalidating a provider nobody is
/// watching costs nothing — it is rebuilt only when it is next read — so the list can be the
/// whole app rather than one screen's guess at what it shows.
///
/// THE ACCOUNT IS RE-READ TOO ([AuthController.reload]), so a role or PG that changed on the
/// server — a join request accepted, a staff request decided — takes effect on the pull.
///
/// Left alone on purpose: the consent record (re-reading it would flash the consent gate over
/// every screen), the device's own facts (installed UPI apps, the app-update check), signed
/// photo links (they renew themselves) and anything a form is in the middle of editing.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/people_providers.dart';
import '../../data/providers.dart';
import '../../data/repositories/pg_profile_repository.dart';
import '../../data/repositories/staff_request_repository.dart';
import '../../data/repositories/stay_repository.dart';
import '../../data/repositories/tenant_admin_repository.dart';
import '../../data/repositories/upi_repository.dart';
import '../manager/data/manager_providers.dart';
import '../owner/owner_providers.dart';
import '../owner/staff/staff_providers.dart';
import '../student/student_providers.dart';
import '../super_admin/data/sa_providers.dart';
import '../super_admin/data/sa_round3.dart';
import '../warden/data/warden_providers.dart';

void refreshEverything(WidgetRef ref) {
  unawaited(ref.read(authControllerProvider.notifier).reload());

  // The account and the people around it.
  ref
    ..invalidate(myAvatarPathProvider)
    ..invalidate(unreadCountProvider)
    ..invalidate(myStaffHostelsProvider)
    ..invalidate(myHostelsProvider)
    ..invalidate(hostelProvider)
    ..invalidate(hostelContactsProvider)
    ..invalidate(planStatusProvider)
    ..invalidate(ownerStaffProvider)
    ..invalidate(hostelStaffProvider)
    ..invalidate(staffNamesProvider)
    ..invalidate(noticeAuthorsProvider);

  // Requests waiting on someone.
  ref
    ..invalidate(pendingJoinCountProvider)
    ..invalidate(joinRequestsProvider)
    ..invalidate(pendingStaffRequestCountProvider)
    ..invalidate(staffRequestsProvider)
    ..invalidate(checkoutRequestsProvider)
    ..invalidate(ownerCheckoutSummaryProvider)
    ..invalidate(myCheckoutRequestProvider)
    ..invalidate(pendingLeavesProvider)
    ..invalidate(visitorsOnSiteProvider);

  // Residents, rooms and beds.
  ref
    ..invalidate(studentsProvider)
    ..invalidate(studentProvider)
    ..invalidate(myStudentProvider)
    ..invalidate(roommatesProvider)
    ..invalidate(tenantProfileProvider)
    ..invalidate(rentlessResidentsProvider)
    ..invalidate(floorsProvider)
    ..invalidate(roomOccupancyProvider)
    ..invalidate(bedsInRoomProvider)
    ..invalidate(freeBedsProvider)
    ..invalidate(freeBedOptionsProvider)
    ..invalidate(studentsInRoomProvider)
    ..invalidate(studentsAwaitingBedProvider)
    ..invalidate(myTimelineProvider);

  // Money.
  ref
    ..invalidate(hostelStatsProvider)
    ..invalidate(feeLedgerProvider)
    ..invalidate(myRentThisMonthProvider)
    ..invalidate(studentFeeHistoryProvider)
    ..invalidate(studentMonthFeeProvider)
    ..invalidate(studentRefundsProvider)
    ..invalidate(hostelRefundsProvider)
    ..invalidate(recentPaymentsProvider)
    ..invalidate(dailyFinanceProvider)
    ..invalidate(expensesProvider)
    ..invalidate(revenuesProvider)
    ..invalidate(expenseMonthsProvider)
    ..invalidate(expenseDaysProvider)
    ..invalidate(managerExpensesProvider)
    ..invalidate(managerRevenuesProvider)
    ..invalidate(managerFinanceProvider)
    ..invalidate(upiSettingsProvider)
    ..invalidate(myPaymentClaimsProvider)
    ..invalidate(pendingClaimsProvider)
    ..invalidate(allClaimsProvider);

  // The PG's day: complaints, notices, menu, tasks, its public page.
  ref
    ..invalidate(complaintsProvider)
    ..invalidate(complaintProvider)
    ..invalidate(complaintTimelineProvider)
    ..invalidate(noticesProvider)
    ..invalidate(weeklyMenuProvider)
    ..invalidate(tasksProvider)
    ..invalidate(taskLoadProvider)
    ..invalidate(ownerPgProfileProvider)
    ..invalidate(pgPublicProfileProvider)
    ..invalidate(myReviewProvider);

  // Super Admin.
  ref
    ..invalidate(saStatsProvider)
    ..invalidate(saHostelsProvider)
    ..invalidate(saHostelListProvider)
    ..invalidate(saHostelProvider)
    ..invalidate(saOnboardingProvider)
    ..invalidate(saOwnersProvider)
    ..invalidate(saAlertsProvider)
    ..invalidate(saOpenAlertCountProvider)
    ..invalidate(saSubscriptionHistoryProvider)
    ..invalidate(saPayoutProvider)
    ..invalidate(saSignupsProvider)
    ..invalidate(saDeletedAccountsProvider);
}
