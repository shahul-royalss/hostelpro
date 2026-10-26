library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// THE CLAY ICONS — every file in `assets/clay/`, by name.
///
/// Glossy 3D clay renders with the light from the top left, cut out on transparent ground. They
/// are what makes a quick action, an empty state or a tab read as Apnivaas before a word is
/// read, and they carry what KIND of thing something is now that the domain hues are retired.
///
/// ── WHAT IS TRUE OF EVERY FILE HERE ───────────────────────────────────────────────────────
///
///  * WebP with alpha. Converted from `design-3d/icons-v3` at quality 85: feature and nav icons
///    at 192px (pixel-exact at 64dp on a 3x phone), role art at its native 320px, the brand mark
///    at 256×186. The 54 files are ~585KB together, against 4.1MB as the source PNGs.
///  * Never tinted. The lighting is baked in; a colour filter turns clay into mud. The one
///    exception is [ClayIcon.greyscale], for an unselected tab.
///  * Always seated on a surface — a well, a tile, a card, a Mist disc — never floating on the
///    cream ground and never on the forest header, where only role art may stand.
///  * No words in any image. Labels stay real Text: translatable, testable, read aloud.
///
/// Every constant is a path; [all] lists them so a test can prove each one is in the bundle and
/// every file in the folder is named here. `role-seeker`, `role-owner-man` and
/// `role-owner-mascot` are deliberately NOT converted — the seeker persona was removed and the
/// alternate owners were not chosen.
abstract final class ClayIcons {
  static const _dir = 'assets/clay';

  /// A resident with a plus — add a tenant.
  static const addTenant = '$_dir/add-tenant.webp';

  /// A signed agreement with a pen.
  static const agreement = '$_dir/agreement.webp';

  /// Rising bars — analytics, trends.
  static const analytics = '$_dir/analytics.webp';

  /// A megaphone — a notice, an announcement.
  static const announcement = '$_dir/announcement.webp';

  /// The Apnivaas brand mark, 256x186 — the header avatar and the auth top bar.
  static const apnivaasMark = '$_dir/apnivaas-mark.webp';

  /// A checklist on a clipboard — attendance.
  static const attendance = '$_dir/attendance.webp';

  /// A bank with circular arrows — a bank transfer.
  static const bankTransfer = '$_dir/bank-transfer.webp';

  /// A single bed — beds.
  static const beds = '$_dir/beds.webp';

  /// A bell with a red dot — notifications.
  static const bell = '$_dir/bell.webp';

  /// A calendar — dates, booking a demo.
  static const calendar = '$_dir/calendar.webp';

  /// A phone with a QR, a rupee coin and a tick — collect a payment.
  static const collectPayment = '$_dir/collect-payment.webp';

  /// A speech bubble with a wrench — a complaint.
  static const complaint = '$_dir/complaint.webp';

  /// A safe with a rupee coin — a deposit.
  static const deposit = '$_dir/deposit.webp';

  /// A percent tag — a discount.
  static const discount = '$_dir/discount.webp';

  /// A bulb and a meter — electricity, meter readings.
  static const electricity = '$_dir/electricity.webp';

  /// A bill with a red arrow — an expense.
  static const expense = '$_dir/expense.webp';

  /// A thali — food, the menu.
  static const food = '$_dir/food.webp';

  /// A gate — late entries, the curfew.
  static const gate = '$_dir/gate.webp';

  /// A broom and a bucket — housekeeping.
  static const housekeeping = '$_dir/housekeeping.webp';

  /// An invoice with a rupee and a tick.
  static const invoice = '$_dir/invoice.webp';

  /// An ID card with a shield — KYC.
  static const kyc = '$_dir/kyc.webp';

  /// An hourglass with a red badge — a late fee.
  static const lateFee = '$_dir/late-fee.webp';

  /// A washing machine — laundry.
  static const laundry = '$_dir/laundry.webp';

  /// A bag with a calendar — leave.
  static const leave = '$_dir/leave.webp';

  /// A wallet with notes and coins — money.
  static const money = '$_dir/money.webp';

  /// A suitcase with a tick — move in.
  static const moveIn = '$_dir/move-in.webp';

  /// A door with an arrow — move out.
  static const moveOut = '$_dir/move-out.webp';

  /// The Home tab: a green-roofed house.
  static const navHome = '$_dir/nav-home.webp';

  /// The Home tab, unselected (greyscale render).
  static const navHomeOff = '$_dir/nav-home-off.webp';

  /// The Money tab: a gold rupee coin.
  static const navMoney = '$_dir/nav-money.webp';

  /// The Money tab, unselected.
  static const navMoneyOff = '$_dir/nav-money-off.webp';

