library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart';
import '../../payments/payments.dart';
import 'common.dart';
import 'format.dart';
import '../pay_upi.dart';

/// The rent cards — the one thing a resident opens this app to check.
///
/// THE RULE EVERY WIDGET IN THIS FILE FOLLOWS: no arithmetic. Every figure shown is either a
/// column Postgres returned (`amount_due`, `amount_paid`) or a getter on the model that owns it
/// (`balance`, which clamps an overpayment to zero because an overpayment is not a debt). The
/// UI never adds two amounts together, so what is drawn here cannot drift from what the
/// warden's collections screen shows for the same person.

/// The card every rent surface in this file sits on: the card fill at the surface radius with a
/// hairline. Not an [OutlineCard] — that is the history row's widget, and the one a tapped month
/// is found by — and never tappable: the rent card's actions are its buttons.
class _RentShell extends StatelessWidget {
  const _RentShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardSurfaceOf(context),
        borderRadius: Radii.rSurface,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: Padding(padding: const EdgeInsets.all(Space.md), child: child),
    );
  }
}

/// A money figure that shrinks before it truncates. "₹1,20,0…" would be a different number;
/// a smaller "₹1,20,000" is the same one.
class _Figure extends StatelessWidget {
  const _Figure(this.value, {required this.style});
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(value, style: style, maxLines: 1, softWrap: false),
  );
}

/// This month's rent, stated plainly and without a number that is not in the database.
///
/// [row] is the resident's own row of `rpc_fee_ledger`. Null means the ledger had nothing for
/// them this month, which is a real state (registration not finished, or checked out) and is
/// said out loud rather than drawn as ₹0.
class RentCard extends StatelessWidget {
  const RentCard({
    super.key,
    required this.periodMonth,
    required this.row,
    this.payment,
    this.payerName,
    this.refunds = const [],
  });

  /// 'YYYY-MM'. Shown as a month name, never as a due date: `fee_payments` has a period and a
  /// `paid_on`, and no due-date column exists anywhere in the schema. Inventing "due on the
  /// 5th" would be putting a rule on screen that the database does not hold.
  final String periodMonth;
  final FeeLedgerRow? row;

  /// THE `fee_payments` ROW BEHIND THIS MONTH, when the resident's own history has it — and the
  /// only thing on this card that can produce a receipt.
  ///
  /// [row] cannot: `rpc_fee_ledger` returns figures, not a payment id, and a receipt with no
  /// receipt number is a picture of a number rather than a document anyone can look up. So the
  /// screen passes the month's real row down (see features/student/fees_screen.dart), the card
  /// hands it to [Receipt.forFeePayment], and if that returns null — a month opened with
  /// nothing received against it — there is no button. Null here simply means the history read
  /// has not landed, or the desk has not recorded anything yet; either way nothing is drawn.
  final FeePayment? payment;

  /// Printed on the receipt as "Resident". Null prints no line — never a guessed name.
  final String? payerName;

