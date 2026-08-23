import type { Metadata } from "next";
import { LEGAL, isConfigured } from "@/lib/legal-config";
import Link from "next/link";
import { headers } from "next/headers";
import { Callout, DataTable, DocBody, DocHeader, Section, TableOfContents } from "../layout";

/**
 * PUBLIC account-deletion page — the URL that goes in the Play Console
 * "Data safety → Account deletion URL" field.
 *
 * It must render for a signed-OUT visitor: Google rejects a deletion or privacy URL that sits
 * behind a login. "/legal" is in PUBLIC_PATHS in lib/supabase/middleware.ts, and nothing in
 * this file or in ../layout.tsx reads a session, a cookie or the database.
 *
 * Every period and every claim below is sourced from docs/data-retention-and-privacy.md (§4
 * inventory, §5 retention, §6 erasure) and docs/backup-and-dr.md. Do not add a promise the
 * application cannot keep — the runbook that has to honour it is docs/account-deletion.md.
 */

/* ────────────────────────────────────────────────────────────────────────────
 * PLACEHOLDER — same convention as app/legal/privacy/page.tsx: a deliberately
 * non-resolvable address on the .invalid top-level domain, which can never be
 * registered. While it is unset this page renders a visible notice at the top.
 *
 * KEEP IT IN STEP WITH THE PRIVACY POLICY. The same mailbox is named in the
 * CONTACT block of app/legal/privacy/page.tsx; set both, in the same change.
 * ──────────────────────────────────────────────────────────────────────────── */
const CONTACT = {
  email: LEGAL.grievanceEmail,
} as const;

const PLACEHOLDERS_UNSET = !isConfigured;

const UPDATED = "2026-08-21";

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

/** Android applicationId — android/app/build.gradle.kts, see docs/play-store.md §1. */
const ANDROID_PACKAGE = "app.hostelpro.twa";

/** Kept as named constants so this page and docs/account-deletion.md cannot drift apart. */
const ACKNOWLEDGE_HOURS = 72;
const COMPLETE_DAYS = 30;

export const metadata: Metadata = {
  title: "Delete your account and data",
  description:
    "How to ask for your NIVORA account and personal data to be deleted, what is erased, what has to be kept and why, and how long it takes.",
};

const SECTIONS = [
  { id: "app", title: "The app this applies to" },
  { id: "accounts", title: "How accounts here are created" },
  { id: "in-app", title: "Requesting deletion inside the app" },
  { id: "email", title: "Requesting deletion without signing in" },
  { id: "timeline", title: "What happens, and when" },
  { id: "deleted", title: "What is deleted" },
  { id: "kept", title: "What is kept, and why" },
  { id: "limits", title: "What deletion cannot reach" },
  { id: "who", title: "Who your request goes to" },
] as const;