  /// The People tab: two residents.
  static const navPeople = '$_dir/nav-people.webp';

  /// The People tab, unselected.
  static const navPeopleOff = '$_dir/nav-people-off.webp';

  /// The Property tab: a building.
  static const navProperty = '$_dir/nav-property.webp';

  /// The Property tab, unselected.
  static const navPropertyOff = '$_dir/nav-property-off.webp';

  /// A receipt with a tick.
  static const receipt = '$_dir/receipt.webp';

  /// A gift box — referral.
  static const referral = '$_dir/referral.webp';

  /// An alarm clock with a coin — rent reminder.
  static const rentReminder = '$_dir/rent-reminder.webp';

  /// A report with a pie chart.
  static const reports = '$_dir/reports.webp';

  /// A speech bubble with five stars — reviews.
  static const reviews = '$_dir/reviews.webp';

  /// Role art, 320px: the manager.
  static const roleManager = '$_dir/role-manager.webp';

  /// Role art, 320px: the owner (the sign-in hero and the Owner persona).
  static const roleOwner = '$_dir/role-owner.webp';

  /// Role art, 320px: the tenant.
  static const roleTenant = '$_dir/role-tenant.webp';

  /// Role art, 320px: the warden.
  static const roleWarden = '$_dir/role-warden.webp';

  /// A door with a key tag — rooms.
  static const rooms = '$_dir/rooms.webp';

  /// A shield with a padlock — security.
  static const security = '$_dir/security.webp';

  /// Two cogs — settings.
  static const settings = '$_dir/settings.webp';

  /// A trophy — success, all done.
  static const success = '$_dir/success.webp';

  /// A headset — support.
  static const support = '$_dir/support.webp';

  /// A pinboard of notes — tasks.
  static const tasks = '$_dir/tasks.webp';

  /// Three people — the team, staff.
  static const team = '$_dir/team.webp';

  /// A visitor badge — visitors.
  static const visitor = '$_dir/visitor.webp';

  /// A tap with a drop — water.
  static const water = '$_dir/water.webp';

  /// A router — Wi-Fi.
  static const wifi = '$_dir/wifi.webp';

  /// Every file above, for the asset test.
  static const all = <String>[
    addTenant,
    agreement,
    analytics,
    announcement,
    apnivaasMark,
    attendance,
    bankTransfer,
    beds,
    bell,
    calendar,
    collectPayment,
    complaint,
    deposit,
    discount,
    electricity,
    expense,
    food,
    gate,
    housekeeping,
    invoice,
    kyc,
    lateFee,
    laundry,
    leave,
    money,
    moveIn,
    moveOut,
    navHome,
    navHomeOff,
    navMoney,
    navMoneyOff,
    navPeople,
    navPeopleOff,
    navProperty,
    navPropertyOff,
    receipt,
    referral,
    rentReminder,
    reports,
    reviews,
    roleManager,
    roleOwner,
    roleTenant,
    roleWarden,
    rooms,
    security,
    settings,
    success,
    support,
    tasks,
    team,
    visitor,
    water,
    wifi,
  ];

  /// The pixel width each file ships at, so a decode is never asked to upscale.
  static int sourceWidthOf(String path) {
    if (path.contains('/role-')) return 320;
    if (path == apnivaasMark) return 256;
    return 192;
  }

  /// The selected/unselected pair for each of the four tabs that have their own off-art.
  /// Any other tab uses [ClayIcon.greyscale] over its selected icon.
  static const navPairs = <String, String>{
    navHome: navHomeOff,
    navMoney: navMoneyOff,
    navPeople: navPeopleOff,
    navProperty: navPropertyOff,
  };

  /// A Material glyph that says roughly the same thing, for the one case the art cannot load.
  /// A missing asset must degrade to something legible, never to a broken-image box.
  static IconData fallbackFor(String path) => _fallbacks[path] ?? Icons.circle_outlined;