  /// THIS MONTH'S REFUNDS, from `public.payment_refunds` — passed down by the screen, which
  /// already holds the [RefundIndex], rather than read here. One card is one month, so this is
  /// `index.forMonth(studentId, periodMonth)` and nothing else.
  ///
  /// A LIST, because a month can be refunded twice and two refunds are two facts. Empty is the
  /// answer for very nearly every month, and empty draws nothing at all.
  final List<RefundInfo> refunds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rent = row;
    // "Rent · August" — the month's name, in the case the rest of the card is written in. The
    // year is established by the screen; a figure's eyebrow does not need to say it again.
    final eyebrow = 'Rent · ${_titleCase(monthEyebrow(periodMonth))}';
    final eyebrowStyle = t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurfaceVariant);

    if (rent == null) {
      return _RentShell(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: eyebrowStyle),
                  const SizedBox(height: Space.xs),
                  // titleLarge, not the figure's slot. There is no figure here, and a sentence
                  // set at the size of one shouts louder than the card ever does when it has
                  // something to say.
                  Text('No rent record yet', style: t.textTheme.titleLarge),
                  const SizedBox(height: Space.xxs),
                  Text(
                    'Your warden has not set up this month for you. Ask at the office if you '
                    'think that is wrong.',
                    style: t.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            // The wallet says what KIND of card this is; there is no row, and so no state for
            // the art to carry.
            const ClayIcon(ClayIcons.money, size: ClaySize.tile),
          ],
        ),
      );
    }

    final tone = feeTone(rent.status);
    // [feeTone] is context-free, so what it returns is CANONICAL — legible as a shape in both
    // themes and as nothing else. The figure below is 28px TYPE, so it is painted with the
    // resolved value; [StatusPill] and [Meter] are handed the canonical one and resolve it for
    // themselves.
    final accent = context.tones.resolve(tone);
    final owes = rent.balance > 0;

    // ═══ THE FIGURE, THE WORD AND THE ART ═══
    //
    // This is the one figure a resident opens the app for, so it is the largest thing on the
    // card and the only one painted in the state's ink. The state is also said in a WORD, on
    // the chip beneath it — the half a red-green deficiency depends on — and the clay art in
    // the corner changes with it: the alarm clock while something is owed, the ticked receipt
    // once nothing is.
    //
    // The card itself stays the card. It used to take the fee state on its whole ground, which
    // put a red wash behind every unpaid month and forced the chip off its own tint (a chip on
    // a ground of its own tone measures 3.98:1 in dark). A flat card with one coloured figure
    // says the same thing at a quarter of the volume.
    return Semantics(
      label: _spoken(rent),
      container: true,
      child: _RentShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(eyebrow, style: eyebrowStyle),
                      const SizedBox(height: Space.xs),
                      // The hero figure is what is OUTSTANDING when anything is outstanding,
                      // and what was paid when nothing is. A resident checking this card is
                      // answering one question, and it is not "what is my rent".
                      _Figure(
                        rupees(owes ? rent.balance : rent.amountPaid),
                        style: context.textRoles.statValue.copyWith(
                          color: owes ? accent : t.colorScheme.onSurface,
                        ),
                      ),
                      Text(owes ? 'still to pay' : 'paid in full', style: t.textTheme.bodyMedium),
                      const SizedBox(height: Space.sm),
                      StatusPill(
                        label: rent.status.label,
                        tone: tone,
                        icon: switch (rent.status) {
                          FeeStatus.paid => Icons.check_circle_rounded,
                          FeeStatus.partial => Icons.timelapse_rounded,
                          FeeStatus.unpaid => Icons.error_outline_rounded,
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                ClayIcon(owes ? ClayIcons.rentReminder : ClayIcons.receipt, size: ClaySize.banner),
              ],
            ),
            if (rent.amountDue > 0) ...[
              const SizedBox(height: Space.md),
              // No semantic label: the card already speaks as one sentence (see [_spoken]), and
              // a bar that repeated it would say the rent twice. A percentage would be a figure
              // the ledger never stated, so none is given.
              Meter(fraction: _collected(rent), tone: tone),
            ],
            const SizedBox(height: Space.md),
            Divider(height: Strokes.hairline, color: t.colorScheme.outlineVariant),
            const SizedBox(height: Space.xs),
            _Line(label: 'Rent for the month', value: rupees(rent.amountDue)),
            _Line(label: 'Received so far', value: rupees(rent.amountPaid)),
            // BOTH NUMBERS, NEVER THEIR SUM. A partial refund is only legible with two figures
            // on screen — what is credited to the month, and what came back — and this app is
            // not allowed to add them together (see the no-arithmetic rule at the top of this
            // file). The gross a resident originally handed over is not a column, so it is not
            // printed.
            //
            // ONE LINE PER REFUND, for the same reason: two refunds are two facts, and their
            // total is a figure the database never computed. Only settled ones are money that
            // has moved — a pending refund has its own sentence below and no money line,
            // because there is no money to line up yet.
            for (final r in refunds.where((r) => r.isSettled))
              _Line(label: 'Refunded to you', value: rupees(r.amount)),
            if (rent.paidOn != null)
              _Line(
                label: 'Last payment',
                value:
                    '${dayLabel(rent.paidOn!)}'
                    '${rent.mode == null ? '' : ' · ${rent.mode!.label}'}',
              ),
            // The receipt for THIS month, and only for this month. A card headed "August" that
            // could open July's document would be worse than one that opens nothing.
            if (payment != null && payment!.periodMonth == periodMonth)
              _ReceiptAction(payment: payment!, payerName: payerName, refunds: refunds),
            // ═══ THE REASON THE FIGURE ABOVE MOVED ═══
            //
            // This is the whole point of the feature. A resident who paid in full and later
            // sees "PARTLY PAID" with no explanation has been told, by an app they trust with
            // their rent, that their money went missing. The two money lines above state the
            // fact; this states the CAUSE, and it is placed before the pay-at-desk note so the
            // explanation is read before the instruction.
            if (refunds.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              RefundNote(refunds: refunds, outstanding: owes ? rent.balance : null),
            ],
            if (owes) ...[
              const SizedBox(height: Space.md),
              // ═══ THE PAY BUTTON, AND WHY IT IS ON THIS CARD ═══
              //
              // This card is drawn on the resident's HOME as well as on their Fees tab, so
              // paying is one tap from opening the app — which is the reason the app gets
              // opened at all. The checkout is Razorpay's own native sheet, taking UPI, cards,
              // netbanking and wallets (features/payments/pay_rent.dart).
              //
              // It is the screen's one filled forest button, and it means "the action" — paying
              // rent IS the action on this card.
              //
              // ONLY WHEN SOMETHING IS OWED: the whole block sits inside `if (owes)`. A settled
              // month shows no button, because an app that offers to take money it is not owed
              // is one a resident stops trusting.
              PayRentButton(amount: rent.balance),
              const SizedBox(height: Space.sm),
              PayWithUpiButton(amount: rent.balance, periodMonth: periodMonth),
              const SizedBox(height: Space.sm),
              PayAtDeskNote(amount: rent.balance),
            ],
          ],
        ),
      ),
    );
  }

  /// 'AUGUST' → 'August'. [monthEyebrow] is the shared formatter and shouts; this card does
  /// not.
  static String _titleCase(String word) => word.isEmpty
      ? word
      : '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}';

  /// How much of this month's rent is in, as a WIDTH.
  ///
  /// THE ONE DIVISION IN THIS FILE, AND IT NEVER BECOMES A FIGURE. Both operands are columns
  /// `rpc_fee_ledger` returned, and both are already printed verbatim as the two `_Line` rows
  /// directly beneath the bar — so there is nothing here that could disagree with the ledger,
  /// which is what the no-arithmetic rule at the top of this file exists to prevent. No
  /// percentage is rendered and none may be: the moment this result is formatted as text it is
  /// a number the database never said.
  ///
  /// Guarded on `amountDue > 0` at the call site. A month opened at ₹0 is a real row (a
  /// resident who moved in mid-month and owes nothing yet) and it has no fraction, so it gets
  /// no bar rather than a full one.
  static double _collected(FeeLedgerRow rent) => rent.amountPaid / rent.amountDue;

  /// One sentence for a screen reader, instead of six disconnected fragments.
  ///
  /// The refund is spoken LAST and as its own clause. A screen reader user gets the same
  /// explanation a sighted one does, in the same order: the position first, then why it moved.
  String _spoken(FeeLedgerRow rent) {
    final month = monthLabel(periodMonth);
    final refunded = refunds
        .map(
          (r) => r.isSettled
              ? ' ${rupees(r.amount)} was refunded to you.'
              : ' A refund of ${rupees(r.amount)} is on its way to you.',
        )
        .join();
    if (rent.balance > 0) {
      return 'Rent for $month: ${rupees(rent.balance)} still to pay '
          'of ${rupees(rent.amountDue)}.$refunded';
    }
    return 'Rent for $month: paid in full, ${rupees(rent.amountPaid)}.$refunded';
  }
}

