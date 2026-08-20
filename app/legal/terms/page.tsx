import type { Metadata } from "next";
import Link from "next/link";
import { Callout, DataTable, DocBody, DocHeader, Section, TableOfContents } from "../layout";

/* ────────────────────────────────────────────────────────────────────────────
 * PLACEHOLDERS — the hostel operator fills these in once, here, before these
 * terms are published or relied upon.
 *
 * Every value below is deliberately a non-resolvable placeholder (the .invalid
 * top-level domain can never be registered). Nothing else in this file needs
 * editing. While a placeholder is still in place the page renders a visible
 * notice at the top; that notice disappears on its own once real values are set.
 * ──────────────────────────────────────────────────────────────────────────── */
const OPERATOR = {
  /** Legal name of the entity that provides this HostelPro deployment. */
  legalName: "[OPERATOR LEGAL NAME — NOT YET SET]",
  /** Inbox for contractual and support correspondence. */
  email: "legal@placeholder.invalid",
  /** Postal address at which legal notice can be served. */
  postalAddress: "[POSTAL ADDRESS — NOT YET SET]",
  /** Governing law, e.g. "the laws of India". */
  governingLaw: "[GOVERNING LAW — NOT YET SET]",
  /** Courts with exclusive jurisdiction, e.g. "the courts at Pune, Maharashtra". */
  jurisdiction: "[COURTS OF EXCLUSIVE JURISDICTION — NOT YET SET]",
} as const;

const PLACEHOLDERS_UNSET = Object.values(OPERATOR).some(
  (v) => v.startsWith("[") || v.endsWith(".invalid"),
);

const UPDATED = "2026-08-21";

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "HostelPro";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "The terms on which HostelPro is provided to hostel and PG operators and to the staff and residents whose accounts they issue — including acceptable use, what happens when a subscription lapses, and limitation of liability.",
};

/** Rendered per-request so middleware's CSP nonce reaches the script tags — see
 *  the note in `app/legal/privacy/page.tsx`. The page itself reads no session,
 *  no cookies and no data, so it remains statically renderable. */
export const dynamic = "force-dynamic";

const SECTIONS = [
  { id: "parties", title: "Who these terms bind" },
  { id: "service", title: "What the service does" },
  { id: "accounts", title: "Accounts are issued, not registered" },
  { id: "credentials", title: "Looking after your credentials" },
  { id: "acceptable-use", title: "Acceptable use" },
  { id: "resident-data", title: "Resident data and the operator's duties" },
  { id: "content", title: "Content you put into the service" },
  { id: "subscription", title: "Subscription, and read-only mode" },
  { id: "payments", title: "Payments are recorded, not processed" },
  { id: "availability", title: "Availability, backups and support" },
  { id: "suspension", title: "Suspension and termination" },
  { id: "ip", title: "Intellectual property" },
  { id: "warranty", title: "Disclaimer of warranties" },
  { id: "liability", title: "Limitation of liability" },
  { id: "indemnity", title: "Indemnity" },
  { id: "changes", title: "Changes to these terms" },
  { id: "law", title: "Governing law and jurisdiction" },
  { id: "contact", title: "Contact" },
] as const;

