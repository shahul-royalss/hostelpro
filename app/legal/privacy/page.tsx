import type { Metadata } from "next";
import { LEGAL, isConfigured } from "@/lib/legal-config";
import Link from "next/link";
import { Callout, DataTable, DocBody, DocHeader, Section, TableOfContents } from "../layout";

/* ────────────────────────────────────────────────────────────────────────────
 * PLACEHOLDERS — the hostel operator fills these in once, here, before the
 * policy is published or submitted to the Play Console.
 *
 * Every value below is deliberately a non-resolvable placeholder (the .invalid
 * top-level domain can never be registered). Nothing else in this file needs
 * editing. While a placeholder is still in place the page renders a visible
 * notice at the top; that notice disappears on its own once real values are set.
 * ──────────────────────────────────────────────────────────────────────────── */
const CONTACT = {
  operatorName: LEGAL.operatorName,
  email: LEGAL.grievanceEmail,
  postalAddress: LEGAL.postalAddress,
} as const;

const PLACEHOLDERS_UNSET = !isConfigured;

const UPDATED = "2026-08-21";

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How NIVORA collects, stores, shares, protects and deletes the personal data of hostel residents, guardians, visitors and staff — including your rights under India's DPDP Act 2023 and the GDPR.",
};

/**
 * This page holds no dynamic data — no session, no cookies, no database — so it
 * *is* statically renderable, and Next will happily prerender it if you delete
 * this line. It is rendered per-request anyway, and the reason is the CSP:
 * middleware issues a fresh script nonce on every response, and Next can only
 * stamp that nonce onto its script tags while rendering that same request.
 * Prerendered HTML carries no nonce, so `strict-dynamic` blocks all 50 script
 * tags and the page never hydrates. Verified both ways against `next start`.
 */
export const dynamic = "force-dynamic";

const SECTIONS = [
  { id: "who", title: "Who this policy is from" },
  { id: "accounts", title: "How accounts work here" },
  { id: "data", title: "What personal data is held" },
  { id: "not-collected", title: "What is never collected" },
  { id: "documents", title: "Photographs and ID documents" },
  { id: "why", title: "Why the data is held" },
  { id: "retention", title: "How long it is kept" },
  { id: "sharing", title: "Who can see it" },
  { id: "location", title: "Where it is stored" },
  { id: "security", title: "How it is protected" },
  { id: "backups", title: "Backups, and the limits of deletion" },
  { id: "children", title: "Children" },
  { id: "rights-dpdp", title: "Your rights (DPDP Act 2023)" },
  { id: "rights-gdpr", title: "Your rights (GDPR / UK GDPR)" },
  { id: "exercise", title: "How to exercise your rights" },
  { id: "breach", title: "If something goes wrong" },
  { id: "changes", title: "Changes to this policy" },
  { id: "contact", title: "Grievance Officer and contact" },
] as const;