export default async function AccountDeletionPage() {
  // Forces dynamic rendering. A statically prerendered page carries no CSP nonce, and the
  // 'strict-dynamic' policy in lib/security-headers.ts would then block every script on it —
  // the same reason app/not-found.tsx reads headers(). The sibling legal pages opt into
  // force-static instead; this one is the URL Google Play actually loads, so it gets the
  // per-request nonce and hydrates cleanly.
  await headers();

  return (
    <>
      <DocHeader
        title="Delete your account and data"
        summary={
          "How to ask for your " +
          APP_NAME +
          " account and personal data to be deleted, what is erased, what has to be kept for legal reasons and for how long, and how long the whole thing takes. You do not need to sign in to read this or to make the request."
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
              Signed in? <strong>Profile → Delete my account and data.</strong> One tap files the
              request.
            </li>
            <li>
              Cannot sign in? Email <strong>{CONTACT.email}</strong>. Never email photographs of
              your ID.
            </li>
            <li>
              Your identity is confirmed first — by the hostel, in person or on the number already
              on your record. Then your details, photo and ID proof are erased.
            </li>
            <li>
              Fee and payment records survive, because the hostel has an accounting duty it cannot
              waive. Your name is taken out of them instead.
            </li>
            <li>
              Acknowledged within {ACKNOWLEDGE_HOURS} hours, completed within {COMPLETE_DAYS} days.
            </li>
          </ul>
        </Callout>

        <Section id="app" title="1. The app this applies to">
          <ul>
            <li>
              <strong>App:</strong> {APP_NAME} — hostel and PG management software.
            </li>
            <li>
              <strong>Android package:</strong> <code>{ANDROID_PACKAGE}</code>
            </li>
            <li>
              <strong>Applies to:</strong> the Android app and the website. They are the same
              service and the same data.
            </li>
          </ul>
          <p>
            This page is the account-deletion route for {APP_NAME}. It covers every kind of account
            the app issues: residents, wardens, managers and hostel owners.
          </p>
        </Section>

        <Section id="accounts" title="2. How accounts here are created">
          <p>
            {APP_NAME} is not an app you sign up for. A hostel or PG operator runs it for their own
            property: the warden registers each resident, and the owner creates the manager and
            warden accounts. Nobody creates their own account, and residents sign in with the phone
            number their warden registered.
          </p>
          <p>
            That is why deletion is a <strong>verified request</strong> rather than a button that
            erases everything on the spot. Two reasons, both of which protect you:
          </p>
          <ul>
            <li>
              <strong>A request in your name might not be from you.</strong> Your identity is
              confirmed before anything is erased — otherwise anyone who picked up your phone could
              wipe your records, and a deletion cannot be undone.
            </li>
            <li>
              <strong>Your record is tied to the hostel&rsquo;s own books and to a physical bed.</strong>{" "}
              Removing it unilaterally would delete accounting records the hostel is legally
              required to keep, and mark an occupied bed as free.
            </li>
          </ul>
          <p>
            Nothing is erased at the moment you ask. What happens immediately is that the request is
            recorded and the people who can act on it are told.
          </p>
        </Section>

        <Section id="in-app" title="3. Requesting deletion inside the app">
          <p>If you can still sign in, this is the fastest route:</p>
          <ol>
            <li>
              Open {APP_NAME} and sign in — residents with their phone number, staff with their
              email address.
            </li>
            <li>
              Residents: open the <strong>Profile</strong> tab. That is your
              profile screen.
            </li>
            <li>
              Scroll to <strong>Delete my account and data</strong>, read what it tells you, and
              confirm. You can add a reason, but you do not have to give one.
            </li>
          </ol>
          <p>
            Your warden and hostel owner are notified straight away, and the request is recorded
            with the date and time. The screen then shows the date your request was filed, so you
            can check it was received.
          </p>
          <p>
            Staff accounts (manager, warden, owner) do not yet have this control on their own
            profile screen — use the email route in section 4 instead.
          </p>
        </Section>

        <Section id="email" title="4. Requesting deletion without signing in">
          <p>
            If you have left the hostel, no longer use the phone number you signed in with, or
            simply do not want to sign in, write to the grievance contact:
          </p>
          <p>
            <a href={"mailto:" + CONTACT.email + "?subject=Account%20deletion%20request"}>
              {CONTACT.email}
            </a>
            {PLACEHOLDERS_UNSET ? " — placeholder address, not yet monitored (see the notice above)." : null}
          </p>
          <p>Include enough for the hostel to find you and to check that it is really you:</p>
          <ul>
            <li>Your full name, as the hostel recorded it.</li>
            <li>The name of the hostel or PG, and roughly when you stayed there.</li>
            <li>The phone number you used to sign in.</li>
            <li>
              Whether you want your data <strong>erased</strong>, or only a <strong>copy</strong> of
              what is held about you.
            </li>
          </ul>
          <Callout tone="sand" title="Do not email photographs of your ID">
            <p>
              Email is not a secure channel, and you will never be asked for identity documents that
              way. Identity is confirmed with the hostel you stayed at — in person, or on the phone
              number already held on your record.
            </p>
          </Callout>
        </Section>

        <Section id="timeline" title="5. What happens, and when">
          <DataTable
            head={["When", "What happens"]}
            rows={[
              [
                "Within " + ACKNOWLEDGE_HOURS + " hours",
                "Your request is acknowledged and logged — who asked, and when.",
              ],
              [
                "Next",
                "Your hostel confirms your identity, in person or on the number already on your record. This is never done over email.",
              ],
              [
                "Within " + COMPLETE_DAYS + " days",
                "Your data is erased. Where a financial record has to survive, your identity is stripped out of it instead. You are told what was deleted and what was kept.",
              ],
              [
                "If money is outstanding",
                "Deleting your data does not cancel anything you owe or are owed. Settle that with the hostel separately — the payment record is kept either way, without your name on it.",
              ],
            ]}
          />
        </Section>

        <Section id="deleted" title="6. What is deleted">
          <p>Once your identity is confirmed, all of the following is permanently removed:</p>
          <DataTable
            head={["What", "Detail"]}
            rows={[
              [
                "Your identity and contact details",
                "Name, phone number, email address, permanent address, date of joining and monthly fee on your resident record.",
              ],
              [
                "Your photograph and ID proof",
                "The images held in private storage. These are deleted first, ahead of everything else — they are the most sensitive thing the system holds about you.",
              ],
              [
                "Your guardian's details",
                "Guardian name and phone number. They were collected from you, and they go with your record.",
              ],
              [
                "Complaints, leave requests and visitor entries",
                "Everything you filed, any photographs attached to it, and the log of visitors recorded against your name while you stayed.",
              ],
              [
                "Your room and bed",
                "The link between you and a physical bed is removed, and the bed is released.",
              ],
              [
                "Your sign-in",
                "The login itself is deleted, so the phone number or email you signed in with no longer works. Notifications addressed to you go with it.",
              ],
            ]}
          />
          <p>
            Deletion here means deletion from the live system, not a hidden flag: the rows and the
            files are removed. See section 8 for the one place copies persist for a while.
          </p>
        </Section>

        <Section id="kept" title="7. What is kept, and why">
          <p>
            Some records cannot be deleted on request. Each one below is kept for a stated reason
            and for a stated period. <strong>None of it is kept for advertising, profiling or
            analytics</strong> — {APP_NAME} contains no advertising, no analytics and no tracking
            code of any kind.
          </p>
          <DataTable
            head={["What is kept", "For how long", "Why"]}
            rows={[
              [
                "Fee and payment records",
                "As long as the hostel's accounting duty requires — 8 years unless its accountant sets a different period.",
                "Indian tax and company-law record keeping outlives any privacy schedule, and a business cannot lawfully delete its books on request. Your name, phone, address and ID proof are removed from the record instead, so the ledger survives without you being identifiable in it.",
              ],
              [
                "Security and sign-in log",
                "365 days. The IP address and device string are removed after 90 days.",
                "Held so that a break-in can be detected, investigated and reported — a duty of its own. Once your account is gone these entries reference an internal identifier, not your name. Deleting them would destroy the evidence needed for the next security incident, including one affecting you.",
              ],
            ]}
          />
        </Section>

        <Section id="limits" title="8. What deletion cannot reach">
          <ul>
            <li>
              <strong>Encrypted backups</strong> are sealed point-in-time copies and cannot be
              edited row by row. Deleted data is never restored into the live system, backups expire
              automatically after <strong>90 days</strong>, and if a backup ever has to be restored
              the deletion is applied again immediately afterwards.
            </li>
            <li>
              <strong>Our hosting providers&rsquo; own logs.</strong> Supabase and Vercel keep
              service logs on their own schedules, outside our control. They contain request
              metadata, not your resident record.
            </li>
            <li>
              <strong>Anything already outside the app.</strong> A receipt your hostel printed, or a
              register they keep on paper, is theirs — ask them about it directly.
            </li>
          </ul>
        </Section>

        <Section id="who" title="9. Who your request goes to">
          <p>
            Your hostel or PG operator decides what resident data is collected and why, so the
            request is theirs to answer; {APP_NAME} runs the software on their behalf and carries
            out the deletion. In the language of the DPDP Act 2023, your hostel is the Data
            Fiduciary and {APP_NAME} is the Data Processor — the{" "}
            <Link href="/legal/privacy">Privacy Policy</Link> sets this out in full.
          </p>
          <p>
            If your hostel does not respond, write to <a href={"mailto:" + CONTACT.email}>{CONTACT.email}</a>{" "}
            and it will be taken up with them directly.
          </p>
          <p>
            Your data is held by exactly two service providers on {APP_NAME}&rsquo;s behalf —
            Supabase (database, sign-in and private file storage) and Vercel (application hosting).
            There is no advertising network, no analytics service, no payment processor and no email
            or SMS provider in the picture.
          </p>
        </Section>
      </DocBody>
    </>
  );
}