  static const _fallbacks = <String, IconData>{
    addTenant: Icons.person_add_alt_1_rounded,
    agreement: Icons.description_rounded,
    analytics: Icons.insights_rounded,
    announcement: Icons.campaign_rounded,
    apnivaasMark: Icons.home_rounded,
    attendance: Icons.fact_check_rounded,
    bankTransfer: Icons.account_balance_rounded,
    beds: Icons.bed_rounded,
    bell: Icons.notifications_rounded,
    calendar: Icons.calendar_month_rounded,
    collectPayment: Icons.qr_code_2_rounded,
    complaint: Icons.report_problem_rounded,
    deposit: Icons.savings_rounded,
    discount: Icons.percent_rounded,
    electricity: Icons.bolt_rounded,
    expense: Icons.trending_down_rounded,
    food: Icons.restaurant_rounded,
    gate: Icons.door_sliding_rounded,
    housekeeping: Icons.cleaning_services_rounded,
    invoice: Icons.receipt_long_rounded,
    kyc: Icons.badge_rounded,
    lateFee: Icons.hourglass_bottom_rounded,
    laundry: Icons.local_laundry_service_rounded,
    leave: Icons.luggage_rounded,
    money: Icons.account_balance_wallet_rounded,
    moveIn: Icons.login_rounded,
    moveOut: Icons.logout_rounded,
    navHome: Icons.home_rounded,
    navHomeOff: Icons.home_outlined,
    navMoney: Icons.currency_rupee_rounded,
    navMoneyOff: Icons.currency_rupee_rounded,
    navPeople: Icons.people_alt_rounded,
    navPeopleOff: Icons.people_alt_outlined,
    navProperty: Icons.apartment_rounded,
    navPropertyOff: Icons.apartment_outlined,
    receipt: Icons.receipt_rounded,
    referral: Icons.card_giftcard_rounded,
    rentReminder: Icons.alarm_rounded,
    reports: Icons.pie_chart_rounded,
    reviews: Icons.reviews_rounded,
    roleManager: Icons.person_rounded,
    roleOwner: Icons.person_rounded,
    roleTenant: Icons.person_rounded,
    roleWarden: Icons.person_rounded,
    rooms: Icons.meeting_room_rounded,
    security: Icons.shield_rounded,
    settings: Icons.settings_rounded,
    success: Icons.emoji_events_rounded,
    support: Icons.support_agent_rounded,
    tasks: Icons.checklist_rounded,
    team: Icons.groups_rounded,
    visitor: Icons.badge_outlined,
    water: Icons.water_drop_rounded,
    wifi: Icons.wifi_rounded,
  };
}

/// The clay icon that stands for a whole [ApnivaasDomain], for a row or tile with nothing more
/// specific to show.
String domainClayIcon(ApnivaasDomain domain) => switch (domain) {
      ApnivaasDomain.money => ClayIcons.money,
      ApnivaasDomain.rooms => ClayIcons.rooms,
      ApnivaasDomain.people => ClayIcons.navPeople,
      ApnivaasDomain.complaints => ClayIcons.complaint,
      ApnivaasDomain.notices => ClayIcons.announcement,
      ApnivaasDomain.food => ClayIcons.food,
      ApnivaasDomain.security => ClayIcons.security,
    };

/// One clay icon, drawn at [size].
///
/// DECORATIVE BY DEFAULT. Almost every clay icon sits beside a label that already says what it
/// is, and announcing "money, image" before "Collect payment" reads the tile twice. Pass
/// [semanticLabel] only when the picture is the only thing carrying the meaning.
///
/// It decodes at the size it is drawn (never above the file's own width), so a screen of
/// forty icons does not hold forty full bitmaps; and a missing or corrupt file degrades to
/// [ClayIcons.fallbackFor]'s glyph in the brand ink rather than to a broken-image box.
class ClayIcon extends StatelessWidget {
  const ClayIcon(
    this.asset, {
    super.key,
    this.size = ClaySize.action,
    this.semanticLabel,
    this.greyscale = false,
    this.opacity = 1,
  });

  /// One of the [ClayIcons] paths.
  final String asset;

  /// The square the art is drawn in. Use a [ClaySize] step.
  final double size;

  /// Null keeps the icon out of the semantics tree.
  final String? semanticLabel;

  /// Draws the icon through [greyscaleFilter] — an unselected tab whose icon has no off-art.
  final bool greyscale;

  /// Applied in paint, without a save layer.
  final double opacity;

  /// Luminance rows (Rec. 709) with a small lift, which matches the supplied `nav-*-off`
  /// renders closely enough that a tab with off-art and one without read as one set.
  static const greyscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 18, //
    0.2126, 0.7152, 0.0722, 0, 18, //
    0.2126, 0.7152, 0.0722, 0, 18, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = math.min((size * dpr).round(), ClayIcons.sourceWidthOf(asset));
    Widget art = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: decode,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      opacity: opacity >= 1 ? null : AlwaysStoppedAnimation<double>(opacity),
      errorBuilder: (context, _, _) => Center(
        child: Icon(
          ClayIcons.fallbackFor(asset),
          size: size * 0.55,
          color: context.tones.brand.withValues(alpha: opacity),
        ),
      ),
    );
    if (greyscale) art = ColorFiltered(colorFilter: greyscaleFilter, child: art);
    art = SizedBox.square(dimension: size, child: art);

    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: art);
    return Semantics(label: label, image: true, child: ExcludeSemantics(child: art));
  }
}
