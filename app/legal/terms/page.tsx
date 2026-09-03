import type { Metadata } from "next";
import { LEGAL, LEGAL_VERSION, isConfigured } from "@/lib/legal-config";
import Link from "next/link";
import { Callout, DataTable, DocBody, DocHeader, Section, TableOfContents } from "../layout";

/* ────────────────────────────────────────────────────────────────────────────
 * The operator's real-world facts live in lib/legal-config.ts and are mirrored
 * in nivora_app/lib/features/legal/legal_documents.dart — change both, in the
 * same commit. While any value there is still an unresolvable `.invalid`
 * placeholder this page renders a visible notice at the top, which disappears
 * on its own once real values are set.
 *
 * THE CONTACT IS A ROLE, NOT A PERSON. The mailbox is monitored and the address
 * is a locality; neither names an individual, and neither should. See the note
 * on `grievanceOfficer` in lib/legal-config.ts.
 * ──────────────────────────────────────────────────────────────────────────── */
const OPERATOR = {
  legalName: LEGAL.operatorName,
  email: LEGAL.legalEmail,
  postalAddress: LEGAL.postalAddress,
  governingLaw: LEGAL.governingLaw,
  jurisdiction: LEGAL.jurisdiction,
} as const;

const PLACEHOLDERS_UNSET = !isConfigured;

// The publication date of the Terms + Privacy pair, and the string an in-app acceptance is
// recorded against. It lives in lib/legal-config.ts so that this page, its three siblings, the
// Android app and public.legal_versions cannot drift apart — see the note on LEGAL_VERSION
// there, which explains why bumping it re-asks every user for their agreement.
const UPDATED = LEGAL_VERSION;

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

export const metadata: Metadata = {
  title: "Terms of Use",
  description:
    "The terms on which NIVORA is provided to hostel and PG operators and to the staff and residents whose accounts they issue — including acceptable use, what happens when a subscription lapses, and limitation of liability.",
};

/** Rendered per-request so middleware's CSP nonce reaches the script tags — see
 *  the note in `app/legal/privacy/page.tsx`. The page itself reads no session,
 *  no cookies and no data, so it remains statically renderable. */
export const dynamic = "force-dynamic";

/**
 * EIGHT SECTIONS, and they are the same eight the Android app shows — see
 * nivora_app/lib/features/legal/legal_documents.dart, which carries this text so the consent
 * gate can draw it without a network call. An earlier version of this page ran to eighteen
 * sections; the cut was made by merging and by deleting repetition, never by softening a claim.
 */
const SECTIONS = [
  { id: "parties", title: "Who these terms bind" },
  { id: "service", title: "What the service does" },
  { id: "accounts", title: "Your account" },
  { id: "acceptable-use", title: "Acceptable use" },
  { id: "resident-data", title: "Resident data, and what the hostel is responsible for" },
  { id: "payments", title: "Subscription and payments" },
  { id: "availability", title: "Availability, suspension and liability" },
  { id: "contact", title: "Changes, governing law and contact" },
] as const;

