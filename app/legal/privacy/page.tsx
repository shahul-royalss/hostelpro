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
 * THE GRIEVANCE CONTACT IS A ROLE, NOT A PERSON. Play requires a working
 * contact and the DPDP Act requires a grievance officer's contact; a role title
 * plus a monitored role mailbox satisfies both, and neither is improved by
 * publishing somebody's name and street address. See lib/legal-config.ts.
 * ──────────────────────────────────────────────────────────────────────────── */
const CONTACT = {
  operatorName: LEGAL.operatorName,
  officer: LEGAL.grievanceOfficer,
  email: LEGAL.grievanceEmail,
  postalAddress: LEGAL.postalAddress,
} as const;

const PLACEHOLDERS_UNSET = !isConfigured;

// The publication date of the Terms + Privacy pair, and the string an in-app acceptance is
// recorded against. It lives in lib/legal-config.ts so that this page, its three siblings, the
// Android app and public.legal_versions cannot drift apart — see the note on LEGAL_VERSION
// there, which explains why bumping it re-asks every user for their agreement.
const UPDATED = LEGAL_VERSION;

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How NIVORA collects, stores, shares, protects and deletes the personal data of hostel residents, guardians, visitors and staff — and your rights under India's DPDP Act 2023.",
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

/**
 * TEN SECTIONS, and they are the same ten the Android app shows — see
 * nivora_app/lib/features/legal/legal_documents.dart, which carries this text so the consent
 * gate can draw it without a network call.
 *
 * This page ran to eighteen sections. The cut was made by merging overlapping ones and deleting
 * repetition, never by softening a claim: the GDPR section went because this is an Indian PG
 * product with Indian users, and the retention periods that no code enforced went with it,
 * rather than being restated more vaguely. Every period below is traceable to
 * app.apply_retention() / app.erase_student() in db/schema.sql, which the pg_cron job
 * 'hostelpro-retention' runs nightly at 03:15 UTC.
 */