/// The resident's receipt for one recorded month, or null when that row is not evidence.
///
/// ═══ THE ONE PLACE THIS SCREEN BUILDS A RECEIPT ═══
/// The rent card and every row of the payment history route through here, so the two can never
/// print different documents for the same month. It adds nothing of its own: the figures are
/// [FeePayment]'s columns, the hostel's name is `st_hostel_contacts`, and the null it returns
/// for a month with `amount_paid = 0` is [Receipt.forFeePayment]'s refusal, not a rule repeated
/// here. A caller that gets null must draw no affordance at all — see [_ReceiptAction].
///
/// The name is passed IN rather than read here. This runs once per history row, and a resident
/// reading two years of rent should not fan out twenty reads of their own `students` row to put
/// their own name on twenty documents.
Receipt? residentReceipt(
  WidgetRef ref,
  FeePayment payment, {
  String? payerName,
  List<RefundInfo> refunds = const [],
}) {
  return Receipt.forFeePayment(
    payment,
    payerName: payerName,
    // The paper prints the SETTLED ones (see [Receipt.forFeePayment]); passing the month's
    // whole list keeps that decision in one place rather than filtered differently at each of
    // the two call sites below.
    refunds: refunds,
    // `.value`, not `.requireValue`: a hostel name this device has not fetched yet is a line
    // the paper simply omits, and is never a reason to withhold the receipt itself.
    hostelName: ref.watch(hostelContactsProvider).value?.hostelName,
  );
}

