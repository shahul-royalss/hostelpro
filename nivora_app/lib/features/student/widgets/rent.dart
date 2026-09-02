library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../../payments/payments.dart';
import 'common.dart';
import 'format.dart';

/// The rent cards — the one thing a resident opens this app to check.
///
/// THE RULE EVERY WIDGET IN THIS FILE FOLLOWS: no arithmetic. Every figure shown is either a
/// column Postgres returned (`amount_due`, `amount_paid`) or a getter on the model that owns it
/// (`balance`, which clamps an overpayment to zero because an overpayment is not a debt). The
/// UI never adds two amounts together, so what is drawn here cannot drift from what the
/// warden's collections screen shows for the same person.

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

    if (rent == null) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(
              label: 'Rent · ${monthEyebrow(periodMonth)}',
              trailing: const IconTile(
                icon: Icons.account_balance_wallet_rounded,
                tone: NivoraColors.textMuted,
              ),
            ),
            const SizedBox(height: Space.sm),
            // titleLarge, not the hero slot. There is no figure here, and a sentence set at 32px
            // shouts louder than the rent card ever does when it has something to say.
            Text('No rent record yet', style: t.textTheme.titleLarge),
            const SizedBox(height: Space.xxs),
            Text(
              'Your warden has not set up this month for you. Ask at the office if you think '
              'that is wrong.',
              style: t.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final tone = feeTone(rent.status);
    // [feeTone] is context-free, so what it returns is CANONICAL — legible as a shape in both
    // themes and as nothing else. The hero figure below is `display-lg`, 48px TYPE, so it is
    // painted with the resolved value; [StatusPill] and [IconTile] are handed the canonical one
    // and resolve it for themselves.
    final accent = context.tones.resolve(tone);
    final owes = rent.balance > 0;

    // ═══ THE CARD'S GROUND CARRIES THE FEE STATE ═══
    //
    // This is the one figure a resident opens the app for, so this is the one card in the
    // resident shell that states its status with its whole surface instead of with a badge in
    // the corner. Paid is green, part-paid amber, unpaid red — the same three meanings
    // [feeTone] already assigned, at card scale.
    //
    // THE PILL BECAME A WORD, and that is a measurement rather than a preference. A chip's
    // fill is a tint of its tone; over a ground that is already a tint of the same tone it
    // lands twice as far toward its own label and measures 3.98:1 in the dark theme, which no
    // alpha rescues. So the ground does the chip's job and the word sits on it at full
    // strength — 4.56:1 dark, 5.83:1 light. See [NivoraSemantics.surfaceTintAlpha] and
    // [StatusWord]. The WORD itself never went anywhere, because that is the half a red-green
    // deficiency depends on.
    return ToneSurface(
      tone: tone,
      // Null: the status word is not a header here, it sits on the hero figure's own baseline
      // where the mockup puts it. [ToneSurface] allows that for exactly this case.
      statusLabel: null,
      semanticLabel: _spoken(rent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The design's card header: eyebrow left, a tinted icon box right. The box carries
          // the fee tone, so the card announces its state before the figure has been read.
          CardHeader(
            label: 'Rent · ${monthEyebrow(periodMonth)}',
            trailing: IconTile(icon: Icons.account_balance_wallet_rounded, tone: tone),
          ),
          const SizedBox(height: Space.sm),
          // The hero figure is what is OUTSTANDING when anything is outstanding, and what was
          // paid when nothing is. A resident checking this screen is answering one question,
          // and it is not "what is my rent".
          //
          // The status pill moved down here onto the figure's baseline, which is where the
          // mockup puts it — `flex items-baseline gap-2`, the hero and its qualifier read as
          // one phrase instead of as a heading and a badge at opposite ends of a row.
          //
          // A Wrap and not a Row. A 48px figure beside a pill whose width is set by the longest
          // status word ("PARTLY PAID") is the one pairing on this card that cannot be
          // guaranteed to fit: measured at 320dp it holds to 1.3x and breaks at 1.6x. A Row
          // overflows there; this drops the pill onto its own line and the card simply gets
          // taller, which is what a resident who has turned their text up is asking for.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                rupees(owes ? rent.balance : rent.amountPaid),
                style: t.textTheme.headlineLarge?.copyWith(color: owes ? accent : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Padding(
                // Lifts the word off the descender line onto the figure's own baseline.
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: StatusWord(
                  label: rent.status.label,
                  tone: tone,
                  icon: switch (rent.status) {
                    FeeStatus.paid => Icons.check_circle_rounded,
                    FeeStatus.partial => Icons.timelapse_rounded,
                    FeeStatus.unpaid => Icons.error_outline_rounded,
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(owes ? 'still to pay' : 'paid in full', style: t.textTheme.bodyMedium),
          if (rent.amountDue > 0) ...[
            const SizedBox(height: Space.sm),
            // No semantic label: [GlassCard] already speaks this whole card as one sentence
            // (see [_spoken]), and a bar that repeated it would say the rent twice. A
            // determinate LinearProgressIndicator announces nothing of its own unless it is
            // given a `semanticsValue`, which would be a percentage the ledger never stated.
            Meter(fraction: _collected(rent), tone: tone),
          ],
          const SizedBox(height: Space.sm),
          Divider(color: t.colorScheme.outlineVariant),
          const SizedBox(height: Space.xs),
          _Line(label: 'Rent for the month', value: rupees(rent.amountDue)),
          _Line(label: 'Received so far', value: rupees(rent.amountPaid)),
          // BOTH NUMBERS, NEVER THEIR SUM. A partial refund is only legible with two figures
          // on screen — what is credited to the month, and what came back — and this app is not
          // allowed to add them together (see the no-arithmetic rule at the top of this file).
          // The gross a resident originally handed over is not a column, so it is not printed.
          //
          // ONE LINE PER REFUND, for the same reason: two refunds are two facts, and their
          // total is a figure the database never computed. Only settled ones are money that has
          // moved — a pending refund has its own sentence below and no money line, because
          // there is no money to line up yet.
          for (final r in refunds.where((r) => r.isSettled))
            _Line(label: 'Refunded to you', value: rupees(r.amount)),
          if (rent.paidOn != null)
            _Line(
              label: 'Last payment',
              value: '${dayLabel(rent.paidOn!)}'
                  '${rent.mode == null ? '' : ' · ${rent.mode!.label}'}',
            ),
          // The receipt for THIS month, and only for this month. A card headed "September"
          // that could open August's document would be worse than one that opens nothing.
          if (payment != null && payment!.periodMonth == periodMonth)
            _ReceiptAction(
              payment: payment!,
              payerName: payerName,
              refunds: refunds,
            ),
          // ═══ THE REASON THE FIGURE ABOVE MOVED ═══
          //
          // This is the whole point of the feature. A resident who paid in full and later sees
          // "PARTLY PAID" with no explanation has been told, by an app they trust with their
          // rent, that their money went missing. The two money lines above state the fact; this
          // states the CAUSE, and it is placed before the pay-at-desk note so the explanation
          // is read before the instruction.
          if (refunds.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            RefundNote(refunds: refunds, outstanding: owes ? rent.balance : null),
          ],
          if (owes) ...[
            const SizedBox(height: Space.md),
            // ═══ WHERE THE CREAM "PAY ₹8,500" BUTTON USED TO BE ═══
            //
            // Rent is handed over at the warden's desk. There is no checkout in this build: the
            // razorpay-order / razorpay-webhook Edge Functions are deployed but not configured,
            // so the button opened a flow that could not take money, and the honest version of
            // that flow is a sentence.
            //
            // IT IS NOT DRAWN AS AN ERROR, and that is the whole design of it. Nothing has gone
            // wrong for this resident — the hostel takes rent at the desk, which is how nearly
            // every PG in the country already works. So: no red, no warning glyph, no "unable
            // to". A quiet well inside the card, the figure repeated as the amount to hand
            // over, and the person to hand it to when the app knows who that is.
            //
            // The cream fill does not move somewhere else on this screen. It is the app's only
            // one and it means "the action" — and paying rent IS the action on this card, so it
            // is spent here, on the button, and not on the paragraph below it.
            PayRentButton(amount: rent.balance),
            const SizedBox(height: Space.sm),
            PayAtDeskNote(amount: rent.balance),
          ],
        ],
      ),
    );
  }

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
        .map((r) => r.isSettled
            ? ' ${rupees(r.amount)} was refunded to you.'
            : ' A refund of ${rupees(r.amount)} is on its way to you.')
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
class _ReceiptAction extends ConsumerWidget {
  const _ReceiptAction({required this.payment, this.payerName, this.refunds = const []});

  final FeePayment payment;
  final String? payerName;
  final List<RefundInfo> refunds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt =
        residentReceipt(ref, payment, payerName: payerName, refunds: refunds);
    if (receipt == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: OutlinedButton.icon(
        onPressed: () => showReceipt(context, receipt),
        icon: const Icon(Icons.receipt_long_rounded, size: IconSize.md),
        // Not "Download" and not "Pay": this opens the document, and the sharing and saving
        // live on the receipt screen where the paper the resident is sending is on screen.
        label: const Text('View receipt'),
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

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        // A well INSIDE the rent card, not a second card on top of it: the surface ramp is
        // three flat colours and stacking panes exhausts it (see shared/glass/glass.dart).
        color: t.colorScheme.surfaceContainer,
        borderRadius: Radii.rControl,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(
                icon: Icons.storefront_rounded,
                // Muted, deliberately. The fee tone belongs to the figure above; a coloured
                // glyph here would read as a second status.
                tone: NivoraColors.textMuted,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Or pay cash at the desk', style: t.textTheme.titleSmall),
                    const SizedBox(height: Space.xxs),
                    Text(
                      'Hand ${rupees(amount)} to '
                      '${warden == null || warden.isEmpty ? 'your warden' : warden} '
                      'at the office.',
                      style: t.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            phone == null || phone.isEmpty
                ? 'It appears here as soon as your warden records it.'
                : 'It appears here as soon as your warden records it. Desk: $phone',
            style: t.textTheme.bodySmall,
          ),
        ],
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
///   error   (#C05353) is 'unpaid'. Drawing a refund in it says the resident is in arrears
///           because money was returned to them, which is the accusation this whole feature
///           exists to prevent.
///   warning (#976F23) is 'due / still owing / expiring' — tokens.dart's own list. A refunded
///           month would then look exactly like a month that needs chasing.
///   success (#42825F) is 'paid'. Money leaving the hostel is not a collection.
///
/// So: [NivoraColors.info], the app's factual tone — the blue already used for the empty-state
/// badge, i.e. "here is something you should know". It is a canonical token with measured
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

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        // A well INSIDE the rent card, exactly like [PayAtDeskNote] — the surface ramp is three
        // flat colours and stacking a second card on top of the first exhausts it.
        color: t.colorScheme.surfaceContainer,
        borderRadius: Radii.rControl,
        border: Border.all(
          color: context.tones.chipBorder(NivoraColors.info),
          width: Strokes.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toned, unlike the storefront glyph on [PayAtDeskNote]. That note carries no status
          // of its own; this one IS the status, and it is the only thing on the card wearing
          // this colour.
          const IconTile(
            icon: Icons.assignment_return_rounded,
            tone: NivoraColors.info,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One headline per refund. Two refunds in a month is rare and their sum is a
                // figure no column holds, so they are stated rather than added.
                for (final r in refunds) ...[
                  Text(
                    _headline(r),
                    style: t.textTheme.titleSmall
                        ?.copyWith(color: context.tones.resolve(NivoraColors.info)),
                  ),
                  const SizedBox(height: Space.xxs),
                ],
                Text(
                  _explanation(settled.isNotEmpty, owed),
                  style: t.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
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
      return on == null
          ? '$amount refund on its way'
          : '$amount refund requested ${dayLabel(on)}';
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
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      // BOTH HALVES FLEX, which is what stops this row from breaking. The value used to be a
      // plain Text, so the Row measured it unbounded: at 320dp and 1.3x, "16 Aug 2026 · UPI"
      // asked for 309 of the card's 256 points, the label was left with none, and it wrapped to
      // one character per line — a 286-point-tall row where a 24-point one belonged. The same
      // 6:5 split [DetailRow] already uses, so a labelled value behaves the same way everywhere
      // in this app.
      child: Row(
        children: [
          Expanded(flex: 6, child: Text(label, style: t.textTheme.bodyMedium)),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 5,
            child: Text(value, style: t.textTheme.titleSmall, textAlign: TextAlign.end),
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
  const FeePaymentTile({
    super.key,
    required this.payment,
    this.payerName,
    this.refunds = const [],
  });

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
    final receipt =
        residentReceipt(ref, payment, payerName: payerName, refunds: refunds);
    return OutlineCard(
      onTap: receipt == null ? null : () => showReceipt(context, receipt),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(monthLabel(payment.periodMonth), style: t.textTheme.titleMedium),
              ),
              StatusPill(label: payment.status.label, tone: tone),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(child: _Cell(label: 'Due', value: rupees(payment.amountDue))),
              Expanded(child: _Cell(label: 'Paid', value: rupees(payment.amountPaid))),
              Expanded(
                child: _Cell(
                  label: 'Pending',
                  value: rupees(payment.balance),
                  tone: payment.balance > 0 ? tone : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            payment.paidOn == null
                // A row with no paid_on exists only where a month was opened without a
                // payment. Say that, rather than printing a date that is not there.
                ? 'No payment date recorded'
                : 'Received ${dayLabel(payment.paidOn!)}'
                    '${payment.mode == null ? '' : ' · ${payment.mode!.label}'}',
            style: t.textTheme.bodySmall,
          ),
          // The three cells above are Due / Paid / Pending and a fourth would not survive 320dp
          // at 1.3x text, so each refund gets a line of its own rather than a column. It is the
          // only coloured thing on this row, which is what makes it findable when a resident is
          // scrolling two years of months looking for the one that changed.
          for (final r in refunds) ...[
            const SizedBox(height: Space.xxs),
            Row(
              children: [
                Icon(Icons.assignment_return_rounded,
                    size: IconSize.sm, color: context.tones.info),
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
            const SizedBox(height: Space.xxs),
            Text(payment.notes!.trim(), style: t.textTheme.bodySmall),
          ],
          // Said out loud rather than left to be discovered by tapping. A whole card that
          // happens to be tappable looks exactly like one that is not.
          if (receipt != null) ...[
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: IconSize.sm, color: context.tones.muted),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Text('View receipt', style: t.textTheme.labelLarge),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: IconSize.md, color: context.tones.muted),
              ],
            ),
          ],
        ],
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
    // Canonical in, resolved at the paint site: this is 14px type, and the canonical reds and
    // ambers are only rated as graphics.
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: t.textTheme.labelSmall),
        const SizedBox(height: Space.xxs),
        Text(
          value,
          style: t.textTheme.titleSmall?.copyWith(color: accent),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
  const RoomBedCard({super.key, required this.roomNumber, required this.bedNumber, this.roommates});

  final String? roomNumber;
  final int? bedNumber;

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
    if (roomNumber == null) {
      return RaisedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader(
              label: 'Your room',
              trailing: IconTile(icon: Icons.bed_rounded, tone: NivoraColors.textMuted),
            ),
            const SizedBox(height: Space.xs),
            Text('Not assigned yet', style: t.textTheme.titleMedium),
            const SizedBox(height: Space.xxs),
            Text('Your warden will place you in a room and bed.',
                style: t.textTheme.bodySmall),
          ],
        ),
      );
    }

    // The mockups' room card: eyebrow and a bed tile on the top line, the room itself as the
    // card's figure, and who else is in it underneath.
    //
    // ONE Text FOR ROOM AND BED, and it stays one. The mockup splits them across two lines with
    // a bed TYPE on the second ("Bed B · Standard Ac") — `public.beds` has `bed_number int` and
    // no type column at all, so the second line would have had to be invented.
    //
    // A RAISED CARD, ONE RUNG ABOVE THE RENT CARD ABOVE IT. tokens.dart lists what the design
    // puts on `surface raised` #171A1E and "the room card" is on that list by name, while "the
    // rent card" is on the #111417 list. The pair used to be the same fill, which flattened the
    // screen's only piece of hierarchy that is not typographic.
    return RaisedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            label: 'Your room',
            trailing: IconTile(icon: Icons.bed_rounded),
          ),
          const SizedBox(height: Space.xs),
          Text(
            bedNumber == null ? 'Room $roomNumber' : 'Room $roomNumber · Bed $bedNumber',
            style: t.textTheme.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          ?_sharing(context),
        ],
      ),
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
  Widget? _sharing(BuildContext context) {
    final mates = roommates;
    if (mates == null) return null;
    final t = Theme.of(context);

    final Widget line;
    if (mates.hasError) {
      line = Text(
        errorGuidance(mates.error!).canRetry
            ? 'Could not check who else is in this room. Pull down to try again.'
            : 'Who else is in this room is not available to you.',
        style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
      );
    } else if (mates.hasValue) {
      final people = mates.requireValue;
      final sentence = Text(
        people.isEmpty
            ? 'You have the room to yourself'
            : 'Sharing with ${countLabel(people.length, 'other resident')}',
        style: t.textTheme.bodySmall,
      );
      // The mockups' overlapping discs. The initials are the roommates' own, from the read this
      // sentence is already counting — `st_my_roommates()` returns name, phone and bed and
      // that is the entire set a resident may see, so a disc is the most of a person that can
      // honestly appear here. No cluster for an empty room: there is nobody to draw.
      line = people.isEmpty
          ? sentence
          : Row(
              children: [
                AvatarCluster(
                  names: [for (final mate in people) mate.fullName],
                  // This card is raised now, so the cut-out ring has to be the raised fill.
                  ring: raisedSurfaceOf(context),
                ),
                const SizedBox(width: Space.xs),
                Expanded(child: sentence),
              ],
            );
    } else {
      line = const Skeleton(widthFactor: 0.6);
    }

    return Padding(padding: const EdgeInsets.only(top: Space.sm), child: line);
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