export default function TermsOfUsePage() {
  return (
    <>
      <DocHeader
        title="Terms of Use"
        summary={
          "The terms on which " +
          APP_NAME +
          " is provided — to the hostel or PG operator that subscribes to it, and to the owners, managers, wardens and residents whose accounts that operator issues."
        }
        updated={UPDATED}
      />

      {PLACEHOLDERS_UNSET ? (
        <Callout tone="sand" title="This document is not ready to publish">
          <p>
            The operator&rsquo;s legal name, contact address and postal address have not been set
            yet, so this document does not yet identify who is responsible for your data. Please do
            not rely on it. If you need to reach someone about your personal data in the meantime,
            contact the hostel that issued your account directly.
          </p>
        </Callout>
      ) : null}

      <div className="mt-6">
        <TableOfContents items={SECTIONS} />
      </div>

      <DocBody>
        <Callout title="The short version">
          <ul>
            <li>
              Your hostel subscribes to {APP_NAME} and issues you an account. There is no public
              sign-up and no self-service account.
            </li>
            <li>
              If a hostel&rsquo;s subscription lapses, the workspace becomes{" "}
              <strong>read-only</strong> — everyone can still sign in and read everything. Nothing
              is deleted.
            </li>
            <li>
              {APP_NAME} records payments. It never takes, holds or moves money, and never sees a
              card number, UPI ID or bank account.
            </li>
            <li>
              How personal data is handled is set out separately in the{" "}
              <Link href="/legal/privacy">Privacy Policy</Link>.
            </li>
          </ul>
        </Callout>

        <Section id="parties" title="1. Who these terms bind">
          <p>
            These terms are an agreement between <strong>{OPERATOR.legalName}</strong> (&ldquo;we&rdquo;,
            &ldquo;us&rdquo;), which provides this service, and you — whether you are the{" "}
            <strong>hostel or PG operator</strong> that subscribes to {APP_NAME}, or an owner,
            manager, warden or resident given an account by that operator.
          </p>
          <p>
            Using the app means accepting them. If you do not accept them you cannot use the app,
            and you can sign out from the same screen that asks. Where a term applies only to the
            operator it says so.
          </p>
        </Section>

        <Section id="service" title="2. What the service does">
          <p>
            {APP_NAME} records and organises the running of a hostel or PG: floors, rooms and beds
            and which are occupied; resident records, admission and check-out; a monthly fee ledger;
            complaints with their status history; leave requests; a visitor log; notices, staff
            tasks and mess menus; and expense and revenue records. It is delivered as a website and
            an Android app, and needs an internet connection.
          </p>
          <p>
            It is a record-keeping tool. It is <strong>not</strong> an accounting package, not a
            legal or tax adviser, and not a substitute for the agreement between a resident and
            their hostel. The rent, the deposit, the notice period and the house rules are matters
            between those two; {APP_NAME} only records what they tell it.
          </p>
        </Section>

        <Section id="accounts" title="3. Your account">
          <p>
            There is <strong>no public sign-up</strong>. The platform administrator creates the
            Owner account for a hostel, the Owner creates Manager and Warden accounts, and a Warden
            registers residents — who sign in with the phone number the hostel registered. Every
            account comes with a temporary password that must be changed at first sign-in.
          </p>
          <p>
            An account belongs to the hostel&rsquo;s workspace rather than to you personally, and is
            deactivated on check-out or when employment ends. The operator is responsible for
            issuing accounts only to people entitled to them and for deactivating them promptly.
          </p>
          <ul>
            <li>
              Keep your password to yourself. Anything done with your account is treated as done by
              you, because that is how the security log records it.
            </li>
            <li>
              Turn on two-factor authentication where it is offered. Where it is required for your
              role you will be asked to set it up before you can continue.
            </li>
            <li>Tell your hostel immediately if you think someone else has your password.</li>
            <li>
              Do not use somebody else&rsquo;s account, and do not ask a member of staff to act as
              you.
            </li>
          </ul>
        </Section>

        <Section id="acceptable-use" title="4. Acceptable use">
          <p>You must not:</p>
          <ul>
            <li>
              enter information you know to be false — a payment that did not happen, an invented
              complaint against another resident, or someone else&rsquo;s identity document;
            </li>
            <li>
              try to reach data belonging to another hostel or another person, or probe the service
              for a way to do so. Authentication attempts are rate-limited and unusual activity
              raises an alert; deliberately tripping either is itself a breach of these terms;
            </li>
            <li>
              upload malicious code, anything unlawful, or a photograph of a person taken without
              their knowledge;
            </li>
            <li>
              use the visitor log, complaints or any other feature to harass a resident, a member of
              staff or a visitor;
            </li>
            <li>
              copy, resell, sublicense or reverse-engineer the software, or extract data from it in
              bulk by automated means rather than through the export features — except where the law
              says you may despite this clause.
            </li>
          </ul>
          <p>
            Complaints are read by staff, and notices by every resident they are posted to. Write
            them accordingly. The software, its design and its documentation remain ours; you get a
            non-exclusive, non-transferable right to use the service for the term of the
            subscription, for running the hostel it was issued for.
          </p>
        </Section>

        <Section id="resident-data" title="5. Resident data, and what the hostel is responsible for">
          <p>
            The operator decides what personal data to collect about its residents and why. Under
            India&rsquo;s Digital Personal Data Protection Act, 2023 that makes the{" "}
            <strong>operator the Data Fiduciary</strong> and{" "}
            <strong>{APP_NAME} the Data Processor</strong>. The operator is responsible for:
          </p>
          <ul>
            <li>
              giving residents notice and obtaining their consent before entering their details,
              including a <strong>parent or guardian&rsquo;s consent</strong> where a resident is
              under 18 — the system holds no date of birth and cannot tell;
            </li>
            <li>
              displaying a visible notice at the visitor desk, since a visitor whose name and phone
              number is logged has no account and gets no notice from the app;
            </li>
            <li>
              collecting only what it needs, and preferring a non-Aadhaar identity document;
            </li>
            <li>
              answering residents&rsquo; requests to see, correct or erase their data, and applying
              the periods in the <Link href="/legal/privacy">Privacy Policy</Link>;
            </li>
            <li>removing accounts for staff who leave.</li>
          </ul>
          <p>
            What you enter stays yours. You grant us only the permission needed to store it, show it
            to the people entitled to see it, and back it up. It is never sold, never shared with an
            advertiser and never used to train AI models. {APP_NAME} processes resident data only on
            the operator&rsquo;s instructions — so an operator that records data it had no lawful
            basis to hold, or fails to give the notices above, answers for that itself and
            indemnifies us against claims arising from it.
          </p>
        </Section>

        <Section id="payments" title="6. Subscription and payments">
          <p>
            Each hostel workspace runs on a subscription with an end date, enforced by the database
            itself rather than by the interface, so it behaves the same way everywhere in the
            product:
          </p>
          <DataTable
            head={["State", "What happens"]}
            rows={[
              ["Active", "Everything works normally."],
              [
                "Expiring (15 days or fewer remaining)",
                "Everything still works. The workspace shows a renewal warning so the lapse is not a surprise.",
              ],
              [
                "Expired, or the hostel deactivated by the platform administrator",
                "The workspace becomes read-only. Everyone can still sign in and read everything. Any attempt to create or change a record is refused by the database with an explanatory message. Nothing is deleted, and renewing restores writing immediately.",
              ],
            ]}
          />
          <p>
            Rent reaches the hostel one of two ways, and {APP_NAME} is not holding it in either. A
            warden records a payment already made in cash, by UPI or by bank transfer; or, if the
            resident chooses, the payment is taken by <strong>Razorpay</strong> in
            Razorpay&rsquo;s own checkout under Razorpay&rsquo;s terms. {APP_NAME} passes it the
            payer&rsquo;s name, email, phone and the amount, and receives back only a confirmation
            and the transaction identifiers. In neither case does {APP_NAME}{" "}
            <strong>take, hold, transfer or refund money</strong>, and in neither case does it store
            a card number, a bank account number, a UPI ID or a CVV.
          </p>
          <p>
            A receipt reflects what a member of staff recorded or what the gateway confirmed; it is
            not independent confirmation that money changed hands. If a receipt is wrong, the hostel
            corrects it. Rent, deposits, refunds and any dispute about them are between the resident
            and the hostel. Subscription fees and renewal terms are agreed separately with the
            operator and are not set by this page.
          </p>
        </Section>

        <Section id="availability" title="7. Availability, suspension and liability">
          <p>
            The service is provided <strong>as it is</strong>, without a guaranteed uptime figure or
            recovery time. It may be unavailable during maintenance, during a failure at a hosting
            provider, or for reasons outside our control. An encrypted backup of the database is
            taken nightly and kept for 90 days; backups exist to recover the platform from a
            failure, not to replace records the operator is required to keep. To the fullest extent
            permitted by law we exclude implied warranties, including of merchantability, fitness
            for a particular purpose and non-infringement, and we do not warrant that the records
            the system holds are accurate — they are entered by the operator&rsquo;s staff. Keep
            your own copy of anything you cannot afford to lose.
          </p>
          <p>
            We may suspend or restrict access — to an individual account or to a whole workspace —
            for a breach of section 4, for non-payment of a subscription, after a security incident,
            or where leaving it open would put other people&rsquo;s data at risk. Where it is
            practicable and lawful we tell the operator first, and we restore access as soon as the
            reason is resolved. An operator may stop using the service at any time and may request
            an export of its workspace data first. A resident&rsquo;s account is normally closed by
            their hostel when they leave.
          </p>
          <p>
            To the fullest extent permitted by law, neither party is liable to the other for
            indirect, incidental, special or consequential loss, for lost profits, revenue or
            goodwill, or for loss arising from information a user entered incorrectly. Our total
            aggregate liability is limited to the{" "}
            <strong>
              subscription fees paid by the operator for the twelve months before the event giving
              rise to the claim
            </strong>
            , or a nominal amount where no fees have been paid. Nothing here excludes liability that
            cannot lawfully be excluded, including for fraud, for death or personal injury caused by
            negligence, or under applicable data protection law.
          </p>
        </Section>

        <Section id="contact" title="8. Changes, governing law and contact">
          <p>
            We may change these terms; the date at the top of this page changes when we do. Both
            documents carry a version, currently <strong>{UPDATED}</strong>, and{" "}
            <strong>individual account holders are asked directly</strong>: these terms and the{" "}
            <Link href="/legal/privacy">Privacy Policy</Link> are presented together in the app
            before it can be used, and the fact that you accepted them — which version, and when —
            is recorded. When either changes materially the version changes with it and you are
            asked to read and accept again on your next visit, so nobody is silently moved onto
            terms they have not seen. Declining is a real option: the app cannot be used without
            accepting, and the same screen offers to sign you out. If any provision is held
            unenforceable, the rest continues in force.
          </p>
          <p>
            These terms are governed by <strong>{OPERATOR.governingLaw}</strong>, and the parties
            submit to the exclusive jurisdiction of <strong>{OPERATOR.jurisdiction}</strong>, except
            that either party may seek injunctive relief in any court of competent jurisdiction.
          </p>
          <div className="rounded-card border border-line bg-white/60 p-5 text-sm leading-7">
            <p className="text-navy">
              <strong>{OPERATOR.legalName}</strong>
            </p>
            <p>
              <a
                href={"mailto:" + OPERATOR.email}
                className="text-teal underline underline-offset-2"
              >
                {OPERATOR.email}
              </a>
            </p>
            <p className="whitespace-pre-line">{OPERATOR.postalAddress}</p>
          </div>
          <p>
            See also the <Link href="/legal/privacy">Privacy Policy</Link> and{" "}
            <Link href="/legal/account-deletion">Delete your account and data</Link>.
          </p>
        </Section>
      </DocBody>
    </>
  );
}