/// "View receipt", when there is one — and nothing at all when there is not.
///
/// A month can exist with nothing received against it (opened, then corrected back to zero when
/// a payment was recorded against the wrong resident). That is a real state, and the honest
/// drawing of it is the absence of a button rather than a button that explains itself after
/// being pressed.
///
/// A pill rather than a full-width button: the receipt is a document to look at, and on a card
/// that may also carry the pay button below it, two full-width buttons would argue about which
/// one is the action.
class _ReceiptAction extends ConsumerWidget {
  const _ReceiptAction({required this.payment, this.payerName, this.refunds = const []});

  final FeePayment payment;
  final String? payerName;
  final List<RefundInfo> refunds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = residentReceipt(ref, payment, payerName: payerName, refunds: refunds);
    if (receipt == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        // Not "Download" and not "Pay": this opens the document, and the sharing and saving
        // live on the receipt screen where the paper the resident is sending is on screen.
        child: PillButton(
          label: 'View receipt',
          icon: Icons.receipt_long_rounded,
          onPressed: () => showReceipt(context, receipt),
        ),
      ),
    );
  }
}

/// "Or pay cash at the desk" — the SECOND of the two ways to settle rent.
///
/// Online checkout now sits directly above this ([PayRentButton]). This panel stayed, and stayed
/// unchanged in tone, because the desk is not a fallback for a broken app — it is how nearly
/// every PG in the country already works, and a resident with no bank app, a declined card, or
/// cash in hand still walks to the office. A screen offering only the online path would strand
/// exactly the people this one is for.
///
/// IT IS NOT DRAWN AS AN ERROR. No error tone, no retry, no dead button: money is handed over at
/// the office and a warden records it (features/warden/actions/record_payment_sheet.dart is the
/// other half).
///
/// EVERY VALUE ON IT IS REAL. [amount] is `balance` from the resident's own `rpc_fee_ledger`
/// row — the same column the hero figure above prints, so the card cannot name two prices — and
/// the warden's name and phone come from `st_hostel_contacts`. Nothing is invented: no due
/// date (the schema has no due-date column), no office hours, no counter number.
///
/// THE CONTACT READ IS ALLOWED TO BE ABSENT. `hostelContactsProvider` may be in flight, may
/// have failed, or may genuinely have no warden on the hostel — and none of those change what
/// this panel is for. It degrades to the sentence without a name rather than growing a fourth
/// state of its own: the resident's Profile screen owns the contact card and its loading,
/// empty and failed states, and repeating them inside the rent card would be two places telling
/// one story.
class PayAtDeskNote extends ConsumerWidget {
  const PayAtDeskNote({super.key, required this.amount});

  /// What is still owed this month, in rupees. A column, never a sum computed here.
  final double amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    // `.value` and not `.requireValue`: absent is a normal answer here. Riverpod 3 keeps a
    // failed provider in AsyncLoading-carrying-the-error while it retries, and `.value` reads
    // through both without pretending the read succeeded.
    final contacts = ref.watch(hostelContactsProvider).value;
    final warden = contacts?.wardenName?.trim();
    final phone = contacts?.wardenPhone?.trim();