export default function PrivacyPolicyPage() {
  return (
    <>
      <DocHeader
        title="Privacy Policy"
        summary={
          APP_NAME +
          " is hostel and PG management software. This policy explains exactly what personal data it holds about residents, their guardians, their visitors and hostel staff; why it is held; how long for; who else can reach it; and how to get a copy of it, correct it or have it erased."
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
              You did not create your account and you did not type your details in — hostel staff
              did. There is no public sign-up.
            </li>
            <li>
              Nothing here is sold, shared with advertisers or data brokers, or used to train AI
              models. There is no advertising, analytics or tracking code in the app at all.
            </li>
            <li>
              Photographs and ID-proof scans sit in private storage and are only ever reachable
              through a link that expires in 15 minutes.
            </li>
            <li>
              You can ask for a copy of your data, ask for it to be corrected, or ask for it to be
              deleted — see{" "}
              <Link href="/legal/account-deletion">Delete your account and data</Link>.
            </li>
          </ul>
        </Callout>

        <Section id="who" title="1. Who this policy is from">
          <p>
            {APP_NAME} is software licensed to hostel and PG operators. Your hostel decides which
            residents to admit, what to record about them and why; {APP_NAME} stores and processes
            that information on the hostel&rsquo;s instructions.
          </p>
          <p>
            Under India&rsquo;s <strong>Digital Personal Data Protection Act, 2023 (DPDP Act)</strong>{" "}
            this makes <strong>your hostel the Data Fiduciary</strong> for resident, guardian,
            visitor, fee, complaint and leave records, and{" "}
            <strong>{APP_NAME} the Data Processor</strong>. Your hostel is your first point of
            contact for anything about your own record — they hold it, and they are the ones who can
            correct it.
          </p>
          <p>
            For a small set of data {APP_NAME} decides on its own — platform staff accounts, the
            security audit trail and security alerts — {APP_NAME} is the Data Fiduciary.
          </p>
          <p>
            This deployment of {APP_NAME} is operated by{" "}
            <strong>{CONTACT.operatorName}</strong>, contactable at{" "}
            <a href={"mailto:" + CONTACT.email}>{CONTACT.email}</a>.
          </p>
        </Section>

        <Section id="accounts" title="2. How accounts work here">
          <p>
            This matters for privacy, because it changes who put your data into the system:
          </p>
          <ul>
            <li>
              <strong>Nobody signs themselves up.</strong> The platform administrator creates hostel
              Owner accounts. An Owner creates Manager and Warden accounts for their hostel. A
              Warden registers residents.
            </li>
            <li>
              <strong>Residents sign in with their phone number</strong>, which is mapped internally
              to a synthetic email address so that the authentication system has an identifier to
              work with. Your phone number is therefore also a login credential, which is why
              changing it is an account operation performed by staff rather than a profile edit.
            </li>
            <li>
              <strong>Every account must set a new password at first sign-in.</strong> Passwords are
              hashed by the authentication service; the application itself never sees or stores a
              password.
            </li>
            <li>
              A resident&rsquo;s account is deactivated when they check out of the hostel.
            </li>
          </ul>
        </Section>

        <Section id="data" title="3. What personal data is held">
          <p>
            The complete list. Free-text fields (complaint descriptions, leave reasons, payment
            notes) may contain whatever the person writing them chose to write, including details
            about other people.
          </p>
          <DataTable
            head={["Record", "Personal data", "Who it is about"]}
            rows={[
              [
                "Resident record",
                "Full name, phone number, email address, photograph, guardian name, guardian phone number, permanent address, ID-proof type, ID-proof document, date of joining, monthly fee, room and bed, status and check-out date",
                "The resident, and their guardian",
              ],
              [
                "Account",
                "Name, email, phone, role, hostel, active/inactive status, created and updated timestamps",
                "Every person with a login",
              ],
              [
                "Sign-in credentials",
                "Password hash, two-factor (TOTP) enrolment, sign-in timestamps — held by the authentication service, never by the application",
                "Every person with a login",
              ],
              [
                "Fee records",
                "Month, amount due, amount paid, payment date, a cash / UPI / bank label, and free-text notes",
                "The resident",
              ],
              [
                "Complaints",
                "Title, description, optional photograph, status history and resolution notes",
                "The resident, and anyone named in the text",
              ],
              [
                "Leave requests",
                "Dates, reason, decision and decision note",
                "The resident",
              ],
              [
                "Visitor log",
                "Visitor name, visitor phone number, relationship to the resident, check-in and check-out times",
                "The visitor — a person with no account here — and, by inference, the resident",
              ],
              [
                "Hostel operations",
                "Announcements, staff tasks, mess menus, expense and revenue notes and receipt images",
                "Staff, and anyone named on a receipt or in a note",
              ],
              [
                "Notifications",
                "In-app messages, which quote the complaint, task and leave text they refer to",
                "The recipient",
              ],
              [
                "Security audit trail",
                "Who did what and when, plus the IP address and browser user-agent of the person who did it",
                "Everyone who signs in",
              ],
              [
                "Security alerts",
                "Automated detections of unusual activity, with the account and IP address they fired on",
                "Everyone who signs in",
              ],
              [
                "Rate-limit counters",
                "Irreversible SHA-256 hashes of the login identifier only — never a readable phone number, email or IP address",
                "Pseudonymous",
              ],
            ]}
          />
        </Section>

        <Section id="not-collected" title="4. What is never collected">
          <p>
            Recorded here because absence is a privacy guarantee, and because it is verifiable
            against the application&rsquo;s own source code:
          </p>
          <ul>
            <li>
              <strong>No date of birth or age.</strong> The system has no age field of any kind.
            </li>
            <li>
              <strong>No card, bank account or UPI handle.</strong> Fee payments happen offline; the
              app records only that a payment was made, how much, and whether it was cash, UPI or a
              bank transfer. {APP_NAME} never takes, holds or moves money.
            </li>
            <li>
              <strong>No location data, no device contacts, no calendar, no biometrics, no
              advertising identifier.</strong> The Android app asks for internet access and nothing
              else.
            </li>
            <li>
              <strong>No analytics, telemetry, session-replay or error-reporting service.</strong>{" "}
              There is no third-party tracking code in the application.
            </li>
            <li>
              <strong>No advertising and no profiling.</strong> Nothing here is used to build a
              profile of you or to make an automated decision about you.
            </li>
            <li>
              <strong>No marketing cookies.</strong> The only cookies set are the strictly necessary
              session cookies that keep you signed in. They are HTTP-only, secure and same-site, and
              they are read only by the server.
            </li>
            <li>
              <strong>No email or SMS is sent.</strong> There is no messaging provider connected, so
              nothing about you leaves the platform through a message.
            </li>
          </ul>
        </Section>

        <Section id="documents" title="5. Photographs and ID documents">
          <p>
            Resident photographs, ID-proof scans, expense receipts and complaint photographs are
            kept in <strong>private storage buckets</strong>. They are not published, not indexed
            and have no permanent public address. There is no URL that anyone — including staff —
            can bookmark and come back to later.
          </p>
          <p>
            When an authorised member of staff opens one, the server mints a{" "}
            <strong>short-lived signed link</strong>. The link works for anyone holding it until it
            expires, so it is deliberately given a short life rather than treated as a secret:
          </p>
          <DataTable
            head={["Content", "Link expires after"]}
            rows={[
              ["Resident photographs and ID-proof documents", "15 minutes"],
              ["Expense receipts", "30 minutes"],
              ["Complaint photographs", "30 minutes"],
            ]}
          />
          <p>
            Every stored file is filed under its own hostel, and the server refuses any request for
            a path outside the requester&rsquo;s hostel. Uploaded files are checked by inspecting
            their actual leading bytes rather than trusting the file name or the type the browser
            claims, are capped at 8 MB, and documents are served as downloads so that a PDF cannot
            render inside the site&rsquo;s own origin.
          </p>
          <Callout tone="sand" title="A note on Aadhaar">
            <p>
              The ID-proof field accepts any identity document. Hostel operators are asked to prefer
              a non-Aadhaar document for residence verification, and to use a{" "}
              <strong>masked</strong> copy where an Aadhaar-based document is unavoidable. Operators
              may also record only the document type and skip the scan entirely — the system works
              perfectly well with no image stored at all, and that is the safest option.
            </p>
          </Callout>
        </Section>

        <Section id="why" title="6. Why the data is held">
          <p>
            The DPDP Act permits processing on <strong>consent</strong> or on one of the specific
            legitimate uses it lists. The position for each group of people is:
          </p>
          <ul>
            <li>
              <strong>Residents and guardians</strong> — notice and consent taken by the hostel at
              registration, for the purpose of managing your accommodation: allocating a bed,
              tracking the rent ledger, handling complaints and leave, and contacting your guardian
              in an emergency.
            </li>
            <li>
              <strong>Visitors</strong> — the safety and security of the premises and its residents.
              Hostels are required by this policy to display a visible notice at the point where the
              visitor log is kept, saying what is recorded and for how long.
            </li>
            <li>
              <strong>Staff and owners</strong> — the employment or commercial relationship with the
              hostel, and administration of the {APP_NAME} subscription.
            </li>
            <li>
              <strong>The security audit trail and security alerts</strong> — {APP_NAME}&rsquo;s own
              legitimate interest, and its duty, in keeping the system secure and being able to
              investigate an incident. This is the one category kept for security rather than for
              running the hostel.
            </li>
          </ul>
          <p>
            Where consent is the basis, it can be withdrawn. Withdrawing it may mean the hostel can
            no longer accommodate you, because it can no longer keep the record it needs to do so.
          </p>
        </Section>

        <Section id="retention" title="7. How long it is kept">
          <h3>Enforced automatically</h3>
          <p>
            A scheduled job runs inside the database every day at 03:15 UTC and applies these
            without anybody having to remember:
          </p>
          <DataTable
            head={["Data", "What happens"]}
            rows={[
              [
                "IP address and browser user-agent in the audit trail",
                "Erased 90 days after the event. The security event itself is kept — only the personal part is removed",
              ],
              ["Audit trail entries", "Deleted 365 days after the event"],
              [
                "Security alerts that have been reviewed and closed",
                "Deleted 365 days after the event",
              ],
              ["In-app notifications you have read", "Deleted 90 days after they were created"],
              ["Rate-limit counters (hashed)", "Swept after 24 hours"],
            ]}
          />
          <h3>Applied by the hostel operator</h3>
          <p>
            These are the standard periods. A hostel&rsquo;s own legal duties can extend them, never
            shorten them.
          </p>
          <DataTable
            head={["Data", "Kept for"]}
            rows={[
              [
                "ID-proof scan and photograph",
                "Removed by the hostel on request, and no later than the resident record below. Verification has already served its purpose by check-out, so ask for it earlier if you wish",
              ],
              [
                "Resident record and the linked account",
                "Kept while you live at the hostel, and removed on request after you check out — see “Asking us to delete your data” below. Fee and payment records are held longer where the hostel has an accounting duty",
              ],
              ["Visitor log entries", "12 months"],
              ["Leave requests", "12 months"],
              ["Complaints and their history", "12 months after the complaint is resolved"],
              ["Announcements and staff tasks", "24 months"],
              [
                "Fee, expense, revenue and subscription records",
                "The accounting-record period the hostel is legally required to observe — 8 years by default in India. These are not deleted on a privacy schedule",
              ],
              [
                "Security alerts that are still open",
                "Until they are reviewed and closed — an open alert is an open investigation",
              ],
            ]}
          />
          <p>
            <strong>Where those two rules collide, the person is removed rather than the record.</strong>{" "}
            A former resident&rsquo;s fee ledger may have to survive for the accounting period, while
            their guardian&rsquo;s phone number and permanent address should not. In that case the
            record is anonymised: the name, phone, email, photograph, guardian details, address and
            ID proof are stripped out and the financial figures are left behind attached to nobody.
          </p>
        </Section>

        <Section id="sharing" title="8. Who can see it">
          <h3>Inside your hostel</h3>
          <p>
            Access is enforced by the database itself, row by row, not just by what the app chooses
            to show. One hostel can never read another hostel&rsquo;s data.
          </p>
          <DataTable
            head={["Role", "What they can reach"]}
            rows={[
              ["Owner", "Everything belonging to the hostels they own"],
              [
                "Warden",
                "Resident records, fees, complaints, leaves and the visitor log for their hostel",
              ],
              [
                "Manager",
                "Rooms, finances and operations — but not resident personal data, which is blocked for this role at the database layer",
              ],
              [
                "Resident (student)",
                "Their own record, fees, complaints and leaves. Of their roommates they see a name and phone number only — no photographs, no documents",
              ],
              [
                "Platform administrator",
                "Platform-wide access for support and tenant administration. Every action is written to the audit trail",
              ],
            ]}
          />

          <h3>Outside your hostel</h3>
          <p>
            {APP_NAME} uses three service providers. They process data on our instructions and are
            not permitted to use it for their own purposes. This is the complete list — there is no
            payment processor, no messaging provider, no analytics vendor, no AI service and no
            advertising network involved.
          </p>
          <DataTable
            head={["Provider", "What they do", "What they hold"]}
            rows={[
              [
                "Supabase",
                "Database, authentication and private file storage",
                "Everything in section 3, including the password hashes",
              ],
              [
                "Vercel",
                "Application hosting",
                "Request logs, which contain IP addresses and browser user-agents",
              ],
              [
                "GitHub",
                "Source code, and storage for the nightly encrypted database backup",
                "Encrypted backup archives, retained 90 days",
              ],
            ]}
          />
          <p>
            <strong>
              We do not sell personal data, share it with advertisers or data brokers, or use it to
              train AI models.
            </strong>{" "}
            Data is disclosed to anyone else only where a law, a court or a lawful government
            request requires it, and the hostel is told when that happens unless the law forbids
            telling them.
          </p>
        </Section>

        <Section id="location" title="9. Where it is stored">
          <p>
            The database, authentication service and file storage are operated by Supabase; the
            application is hosted by Vercel. The specific hosting region for this deployment is a
            configuration setting held by the operator, who will tell you what it is on request —
            this page does not guess at it.
          </p>
          <p>
            The DPDP Act permits transfer of personal data outside India except to countries the
            Central Government has restricted. If you are in the EEA or the UK, see section 14 for
            the transfer position under the GDPR.
          </p>
        </Section>

        <Section id="security" title="10. How it is protected">
          <ul>
            <li>
              <strong>Tenant isolation at the database layer.</strong> Row-level security policies
              are attached to every table, so a query from one hostel cannot return another
              hostel&rsquo;s rows even if the application code asks it to.
            </li>
            <li>
              <strong>Role separation.</strong> Each of the five roles is confined to its own part
              of the app, checked both at the request boundary and again in the database. The
              Manager role is deliberately cut off from resident personal data entirely.
            </li>
            <li>
              <strong>Two-factor authentication (TOTP)</strong> is available to every role and can
              be made mandatory for the roles that carry the most access.
            </li>
            <li>
              <strong>Forced password change</strong> at first sign-in, so a staff-issued password
              never stays in use.
            </li>
            <li>
              <strong>An audit trail</strong> records who did what and when, which is what makes it
              possible to answer &ldquo;who looked at my record?&rdquo; at all.
            </li>
            <li>
              <strong>Encryption in transit.</strong> All traffic is served over TLS with HTTP
              Strict Transport Security, so browsers refuse to connect over plain HTTP. Data at rest
              is encrypted by the storage providers, and backup archives are separately encrypted
              with AES-256-GCM.
            </li>
            <li>
              <strong>Private file storage with short-lived signed links</strong> — section 5.
            </li>
            <li>
              <strong>Password hashes never reach the application.</strong> They are held only by
              the authentication service, so a compromise of the application database does not yield
              anybody&rsquo;s password.
            </li>
            <li>
              <strong>Rate limiting on authentication</strong>, keyed on an irreversible hash so the
              defence itself does not become a store of phone numbers.
            </li>
            <li>
              <strong>A strict content security policy</strong>, clickjacking protection and
              framework-level hardening on every response.
            </li>
          </ul>
          <p>
            No system is perfectly secure, and this policy does not claim otherwise. What it claims
            is that the measures above are real, are in the product today, and are described here
            accurately.
          </p>
        </Section>

        <Section id="backups" title="11. Backups, and the limits of deletion">
          <p>
            An encrypted backup of the database is taken nightly and kept for 90 days. Backups are
            point-in-time snapshots; they cannot be edited to remove one person from them. Being
            honest about what that means:
          </p>
          <ul>
            <li>
              When your data is erased from the live system it is gone from the live system
              immediately. It persists in existing backup snapshots until those snapshots expire, at
              most 90 days later.
            </li>
            <li>Backups are never restored into the live system except to recover from a failure.</li>
            <li>
              If a backup ever is restored, the erasure is re-applied afterwards, because a restore
              would otherwise bring deleted records back.
            </li>
            <li>
              Log entries held by our hosting providers age out on their schedules, which we do not
              control.
            </li>
          </ul>
        </Section>

        <Section id="children" title="12. Children">
          <p>
            Hostel and PG residents in India may be under 18. The DPDP Act requires verifiable
            consent from a parent or lawful guardian before a child&rsquo;s personal data is
            processed, and prohibits tracking, behavioural monitoring and targeted advertising
            directed at children.
          </p>
          <p>
            {APP_NAME} does no tracking, no behavioural monitoring, no profiling and no advertising
            of any kind, for anybody — so those prohibitions are met by the way the product is
            built, not merely by promise.
          </p>
          <p>
            The system holds no date of birth or age, so it cannot itself tell whether a resident is
            a minor. <strong>Parental consent is obtained by the hostel</strong> as part of its own
            admission paperwork, before a minor is registered.
          </p>
        </Section>

        <Section id="rights-dpdp" title="13. Your rights under the DPDP Act 2023">
          <p>If you are in India, you have the right to:</p>
          <ul>
            <li>
              <strong>Access</strong> — a summary of the personal data being processed about you and
              what it is being processed for, and the identities of anyone it has been shared with.
            </li>
            <li>
              <strong>Correction, completion and updating</strong> — have inaccurate or misleading
              data corrected, incomplete data completed, and out-of-date data updated.
            </li>
            <li>
              <strong>Erasure</strong> — have your personal data deleted, unless keeping it is
              required by law (for example, accounting records) or is necessary for the purpose you
              gave it for.
            </li>
            <li>
              <strong>Grievance redressal</strong> — a readily available means of raising a
              complaint, which is section 18 of this page. You must use it before approaching the
              Data Protection Board of India.
            </li>
            <li>
              <strong>Nomination</strong> — nominate another person to exercise these rights on your
              behalf in the event of death or incapacity.
            </li>
          </ul>
          <p>
            If your grievance is not resolved, you may complain to the{" "}
            <strong>Data Protection Board of India</strong>.
          </p>
        </Section>

        <Section id="rights-gdpr" title="14. Your rights under the GDPR and UK GDPR">
          <p>
            If you are in the European Economic Area, the United Kingdom or Switzerland, the
            following applies in addition. Our legal bases are: <strong>consent</strong> for
            resident and visitor records; <strong>contract</strong> for staff and subscription
            administration; and <strong>legitimate interests</strong> for the security audit trail
            and security alerts, the interest being keeping the system and the people in it safe.
          </p>
          <p>You have the right to:</p>
          <ul>
            <li>
              <strong>Access</strong> a copy of your personal data;
            </li>
            <li>
              <strong>Rectification</strong> of data that is inaccurate or incomplete;
            </li>
            <li>
              <strong>Erasure</strong> (&ldquo;right to be forgotten&rdquo;), subject to legal
              retention duties;
            </li>
            <li>
              <strong>Restriction</strong> of processing while a dispute about accuracy or
              lawfulness is resolved;
            </li>
            <li>
              <strong>Data portability</strong> — receive the data you provided in a structured,
              commonly used, machine-readable format;
            </li>
            <li>
              <strong>Object</strong> to processing carried out on the basis of legitimate
              interests;
            </li>
            <li>
              <strong>Withdraw consent</strong> at any time, without affecting processing already
              carried out;
            </li>
            <li>
              <strong>Lodge a complaint</strong> with your national supervisory authority.
            </li>
          </ul>
          <p>
            There is <strong>no automated decision-making or profiling</strong> that produces legal
            or similarly significant effects. Where personal data is transferred outside the EEA or
            the UK, it is transferred under the safeguards offered by the relevant provider,
            including standard contractual clauses.
          </p>
        </Section>

        <Section id="exercise" title="15. How to exercise your rights">
          <ol>
            <li>
              <strong>Ask your hostel first.</strong> They are the Data Fiduciary for your record
              and hold the fastest route to it: a Warden or Owner can correct your details in the
              app immediately, and corrections made that way are validated and logged.
            </li>
            <li>
              <strong>To request deletion</strong>, follow the process on{" "}
              <Link href="/legal/account-deletion">Delete your account and data</Link>. It sets out
              what gets deleted, what has to be kept and for how long, and how long the request
              takes.
            </li>
            <li>
              <strong>If the hostel does not respond</strong>, or your request is about the security
              audit trail or a platform account, write to the Grievance Officer at{" "}
              <a href={"mailto:" + CONTACT.email}>{CONTACT.email}</a>.
            </li>
          </ol>
          <p>
            We acknowledge requests within <strong>72 hours</strong> and aim to complete them within{" "}
            <strong>30 days</strong>. Requests are free. We will verify your identity before acting —
            not to obstruct you, but because an erasure request is also a way of attacking somebody
            if we act on it without checking who sent it. For a current resident, the Warden
            verifying you in person is usually the quickest route.
          </p>
        </Section>

        <Section id="breach" title="16. If something goes wrong">
          <p>
            If a personal data breach occurs, {APP_NAME} notifies the affected hostel operator
            without undue delay and supports them in meeting their own notification duties —
            including to the <strong>Data Protection Board of India</strong> and to affected
            residents under the DPDP Act, to CERT-In where its directions apply, and to the relevant
            supervisory authority within 72 hours where the GDPR applies.
          </p>
        </Section>

        <Section id="changes" title="17. Changes to this policy">
          <p>
            When this policy changes, the date at the top of the page changes with it. Material
            changes — a new category of data, a new provider, a longer retention period — are
            notified to hostel operators, who are responsible for passing them on to their
            residents. Older versions are available on request.
          </p>
        </Section>

        <Section id="contact" title="18. Grievance Officer and contact">
          <p>
            Questions, requests and complaints about this policy or about your personal data go to
            the Grievance Officer:
          </p>
          <div className="rounded-card border border-line bg-white/60 p-5 text-sm leading-7">
            <p className="text-navy">
              <strong>Grievance Officer</strong>
            </p>
            <p>{CONTACT.operatorName}</p>
            <p>
              <a href={"mailto:" + CONTACT.email} className="text-teal underline underline-offset-2">
                {CONTACT.email}
              </a>
            </p>
            <p className="whitespace-pre-line">{CONTACT.postalAddress}</p>
          </div>
          <p>
            For anything about your own resident record, contacting your hostel directly will
            usually be faster. If you are unhappy with the outcome, you may complain to the Data
            Protection Board of India or, if you are in the EEA or UK, to your national supervisory
            authority.
          </p>
          <p>
            See also the <Link href="/legal/terms">Terms of Service</Link> and{" "}
            <Link href="/legal/account-deletion">Delete your account and data</Link>.
          </p>
        </Section>
      </DocBody>
    </>
  );
}