const SECTIONS = [
  { id: "who", title: "Who this policy is from, and how accounts work" },
  { id: "data", title: "What personal data is held" },
  { id: "not-collected", title: "What is never collected" },
  { id: "documents", title: "Photographs and identity documents" },
  { id: "why", title: "Why it is held" },
  { id: "sharing", title: "Who can see it, where it is stored, and how it is protected" },
  { id: "retention", title: "How long it is kept, and what deletion reaches" },
  { id: "rights", title: "Your rights, and how to use them" },
  { id: "children", title: "Children" },
  { id: "contact", title: "Changes to this policy, and the Grievance Officer" },
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
              models. There is no advertising and no analytics of ours anywhere in it — see
              section 3 for the one exception, which is Razorpay&rsquo;s own fraud checks during a
              payment.
            </li>
            <li>
              {/* NO SINGLE NUMBER HERE, because there is not one. SIGNED_URL_TTL in
                  supabase/functions/_shared/storage.ts gives student documents 15 minutes and
                  complaint photographs 30, and the shortened draft of this summary flattened both
                  to "15 minutes" — which is simply untrue of a complaint photo. Section 4 states
                  both figures exactly; a summary may be less precise than the section it
                  summarises, never wrong about it. */}
              Photographs and ID-proof scans sit in private storage and are only ever reachable
              through a link that expires within half an hour.
            </li>
            <li>
              You can ask for a copy of your data, ask for it to be corrected, or ask for it to be
              deleted — see{" "}
              <Link href="/legal/account-deletion">Delete your account and data</Link>.
            </li>
          </ul>
        </Callout>

        <Section id="who" title="1. Who this policy is from, and how accounts work">
          <p>
            {APP_NAME} is software licensed to hostel and PG operators. Your hostel decides which
            residents to admit, what to record about them and why; {APP_NAME} stores and processes
            that information on the hostel&rsquo;s instructions. Under India&rsquo;s{" "}
            <strong>Digital Personal Data Protection Act, 2023 (DPDP Act)</strong> that makes{" "}
            <strong>your hostel the Data Fiduciary</strong> and{" "}
            <strong>{APP_NAME} the Data Processor</strong>, so your hostel is your first point of
            contact for anything about your own record. For a small set of data {APP_NAME} decides
            on its own — platform staff accounts, the security log and security alerts —{" "}
            {APP_NAME} is the Data Fiduciary. This deployment is operated by{" "}
            <strong>{CONTACT.operatorName}</strong>, contactable at{" "}
            <a href={"mailto:" + CONTACT.email}>{CONTACT.email}</a>.
          </p>
          <p>
            How accounts work matters for privacy, because it changes who put your data into the
            system:
          </p>
          <ul>
            <li>
              <strong>Nobody signs themselves up.</strong> The platform administrator creates hostel
              Owner accounts, an Owner creates Manager and Warden accounts, and a Warden registers
              residents. Most of what is here was typed in by hostel staff, from documents you
              handed them at the desk.
            </li>
            <li>
              <strong>Residents sign in with their phone number</strong>, mapped internally to a
              synthetic email address so the authentication system has an identifier to work with.
              Your phone number is therefore also a login credential, which is why changing it is an
              account operation performed by staff rather than a profile edit.
            </li>
            <li>
              <strong>Every account must set a new password at first sign-in.</strong> Passwords are
              hashed by the authentication service; the application itself never sees or stores one.
            </li>
            <li>A resident&rsquo;s account is deactivated when they check out of the hostel.</li>
          </ul>
        </Section>

        <Section id="data" title="2. What personal data is held">
          <p>
            The complete list. Free-text fields — complaint descriptions, leave reasons, payment
            notes — may contain whatever the person writing them chose to write, including details
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
                "Month, amount due, amount paid, payment date, a cash / UPI / bank label, free-text notes, and the gateway's reference where rent was paid online",
                "The resident",
              ],
              [
                "Complaints and leave",
                "Complaint title, description, optional photograph, status history and resolution notes; leave dates, reason, decision and decision note",
                "The resident, and anyone named in the text",
              ],
              [
                "Visitor log",
                "Visitor name, visitor phone number, relationship to the resident, check-in and check-out times",
                "The visitor — a person with no account here — and, by inference, the resident",
              ],
              [
                "Hostel operations",
                "Notices, staff tasks, mess menus, expense and revenue notes and receipt images, and the in-app notifications that quote them",
                "Staff, and anyone named on a receipt or in a note",
              ],
              [
                "Security log and alerts",
                "Who did what and when, plus the IP address and browser user-agent of the person who did it, and automated detections of unusual activity. Login rate limits are kept as irreversible SHA-256 hashes — never a readable phone number, email or IP address",
                "Everyone who signs in",
              ],
              [
                "Your agreement to these documents",
                "Which version of the Terms of Use and this Privacy Policy you accepted, when, and whether you were using the app or the website. No IP address and no device details are stored with it",
                "Everyone who signs in",
              ],
            ]}
          />
          <p>
            The last row is the record of the permission the rest of this table depends on — because
            a consent that cannot be evidenced afterwards is not worth having asked for.
          </p>
        </Section>

        <Section id="not-collected" title="3. What is never collected">
          <p>
            Recorded here because absence is a privacy guarantee, and because it is verifiable
            against the application&rsquo;s own source code:
          </p>
          <ul>
            <li>
              <strong>No date of birth or age.</strong> The system has no age field of any kind.
            </li>
            <li>
              <strong>No card number, bank account, UPI ID or CVV.</strong> This is still true now
              that rent can be paid inside the app: those details are typed into{" "}
              <strong>Razorpay&rsquo;s own checkout</strong> and never reach {APP_NAME} at all. What
              comes back is a reference saying that a payment of a stated amount succeeded. Rent
              paid at the desk in cash is recorded by your warden as a cash entry. {APP_NAME} never
              holds your money in either case — see section 6.
            </li>
            <li>
              <strong>No location data, no device contacts, no calendar, no biometrics, no
              advertising identifier.</strong> The Android app asks only for internet access and the ability to tell whether you are online — nothing
              else.
            </li>
            <li>
              {/* The Android app bundles Razorpay's native Checkout SDK, which runs its own
                  device and session checks during a payment — that is exactly why the Data Safety
                  form declares "Device or other IDs · Fraud prevention". Claiming no third-party
                  tracking here would contradict the form the same app files, which is the most
                  common privacy-related rejection there is. See legal_documents.dart, which
                  carries the identical sentence. */}
              <strong>
                No analytics, session replay or crash reporting of our own, no advertising, and no
                tracking across other apps or sites.
              </strong>{" "}
              Razorpay&rsquo;s checkout runs its own device and session checks while a payment is
              open, for its own fraud prevention; {APP_NAME} receives none of it.
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
              <strong>No SMS, and no marketing email of any kind.</strong> {APP_NAME} sends only the
              few emails that keep the account working — a link to confirm your address, a password
              reset — delivered through Google&rsquo;s mail service. There is no mailing list to be
              on.
            </li>
            <li>
              <strong>No push notifications.</strong> Notifications appear inside the app when you
              open it. The Android build registers no device token with any notification service.
            </li>
          </ul>
        </Section>

        <Section id="documents" title="4. Photographs and identity documents">
          <p>
            Resident photographs, identity documents, expense receipts and complaint photographs are
            kept in <strong>private storage buckets</strong>. They are not published, not indexed
            and have no permanent public address. There is no URL that anyone — including staff —
            can bookmark and come back to later.
          </p>
          <p>
            When an authorised member of staff opens one, the server mints a{" "}
            <strong>short-lived signed link</strong>. The link works for anyone holding it until it
            expires, so it is deliberately given a short life rather than treated as a secret:{" "}
            <strong>15 minutes</strong> for a resident photograph or identity document,{" "}
            <strong>30 minutes</strong> for an expense receipt or a complaint photograph.
          </p>
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

        <Section id="why" title="5. Why it is held">
          <p>
            The DPDP Act permits processing on <strong>consent</strong> or on one of the specific
            legitimate uses it lists. The position for each group of people is:
          </p>
          <ul>
            <li>
              <strong>Residents and guardians</strong> — notice and consent taken by the hostel at
              registration, for the purpose of managing your accommodation: allocating a bed,
              keeping the rent ledger, handling complaints and leave, and contacting your guardian
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
              <strong>The security log and security alerts</strong> — {APP_NAME}&rsquo;s own
              legitimate interest, and its duty, in keeping the system secure and being able to
              investigate an incident. This is the one category kept for security rather than for
              running the hostel.
            </li>
          </ul>
          <p>
            Where consent is the basis, it can be withdrawn — though withdrawing it may mean the
            hostel can no longer accommodate you, because it can no longer keep the record it needs
            to do so. There is <strong>no profiling and no automated decision-making</strong> in{" "}
            {APP_NAME} at all.
          </p>
        </Section>

        <Section
          id="sharing"
          title="6. Who can see it, where it is stored, and how it is protected"
        >
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
                "Platform-wide access for support and tenant administration. Every action is written to the security log",
              ],
            ]}
          />

          <h3>Outside your hostel</h3>
          <p>
            Five companies process some part of it, on our instructions and not for their own
            purposes. This is the complete list — there is no analytics vendor, no advertising
            network, no crash-reporting service, no customer-messaging tool and no AI provider in
            the picture.
          </p>
          <DataTable
            head={["Provider", "What they do", "What they hold"]}
            rows={[
              [
                "Supabase",
                "Database, authentication and private file storage, in the ap-southeast-1 region — Singapore",
                "Everything in section 2, including the password hashes",
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
              [
                "Razorpay",
                "Processing an online rent payment, only when you choose to pay in the app",
                "Your name, email and phone, so the payment can be attributed to you, plus the payment details you enter on their own checkout. We receive back only the amount, the identifiers and the method, and Razorpay keeps its own record under its own policy",
              ],
              [
                "Google",
                "Delivering the account emails — a confirmation link, a password reset",
                "Your email address and the contents of those messages. No marketing email is ever sent",
              ],
            ]}
          />
          <p>
            Data is encrypted in transit and at rest. The DPDP Act permits transfer of personal data
            outside India except to countries the Central Government has restricted.{" "}
            <strong>
              We do not sell personal data, share it with advertisers or data brokers, or use it to
              train AI models.
            </strong>{" "}
            It is disclosed to anyone else only where a law, a court or a lawful government request
            requires it, and the hostel is told when that happens unless the law forbids telling
            them.
          </p>

          <h3>How it is protected</h3>
          <ul>
            <li>
              <strong>Tenant isolation at the database layer.</strong> Row-level security policies
              are attached to every table, so a query from one hostel cannot return another
              hostel&rsquo;s rows even if the application code asks it to.
            </li>
            <li>
              <strong>Role separation.</strong> Each role is confined to its own part of the app,
              checked at the request boundary and again in the database. The Manager role is
              deliberately cut off from resident personal data entirely.
            </li>
            <li>
              <strong>Two-factor authentication (TOTP)</strong> is available to every role and is
              required for the roles that carry the most access, and a{" "}
              <strong>forced password change</strong> at first sign-in means a staff-issued password
              never stays in use.
            </li>
            <li>
              <strong>A security log</strong> records who did what and when, which is what makes it
              possible to answer &ldquo;who looked at my record?&rdquo; at all.
            </li>
            <li>
              <strong>Encryption in transit.</strong> All traffic is served over TLS with HTTP
              Strict Transport Security, so browsers refuse to connect over plain HTTP. Data at rest
              is encrypted by the storage providers, and backup archives are separately encrypted
              with AES-256-GCM.
            </li>
            <li>
              <strong>Private file storage with short-lived signed links</strong> — section 4 — and{" "}
              <strong>password hashes that never reach the application</strong>, so a compromise of
              the application database does not yield anybody&rsquo;s password.
            </li>
            <li>
              <strong>Rate limiting on authentication</strong>, keyed on an irreversible hash so the
              defence itself does not become a store of phone numbers, plus a strict content
              security policy and clickjacking protection on every response.
            </li>
          </ul>
          <p>
            No system is perfectly secure, and this policy does not claim otherwise. What it claims
            is that the measures above are real, are in the product today, and are described here
            accurately. If a personal data breach occurs, {APP_NAME} notifies the affected hostel
            operator without undue delay and supports them in meeting their own notification duties
            — including to the <strong>Data Protection Board of India</strong> and to affected
            residents under the DPDP Act, and to CERT-In where its directions apply.
          </p>
        </Section>

        <Section id="retention" title="7. How long it is kept, and what deletion reaches">
          <p>
            A scheduled job runs inside the database every night at 03:15 UTC and applies these
            without anybody having to remember:
          </p>
          <DataTable
            head={["Data", "What happens"]}
            rows={[
              [
                "A departed resident's record",
                "Erased one month after check-out, and with it the photograph and identity document, the complaints, leave requests and visitor entries belonging to that resident, and the login itself. A re-admission before the date arrives cancels it",
              ],
              [
                "Complaints and notices",
                "Deleted two months after they are raised or posted — resolved or not, since ageing from the resolution date would let an unclosed complaint outlive the policy — along with their history and any photograph attached",
              ],
              ["In-app notifications you have read", "Deleted 90 days after they were created"],
              [
                "IP address and browser user-agent in the security log",
                "Erased 90 days after the event. The event itself is kept — only the personal part is removed",
              ],
              [
                "Security log entries, and closed security alerts",
                "Deleted 365 days after the event. An alert that is still open stays until it is reviewed and closed — an open alert is an open investigation",
              ],
              ["Rate-limit counters (hashed)", "Swept after 24 hours"],
              [
                "Staff tasks and mess menus",
                "Kept for as long as the hostel's workspace exists, and removed with it. The nightly job does not age these: a task names the staff member it was assigned to, and deleting it while that person still works there would erase the hostel's own operating history",
              ],
              [
                "Fee, expense, revenue and subscription records",
                "Kept indefinitely. This is the one exception, and it is not the hostel's to waive: a business has a statutory duty to keep records of money received, and those duties run for years",
              ],
              [
                "Your acceptance of these documents",
                "For as long as the account exists, and erased with it. It is the record of the permission everything else rests on",
              ],
            ]}
          />
          <p>
            <strong>Where those two rules collide, the person is removed rather than the record.</strong>{" "}
            A former resident&rsquo;s fee ledger has to survive, while their guardian&rsquo;s phone
            number and permanent address must not. In that case the record is anonymised: the name,
            phone, email, photograph, guardian details, address and ID proof are stripped out and
            the financial figures are left behind attached to nobody. &ldquo;Kept
            indefinitely&rdquo; above therefore describes an amount and a date, not a person. A
            hostel&rsquo;s own legal duties can extend a period, never shorten it, and you may ask
            your hostel at any time to erase something sooner.
          </p>
          <p>
            <strong>Deletion is not instant everywhere.</strong> An encrypted backup of the database
            is taken nightly and kept for 90 days. Backups are point-in-time snapshots and cannot be
            edited to remove one person, so data erased from the live system is gone from the live
            system immediately but persists in existing snapshots until they expire, at most 90 days
            later. Backups are never restored into the live system except to recover from a failure,
            and if one ever is, the erasure is re-applied immediately afterwards. Log entries held
            by our hosting providers age out on their own schedules, which we do not control.
          </p>
        </Section>

        <Section id="rights" title="8. Your rights, and how to use them">
          <p>Under the DPDP Act 2023 you have the right to:</p>
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
              complaint, which is section 10 of this page. You must use it before approaching the
              Data Protection Board of India.
            </li>
            <li>
              <strong>Nomination</strong> — nominate another person to exercise these rights on your
              behalf in the event of death or incapacity.
            </li>
          </ul>
          <p>
            <strong>Ask your hostel first.</strong> They are the Data Fiduciary for your record and
            hold the fastest route to it: a Warden or Owner can correct your details in the app
            immediately, and corrections made that way are validated and logged. To be erased, ask
            them too — checking a resident out schedules the erasure a month later, and it can be
            raised sooner on request.{" "}
            <Link href="/legal/account-deletion">Delete your account and data</Link> sets out what
            gets deleted, what has to be kept, and how long it takes. If the hostel does not
            respond, or your request is about the security log or a platform account, write to the
            Grievance Officer at <a href={"mailto:" + CONTACT.email}>{CONTACT.email}</a>.
          </p>
          <p>
            Nothing erases your record on the spot, and that is deliberate rather than an omission:
            it is tied to a bed you may still be occupying and to a fee ledger the hostel is
            required to keep, and an erasure accepted instantly in someone else&rsquo;s name would
            be a way to attack them. So a deletion is a request, confirmed with you, and then
            carried out — a resident signed in on the website can file one from{" "}
            <strong>Profile → Delete my account and data</strong>. We acknowledge requests within{" "}
            <strong>72 hours</strong> and aim to complete them within <strong>30 days</strong>.
            Requests are free. We will verify your identity before acting — for a current resident,
            the Warden verifying you in person is usually the quickest route. If you are unhappy
            with the outcome you may complain to the Data Protection Board of India.
          </p>
        </Section>

        <Section id="children" title="9. Children">
          <p>
            Hostel and PG residents in India may be under 18. The DPDP Act requires verifiable
            consent from a parent or lawful guardian before a child&rsquo;s personal data is
            processed, and prohibits tracking, behavioural monitoring and targeted advertising
            directed at children.
          </p>
          <p>
            {APP_NAME} does no tracking, no behavioural monitoring, no profiling and no advertising
            of any kind, for anybody — so those prohibitions are met by the way the product is
            built, not merely by promise. The system holds no date of birth or age, so it cannot
            itself tell whether a resident is a minor.{" "}
            <strong>Parental consent is obtained by the hostel</strong> as part of its own admission
            paperwork, before a minor is registered.
          </p>
        </Section>

        <Section id="contact" title="10. Changes to this policy, and the Grievance Officer">
          <p>
            When this policy changes, the date at the top of the page changes with it. Material
            changes — a new category of data, a new provider, a longer retention period — bump the
            version, currently <strong>{UPDATED}</strong>, and you are asked to read and accept the
            documents again the next time you open the app, so nobody is quietly moved onto text
            they have not seen. Older versions are available on request.
          </p>
          <p>
            Questions, requests and complaints about this policy or about your personal data go to
            the Grievance Officer:
          </p>
          <div className="rounded-card border border-line bg-white/60 p-5 text-sm leading-7">
            <p className="text-navy">
              <strong>{CONTACT.officer}</strong>
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
            usually be faster. See also the <Link href="/legal/terms">Terms of Use</Link> and{" "}
            <Link href="/legal/account-deletion">Delete your account and data</Link>.
          </p>
        </Section>
      </DocBody>
    </>
  );
}