    return _Well(
      // The warden at the desk — a person, because this route is a person.
      art: ClayIcons.roleWarden,
      children: [
        Text('Or pay cash at the desk', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.xxs),
        Text(
          'Hand ${rupees(amount)} to '
          '${warden == null || warden.isEmpty ? 'your warden' : warden} '
          'at the office.',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: Space.xs),
        Text(
          phone == null || phone.isEmpty
              ? 'It appears here as soon as your warden records it.'
              : 'It appears here as soon as your warden records it. Desk: $phone',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A well INSIDE the rent card, not a second card on top of it: the neutral fill one step off
/// the card, a 46dp clay figure, and the words beside it. Shared by the desk note and the refund
/// note so the two asides on one card are visibly the same kind of thing.
class _Well extends StatelessWidget {
  const _Well({required this.art, required this.children});

  final String art;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: t.colorScheme.surfaceContainer, borderRadius: Radii.rButton),
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClayIcon(art, size: ClaySize.list),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sentence that stops a corrected bill from reading as theft.
///
/// ═══ WHY THIS EXISTS AT ALL ═══
/// `rz_reverse_fee` subtracts a processed refund from `fee_payments.amount_paid`, and the
/// BEFORE trigger `app.fee_status_compute` then recomputes the status from the new figure. So a
/// month that said PAID last week says PARTLY PAID today, the resident did nothing, and until
/// this panel existed there was not one word on the screen to say why. A bill that quietly
/// reverts reads as the app losing their money.
///
/// ═══ WHY THIS IS NOT PAINTED IN THE ALARM COLOUR ═══
/// A refund is a FACT, not a fault. Nobody did anything wrong, nothing failed, and there is
/// nothing for the resident to fix — so the three tones this app already spends on rent are all
/// the wrong answer:
///
///   error   (#C8443B) is 'unpaid'. Drawing a refund in it says the resident is in arrears
///           because money was returned to them, which is the accusation this whole feature
///           exists to prevent.
///   warning (#986A10) is 'due / still owing / expiring' — tokens.dart's own list. A refunded
///           month would then look exactly like a month that needs chasing.
///   success (#3C8A5C) is 'paid'. Money leaving the hostel is not a collection.
///
/// So: [ApnivaasColors.info], the app's factual tone — the blue the kit maps to refund, new and
/// info, i.e. "here is something you should know". It is a canonical token with measured
/// ratios in both themes, so no new colour and no new pairing enters the palette here.
/// `test/theme_contrast_test.dart` measures the pairing this widget actually paints.
///
/// ═══ SETTLED AND PENDING ARE DIFFERENT CLAIMS ═══
/// A `processed` refund is money that has left; a `pending` one is an instruction that has not
/// moved anything on either side. They get different sentences, because a resident who reads
/// "refunded" and finds nothing in their bank has been misled by this screen. Failed refunds
/// never reach here — [RefundIndex] drops them, since nothing happened to explain.
///
/// ═══ EVERY WORD IS A COLUMN ═══
/// The figure is `amount_paise`, the date is `processed_at` (or `created_at` while pending),
/// and [outstanding] is the resident's own `balance` — the same value the hero figure above
/// prints, so the card cannot name two positions. No date is invented when the server sent
/// none, and no REASON is invented ever: this app does not know why a refund happened.
class RefundNote extends StatelessWidget {
  const RefundNote({super.key, required this.refunds, this.outstanding});

  /// One month's refunds, newest settled first. Never empty at the call site.
  final List<RefundInfo> refunds;

  /// What is still to pay, when anything is — [FeeLedgerRow.balance], passed in rather than
  /// recomputed. Null means the month is square anyway, which is a different sentence and not a
  /// missing one.
  final double? outstanding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owed = outstanding;
    final settled = refunds.where((r) => r.isSettled).toList(growable: false);

    return _Well(
      // Money going back the way it came. The headline below carries the info ink; the art
      // only says what kind of aside this is.
      art: ClayIcons.bankTransfer,
      children: [
        // One headline per refund. Two refunds in a month is rare and their sum is a figure no
        // column holds, so they are stated rather than added.
        for (final r in refunds) ...[
          Text(
            _headline(r),
            style: t.textTheme.titleSmall?.copyWith(
              color: context.tones.resolve(ApnivaasColors.info),
            ),
          ),
          const SizedBox(height: Space.xxs),
        ],
        Text(_explanation(settled.isNotEmpty, owed), style: t.textTheme.bodyMedium),
      ],
    );
  }

  /// "₹2,000 refunded on 12 Sep 2026" / "₹2,000 refund on its way".
  ///
  /// The verb carries the status. A pending refund is never worded as money returned, because a
  /// resident who reads that and looks at their bank will conclude the bank is wrong.
  static String _headline(RefundInfo r) {
    final amount = rupees(r.amount);
    final on = r.on;
    if (!r.isSettled) {
      return on == null ? '$amount refund on its way' : '$amount refund requested ${dayLabel(on)}';
    }
    return on == null ? '$amount refunded' : '$amount refunded on ${dayLabel(on)}';
  }

  /// The sentence that does the actual work: what the resident is looking at, and why.
  static String _explanation(bool anySettled, double? owed) {
    if (!anySettled) {
      // Nothing has moved on either side, so there is nothing on the bill to explain — only
      // something to expect.
      return 'Nothing has changed on this month yet. It will update here once the money '
          'reaches you.';
    }
    if (owed == null) {
      // A refund that left the month settled anyway — an overpayment handed back. Saying the
      // month now owes something would be the card disagreeing with the figure above it.
      return 'That money went back to you. This month is still settled.';
    }
    return 'That money went back to you, so this month now shows ${rupees(owed)} still to '
        'pay. Nothing has gone missing — ask at the office if this is not what you expected.';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.tone});
  final String label;
  final String value;

  /// A CANONICAL tone for the figure — the pending amount on a history row. Resolved here.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs + Space.hair),
      // BOTH HALVES FLEX, which is what stops this row from breaking. The value used to be a
      // plain Text, so the Row measured it unbounded: at 320dp and 1.3x, "16 Aug 2026 · UPI"
      // asked for 309 of the card's 256 points, the label was left with none, and it wrapped to
      // one character per line — a 286-point-tall row where a 24-point one belonged. The same
      // split [DetailRow] uses, so a labelled value behaves the same way everywhere in this app.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Text(
              label,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: t.textTheme.titleSmall?.copyWith(color: accent),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// One month of the resident's own payment history — and the way to its receipt.
///
/// Every column a person needs to check a month against their bank: what was owed, what was
/// received, what is still pending, when it landed and how it was paid.
///
/// ═══ THE ROW IS THE WAY TO THE DOCUMENT ═══
/// A resident who hands cash to the warden gets a status word on this screen a moment later,
/// and a status word is not a receipt. Tapping the month opens the printed one, built from THIS
/// row — the same `fee_payments` row the warden's copy was built from, with the same receipt
/// number on it, so the two pieces of paper cannot disagree.
///
/// A MONTH WITH NOTHING RECEIVED IS NOT TAPPABLE. `Receipt.forFeePayment` returns null for it
/// and the row then carries no affordance and no ink response, rather than a tap that opens
/// nothing.
class FeePaymentTile extends ConsumerWidget {
  const FeePaymentTile({super.key, required this.payment, this.payerName, this.refunds = const []});

  final FeePayment payment;

  /// This month's refunds, from the screen's [RefundIndex]. Empty draws nothing.
  final List<RefundInfo> refunds;

  /// Printed on the receipt as "Resident". Passed down from the screen, which already holds the
  /// resident's own row — see [residentReceipt].
  final String? payerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final tone = feeTone(payment.status);
    final receipt = residentReceipt(ref, payment, payerName: payerName, refunds: refunds);
    final chip = StatusPill(label: payment.status.label, tone: tone);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(monthLabel(payment.periodMonth), style: t.textTheme.titleMedium),
        const SizedBox(height: Space.hair),
        Text(
          payment.paidOn == null
              // A row with no paid_on exists only where a month was opened without a payment.
              // Say that, rather than printing a date that is not there.
              ? 'No payment date recorded'
              : 'Received ${dayLabel(payment.paidOn!)}'
                    '${payment.mode == null ? '' : ' · ${payment.mode!.label}'}',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    return OutlineCard(
      onTap: receipt == null ? null : () => showReceipt(context, receipt),
      child: LayoutBuilder(
        builder: (context, box) {
          // The chip beside the month while both fit; under it once large text or a narrow
          // phone would leave the month a sliver — the rule [ListRow] follows for its trailing
          // control.
          final stacked = box.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(1) >= 1.6;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The ticked receipt for a settled month, the alarm clock for one with money
                  // still owed — the same pair the rent card above wears.
                  ClayIcon(
                    payment.status == FeeStatus.paid ? ClayIcons.receipt : ClayIcons.rentReminder,
                    size: ClaySize.list,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              words,
                              const SizedBox(height: Space.xs),
                              chip,
                            ],
                          )
                        : words,
                  ),
                  if (!stacked) ...[const SizedBox(width: Space.xs), chip],
                ],
              ),
              const SizedBox(height: Space.sm),
              // Every column a person needs to check a month against their bank, on a well so
              // the three figures read as one fact — side by side while they fit, and one line
              // each once large text would run "₹6,000₹3,000" together.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainer,
                  borderRadius: Radii.rControl,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
                  child: stacked
                      ? Column(
                          children: [
                            _Line(label: 'Due', value: rupees(payment.amountDue)),
                            _Line(label: 'Paid', value: rupees(payment.amountPaid)),
                            _Line(
                              label: 'Pending',
                              value: rupees(payment.balance),
                              tone: payment.balance > 0 ? tone : null,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _Cell(label: 'Due', value: rupees(payment.amountDue)),
                            ),
                            const SizedBox(width: Space.xs),
                            Expanded(
                              child: _Cell(label: 'Paid', value: rupees(payment.amountPaid)),
                            ),
                            const SizedBox(width: Space.xs),
                            Expanded(
                              child: _Cell(
                                label: 'Pending',
                                value: rupees(payment.balance),
                                tone: payment.balance > 0 ? tone : null,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              // A fourth cell would not survive 320dp at 1.3x text, so each refund gets a line
              // of its own rather than a column. It is the only info-coloured thing on this row,
              // which is what makes it findable when a resident is scrolling two years of months
              // looking for the one that changed.
              for (final r in refunds) ...[
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Icon(
                      Icons.assignment_return_rounded,
                      size: IconSize.sm,
                      color: context.tones.info,
                    ),
                    const SizedBox(width: Space.xxs),
                    Expanded(
                      child: Text(
                        _refundLine(r),
                        style: t.textTheme.bodySmall?.copyWith(color: context.tones.info),
                      ),
                    ),
                  ],
                ),
              ],
              if (payment.notes != null && payment.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text(payment.notes!.trim(), style: t.textTheme.bodySmall),
              ],
              // Said out loud rather than left to be discovered by tapping. A whole card that
              // happens to be tappable looks exactly like one that is not.
              if (receipt != null) ...[
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'View receipt',
                        style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: IconSize.lg,
                      color: t.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "₹2,000 refunded 12 Sep 2026" — the history row's one-liner.
///
/// Same rule as [RefundNote]: the verb carries the status, so a refund that has not moved yet
/// is never worded as one that has.
String _refundLine(RefundInfo r) {
  final amount = rupees(r.amount);
  final on = r.on;
  if (!r.isSettled) {
    return on == null ? '$amount refund on its way' : '$amount refund requested ${dayLabel(on)}';
  }
  return on == null ? '$amount refunded' : '$amount refunded ${dayLabel(on)}';
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Canonical in, resolved at the paint site: this is 13px type, and the canonical reds and
    // ambers are only rated as graphics.
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.hair),
        _Figure(value, style: t.textTheme.titleSmall?.copyWith(color: accent)),
      ],
    );
  }
}

/// Where the resident lives, from the same ledger row that carries their rent.
///
/// `room_number` and `bed_number` come through joins RLS permits — a resident may read the
/// hostel's rooms, and only the beds in their OWN room. There is no cheaper single read that
/// names a resident's room: `students` stores ids, not numbers.
class RoomBedCard extends StatelessWidget {
  const RoomBedCard({
    super.key,
    required this.roomNumber,
    required this.bedNumber,
    this.roommates,
    this.hero = false,
  });

  final String? roomNumber;
  final int? bedNumber;

  /// Draws the assigned card as the screen's SUBJECT — the Mist tile — for Profile, where "Your
  /// room" is the section and this card is the whole of it. False draws it on the plain card.
  /// An unassigned room ignores it: "Not assigned yet" is an absence, and an absence is not
  /// dressed in a colour.
  final bool hero;

  /// Who else is in the room — as the read that answers it, not as a number.
  ///
  /// An [AsyncValue] and not an `int?` because null could not tell three different facts apart:
  /// the read is still in flight, it came back empty, and it failed. Those are three different
  /// sentences, and "you have the room to yourself" is very nearly the opposite of "we could not
  /// find out" — while a line that simply vanishes reads as the first one.
  ///
  /// THE WHOLE VALUE, NOT A MAPPED COUNT. `roommates.whenData((m) => m.length)` looked like the
  /// tidy way to hand this a number and it is a trap: `whenData` dispatches on the RUNTIME TYPE,
  /// and Riverpod 3 represents a failed read that it is still retrying as an `AsyncLoading` that
  /// CARRIES the error. `whenData` takes the loading branch for it and returns a bare
  /// `AsyncLoading`, throwing the error away — so the card would show a placeholder for a read
  /// that had already failed, for the whole ~38 seconds the default ten-retry backoff takes.
  ///
  /// Null (the parameter itself) means this card is not drawing the line at all, which is what
  /// Profile does: the full roommate list sits directly beneath it there and owns that failure.
  final AsyncValue<List<Roommate>>? roommates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final assigned = roomNumber != null;
    final mist = hero && assigned;
    final ground = mist
        ? (dark ? ApnivaasColors.darkMist : ApnivaasColors.mist)
        : cardSurfaceOf(context);
    // On Mist the secondary ink is the Mist's own; the muted card ink is tuned for the card.
    final quiet = mist
        ? (dark ? ApnivaasColors.onSurfaceVariant : ApnivaasColors.mistInk)
        : t.colorScheme.onSurfaceVariant;

    // ONE Text FOR ROOM AND BED, and it stays one. A mockup split them across two lines with a
    // bed TYPE on the second ("Bed B · Standard Ac") — `public.beds` has `bed_number int` and no
    // type column at all, so the second line would have had to be invented.
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const ClayIcon(ClayIcons.beds, size: ClaySize.tile),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your room', style: t.textTheme.bodySmall?.copyWith(color: quiet)),
                  const SizedBox(height: Space.hair),
                  if (assigned)
                    Text(
                      bedNumber == null ? 'Room $roomNumber' : 'Room $roomNumber · Bed $bedNumber',
                      style: t.textTheme.headlineSmall?.copyWith(
                        color: mist
                            ? (dark ? ApnivaasColors.onSurface : ApnivaasColors.forest)
                            : null,
                      ),
                    )
                  else ...[
                    Text('Not assigned yet', style: t.textTheme.titleMedium),
                    const SizedBox(height: Space.hair),
                    Text(
                      'Your warden will place you in a room and bed.',
                      style: t.textTheme.bodySmall?.copyWith(color: quiet),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (assigned) ?_sharing(context, ring: ground, quiet: quiet),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ground,
        borderRadius: Radii.rSurface,
        border: mist
            ? null
            : Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: Padding(padding: const EdgeInsets.all(Space.md), child: body),
    );
  }

  /// The sharing line, in whichever state the roommate read is actually in.
  ///
  /// Four outcomes, four appearances. In flight is a placeholder the size of the line it will
  /// become; an empty room is stated out loud; a failure says so and points at the
  /// pull-to-refresh every screen that draws this card already has; and a refusal is said
  /// plainly, with no retry affordance for something retrying cannot fix.
  ///
  /// Branched by hand rather than through `when`, because the precedence matters and the flags
  /// bury it: A KNOWN FAILURE OUTRANKS A STALE COUNT. If a refresh failed, the number this
  /// device is holding is no longer something the card can vouch for, and stating it anyway is
  /// the quiet kind of wrong — it looks exactly like a fact.
  Widget? _sharing(BuildContext context, {required Color ring, required Color quiet}) {
    final mates = roommates;
    if (mates == null) return null;
    final t = Theme.of(context);

    final Widget line;
    if (mates.hasError) {
      line = Text(
        errorGuidance(mates.error!).canRetry
            ? 'Could not check who else is in this room. Pull down to try again.'
            : 'Who else is in this room is not available to you.',
        style: t.textTheme.bodySmall?.copyWith(color: quiet),
      );
    } else if (mates.hasValue) {
      final people = mates.requireValue;
      final sentence = Text(
        people.isEmpty
            ? 'You have the room to yourself'
            : 'Sharing with ${countLabel(people.length, 'other resident')}',
        style: t.textTheme.bodySmall?.copyWith(color: quiet),
      );
      // The overlapping discs. The initials are the roommates' own, from the read this sentence
      // is already counting — `st_my_roommates()` returns name, phone and bed and that is the
      // entire set a resident may see, so a disc is the most of a person that can honestly
      // appear here. No cluster for an empty room: there is nobody to draw.
      line = people.isEmpty
          ? sentence
          : Row(
              children: [
                AvatarCluster(names: [for (final mate in people) mate.fullName], ring: ring),
                const SizedBox(width: Space.xs),
                Expanded(child: sentence),
              ],
            );
    } else {
      line = const StillSkeleton(widthFactor: 0.6);
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: line,
    );
  }
}

/// The end of the payment history: the way to the months that did not fit on this page.
///
/// ═══ WHY THIS IS A BUTTON AND NOT AN INFINITE SCROLL ═══
/// The list it sits under is a section of a ListView that also holds the rent card, not a list
/// of its own — so a footer that fetched the moment it was BUILT (the trick
/// [StudentPagedList] uses, where the element is only created once it scrolls into view) would
/// be built immediately inside its Column and would walk the resident's entire history on
/// arrival: two years is two more requests nobody asked for, on mobile data.
///
/// FOUR STATES, KEPT APART. Idle offers the months; pressed shows that something is happening;
/// a failure says what went wrong and offers the same tap again; and the rows already on screen
/// are never disturbed by any of it — a page that fails to load must not take a resident's
/// paid months away from them.
class MoreMonths extends StatefulWidget {
  const MoreMonths({super.key, required this.onLoadMore});

  /// Returns null on success, or the failure to show without touching the rows above.
  final Future<AppFailure?> Function() onLoadMore;

  @override
  State<MoreMonths> createState() => _MoreMonthsState();
}

class _MoreMonthsState extends State<MoreMonths> {
  bool _busy = false;
  AppFailure? _failure;

  Future<void> _more() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await widget.onLoadMore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(
        children: [
          if (_failure != null) ...[
            Text(
              errorGuidance(_failure!).next,
              style: t.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
          ],
          OutlinedButton(
            onPressed: _busy ? null : _more,
            child: _busy
                ? const SizedBox(
                    width: IconSize.md,
                    height: IconSize.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_failure == null ? 'Show earlier months' : 'Try again'),
          ),
        ],
      ),
    );
  }
}