export default function TermsOfServicePage() {
  return (
    <>
      <DocHeader
        title="Terms of Service"
        summary={
          "The terms on which " +
          APP_NAME +
          " is provided — to the hostel or PG operator that subscribes to it, and to the owners, managers, wardens and residents whose accounts that operator issues."
        }
        updated={UPDATED}
      />

      {PLACEHOLDERS_UNSET ? (
        <Callout tone="sand" title="Before publishing this page">
          <p>
            The operator name, contact details, governing law and jurisdiction in these terms are
            still placeholders. Set them in the <code>OPERATOR</code> constant at the top of{" "}
            <code>app/legal/terms/page.tsx</code>. This notice removes itself once they are real.
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
              {APP_NAME} records payments that happened elsewhere. It never takes, holds or moves
              money.
            </li>
            <li>
              How personal data is handled is set out separately in the{" "}
              <Link href="/legal/privacy">Privacy Policy</Link>.
            </li>
          </ul>
        </Callout>

        <Section id="parties" title="1. Who these terms bind">
          <p>
            These terms are an agreement between <strong>{OPERATOR.legalName}</strong> (
            &ldquo;we&rdquo;, &ldquo;us&rdquo;, the provider of {APP_NAME}) and:
          </p>
          <ul>
            <li>
              the <strong>hostel or PG operator</strong> that subscribes to {APP_NAME} for its
              property — referred to here as the <strong>Operator</strong>; and
            </li>
            <li>
              every <strong>individual user</strong> who signs in with an account the Operator
              issued — an owner, manager, warden or resident.
            </li>
          </ul>
          <p>
            By signing in you accept these terms. If you do not accept them, do not sign in, and
            speak to your hostel. Where a term applies only to the Operator it says so.
          </p>
        </Section>

        <Section id="service" title="2. What the service does">
          <p>
            {APP_NAME} is multi-tenant software for running a hostel or paying-guest property. Each
            Operator gets an isolated workspace containing:
          </p>
          <ul>
            <li>floors, rooms and beds, and which of them are occupied;</li>
            <li>resident records, admission and check-out;</li>
            <li>a monthly fee ledger recording payments the Operator has already received;</li>
            <li>complaints, with a status history;</li>
            <li>leave requests and approvals;</li>
            <li>a visitor log;</li>
            <li>announcements, staff tasks and mess menus;</li>
            <li>expense and revenue records with receipt attachments; and</li>
            <li>dashboards summarising the above.</li>
          </ul>
          <p>
            The service is delivered over the web and through an Android application that is a
            wrapper around the same website. There is no separate offline product; an internet
            connection is required.
          </p>
        </Section>

        <Section id="accounts" title="3. Accounts are issued, not registered">
          <p>
            {APP_NAME} has <strong>no public sign-up</strong>. Accounts are created in a chain:
          </p>
          <ol>
            <li>the platform administrator creates the Owner account for a hostel;</li>
            <li>the Owner creates Manager and Warden accounts for that hostel;</li>
            <li>the Warden registers residents.</li>
          </ol>
          <p>
            Residents sign in with the <strong>phone number</strong> the hostel registered. Everyone
            is required to set a new password the first time they sign in.
          </p>
          <p>
            Because accounts are issued rather than self-created, the Operator is responsible for
            issuing them only to people entitled to them, for choosing the right role for each
            person, and for deactivating accounts promptly when someone leaves. An account belongs
            to the hostel workspace, not to the individual; it is deactivated on check-out or when
            employment ends.
          </p>
        </Section>

        <Section id="credentials" title="4. Looking after your credentials">
          <ul>
            <li>
              Keep your password to yourself. Do not share an account, and do not let someone else
              use yours — every action is logged against the account that performed it, and it will
              be attributed to you.
            </li>
            <li>
              Where two-factor authentication is offered, turn it on. Where the Operator has made it
              mandatory for your role, you will be required to enrol before you can continue.
            </li>
            <li>
              Tell your hostel immediately if you think someone else has access to your account.
            </li>
          </ul>
        </Section>

        <Section id="acceptable-use" title="5. Acceptable use">
          <p>You must not:</p>
          <ul>
            <li>
              attempt to reach data belonging to another hostel, another resident or another role,
              whether by manipulating a request, a link, an identifier or in any other way;
            </li>
            <li>
              probe, scan or test the security of the service, or interfere with its normal
              operation, without our prior written permission;
            </li>
            <li>
              scrape, bulk-export or systematically copy data from the service other than through
              the export features provided;
            </li>
            <li>
              upload malicious code, or content that is unlawful, defamatory, obscene or infringes
              someone else&rsquo;s rights;
            </li>
            <li>
              upload an identity document belonging to a person who has not consented to it being
              stored;
            </li>
            <li>
              use the visitor log, complaint records or any other feature to monitor or harass a
              resident, a member of staff or a visitor beyond the legitimate safety and
              administrative purposes those features exist for;
            </li>
            <li>
              resell, sublicense or provide the service to a third party as though it were your own;
              or
            </li>
            <li>
              use the service in breach of any law that applies to you, including data protection
              law.
            </li>
          </ul>
          <p>
            Automated protections rate-limit authentication attempts and raise security alerts on
            unusual activity. Deliberately triggering them is itself a breach of these terms.
          </p>
        </Section>

        <Section id="resident-data" title="6. Resident data and the Operator's duties">
          <p>
            The Operator decides what personal data to collect about its residents and why. Under
            India&rsquo;s Digital Personal Data Protection Act, 2023 that makes the{" "}
            <strong>Operator the Data Fiduciary</strong> and{" "}
            <strong>{APP_NAME} the Data Processor</strong>. The Operator therefore undertakes to:
          </p>
          <ul>
            <li>
              give residents a privacy notice and obtain their consent before entering their details
              — including <strong>verifiable parental consent</strong> where a resident is under 18,
              which the system cannot determine on its own because it holds no date of birth;
            </li>
            <li>
              display a visible notice at the point where the visitor log is kept, telling visitors
              what is recorded and for how long;
            </li>
            <li>
              keep the data accurate, and correct it through the app when a resident asks;
            </li>
            <li>
              respond to residents&rsquo; access, correction and erasure requests, and apply the
              retention periods set out in the <Link href="/legal/privacy">Privacy Policy</Link>;
              and
            </li>
            <li>enter only data it is lawfully entitled to hold.</li>
          </ul>
          <p>
            {APP_NAME} processes resident data only on the Operator&rsquo;s instructions and for the
            purpose of providing the service. It is never used for advertising, sold, or used to
            train AI models.
          </p>
        </Section>

        <Section id="content" title="7. Content you put into the service">
          <p>
            You keep ownership of everything you enter or upload. You grant us the licence we need
            to host, store, back up, transmit and display it in order to run the service, and for no
            other purpose.
          </p>
          <p>
            You are responsible for the accuracy and lawfulness of what you enter. Free-text
            fields — complaint descriptions, leave reasons, payment notes — are visible to the staff
            roles entitled to the record, so do not write anything there you would not want those
            people to read.
          </p>
        </Section>

        <Section id="subscription" title="8. Subscription, and read-only mode">
          <p>
            Each hostel workspace runs on a subscription with an end date. This is enforced by the
            database itself rather than by the interface, so it behaves the same way everywhere in
            the product:
          </p>
          <DataTable
            head={["State", "What happens"]}
            rows={[
              [
                "Active",
                "Everything works normally.",
              ],
              [
                "Expiring (15 days or fewer remaining)",
                "Everything still works. The workspace shows a renewal warning so the lapse is not a surprise.",
              ],
              [
                "Expired (end date passed, or no subscription recorded)",
                "The workspace becomes read-only. Everyone can still sign in and read everything. Any attempt to create or change a record is refused by the database with an explanatory message.",
              ],
              [
                "Hostel deactivated by the platform administrator",
                "The same read-only behaviour applies.",
              ],
            ]}
          />
          <Callout tone="teal" title="What read-only does not mean">
            <ul>
              <li>
                <strong>Nothing is deleted.</strong> Every resident record, fee entry, complaint and
                document stays exactly where it was.
              </li>
              <li>
                <strong>Nobody is locked out.</strong> Owners, managers, wardens and residents can
                all still sign in and read their data, including for the period after a lapse.
              </li>
              <li>
                <strong>Renewing restores writing immediately.</strong> There is no re-import and no
                migration; the moment a current subscription end date is recorded, the workspace is
                writable again.
              </li>
            </ul>
          </Callout>
          <p>
            Platform administrators retain the ability to act on an expired workspace, so that
            service can be restored and so that a lapse never prevents an Operator from getting its
            own data back. Fees, billing cycle and renewal terms are agreed separately with the
            Operator and are not set by this page.
          </p>
        </Section>

        <Section id="payments" title="9. Payments are recorded, not processed">
          <p>
            {APP_NAME} is not a payment service. The fee ledger records payments that have already
            been made to the hostel somewhere else — in cash, by UPI or by bank transfer — together
            with the amount, the date and a label saying which of those three it was. The app{" "}
            <strong>never takes, holds, transfers or refunds money</strong>, and it stores no card
            number, bank account number or UPI handle.
          </p>
          <p>
            Rent, deposits, refunds and any dispute about them are entirely between the resident and
            the hostel. A receipt generated by {APP_NAME} reflects what a member of the
            hostel&rsquo;s staff recorded; it is not independent confirmation that money changed
            hands.
          </p>
        </Section>

        <Section id="availability" title="10. Availability, backups and support">
          <p>
            We work to keep the service available and take an encrypted backup of the database
            nightly, retained for 90 days. We do not, on these terms, offer a guaranteed uptime
            level or a guaranteed recovery time, and the service may be unavailable during
            maintenance, during a failure at a hosting provider, or for reasons outside our control.
          </p>
          <p>
            Backups exist to recover from a failure of the platform. They are not a substitute for
            the Operator keeping its own records of anything it is legally required to retain.
          </p>
        </Section>

        <Section id="suspension" title="11. Suspension and termination">
          <p>
            We may suspend or restrict access — to an individual account or to a whole workspace —
            where we reasonably believe it is necessary to protect the service or other users, for
            example on a serious breach of section 5, on a security incident, or where required by
            law. Where it is practicable and lawful, we tell the Operator first, and we restore
            access as soon as the reason for the suspension is resolved.
          </p>
          <p>
            An Operator may stop using the service at any time and may request an export of its
            workspace data before doing so. After termination, data is retained and then deleted in
            line with the periods in the <Link href="/legal/privacy">Privacy Policy</Link>. An
            individual user&rsquo;s access ends when the Operator deactivates their account, which
            is what happens on check-out or when employment ends.
          </p>
        </Section>

        <Section id="ip" title="12. Intellectual property">
          <p>
            {APP_NAME}, its software, design and documentation remain ours. Nothing in these terms
            transfers ownership of them. You get a non-exclusive, non-transferable right to use the
            service for the term of the subscription, for the purpose of running the hostel it was
            issued for.
          </p>
          <p>
            You must not copy, decompile or reverse-engineer the software except to the extent that
            applicable law says you may do so despite this clause, and you must not remove or
            obscure any notice of ownership.
          </p>
        </Section>

        <Section id="warranty" title="13. Disclaimer of warranties">
          <p>
            The service is provided <strong>&ldquo;as is&rdquo;</strong>. To the fullest extent
            permitted by law we exclude all implied warranties, including of merchantability,
            fitness for a particular purpose and non-infringement. We do not warrant that the
            service will be uninterrupted or error-free, or that the records it holds are accurate —
            those records are entered by the Operator&rsquo;s staff, and their accuracy is the
            Operator&rsquo;s responsibility.
          </p>
          <p>
            {APP_NAME} does not provide legal, tax or accounting advice. Retention periods,
            statutory record-keeping duties and consent requirements referred to in these documents
            are the Operator&rsquo;s own responsibility to verify with its advisers.
          </p>
        </Section>

        <Section id="liability" title="14. Limitation of liability">
          <p>
            To the fullest extent permitted by law, neither party is liable to the other for
            indirect, incidental, special, punitive or consequential loss, or for loss of profit,
            revenue, goodwill, business or anticipated savings, however caused.
          </p>
          <p>
            Our total aggregate liability arising out of or in connection with these terms — whether
            in contract, tort (including negligence), breach of statutory duty or otherwise — is
            limited to the <strong>subscription fees paid by the Operator for the twelve months
            immediately before the event giving rise to the claim</strong>. Where no fees have been
            paid, our aggregate liability is limited to a nominal amount.
          </p>
          <p>
            Nothing in these terms excludes or limits liability that cannot lawfully be excluded or
            limited, including liability for death or personal injury caused by negligence, for
            fraud or fraudulent misrepresentation, or under applicable data protection law.
          </p>
        </Section>

        <Section id="indemnity" title="15. Indemnity">
          <p>
            The Operator indemnifies us against claims, losses and reasonable costs arising from its
            own breach of section 5 or section 6 — in particular, from entering personal data it had
            no lawful basis to collect, or from failing to give residents, guardians and visitors
            the notices those sections require.
          </p>
        </Section>

        <Section id="changes" title="16. Changes to these terms">
          <p>
            We may change these terms. The date at the top of this page changes when we do. Material
            changes are notified to the Operator before they take effect, and continued use of the
            service after that date is acceptance of the revised terms. If the Operator does not
            accept a material change, it may terminate before the change takes effect.
          </p>
        </Section>

        <Section id="law" title="17. Governing law and jurisdiction">
          <p>
            These terms are governed by <strong>{OPERATOR.governingLaw}</strong>, without regard to
            its conflict-of-laws rules. The parties submit to the exclusive jurisdiction of{" "}
            <strong>{OPERATOR.jurisdiction}</strong>, except that either party may seek injunctive
            relief in any court of competent jurisdiction.
          </p>
          <p>
            If any provision of these terms is held unenforceable, the rest continues in force. A
            failure to enforce a provision is not a waiver of it.
          </p>
        </Section>

        <Section id="contact" title="18. Contact">
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
