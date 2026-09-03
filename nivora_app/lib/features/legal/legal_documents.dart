/// THE TERMS OF USE AND THE PRIVACY POLICY, AS THE APP ITSELF HOLDS THEM.
///
/// ═══ WHY THE TEXT IS BUNDLED RATHER THAN FETCHED ═══
/// Both documents are also published on the open web (see [kTermsUrl] / [kPrivacyUrl]) because
/// Google Play requires a privacy policy at a URL a reviewer can open while signed out. That
/// requirement is about the LISTING. This file is about the APP, and the two need different
/// things:
///
///   · The consent gate must be able to show a person what they are agreeing to BEFORE they
///     have agreed to anything. Making that a network fetch means the one screen nobody may
///     skip is also the one screen that can fail, and a gate that cannot draw its own text is a
///     locked door.
///   · `url_launcher` is deliberately not a dependency of this project (see pubspec.yaml, which
///     records the same reasoning for four other packages). Handing the documents to a browser
///     would mean adding one to show text this app already has.
///
/// So the app carries the text, and the URLs are printed as selectable strings for anyone who
/// wants the canonical published copy. The coupling that keeps the two honest is [kLegalVersion]
/// — see below.
///
/// ═══ THE VERSION IS A CONTRACT BETWEEN THREE FILES ═══
/// The same string appears in three places and they must move together:
///
///   1. `lib/legal-config.ts`                 → `LEGAL_VERSION`  (the published web pages)
///   2. this file                             → [kLegalVersion]  (what the app shows and records)
///   3. `public.legal_versions.version`       → a migration      (what an acceptance may name)
///
/// Change the wording of either document → bump all three → every user is asked again, because
/// [ConsentGate] compares this constant against the versions the signed-in user has accepted.
///
/// DEPLOYMENT ORDER IS NOT OPTIONAL: the migration that publishes a version row must land
/// BEFORE an app build carrying that version string reaches anybody. `accept_legal_terms()`
/// refuses a version it has never heard of, and at the gate the only thing a user may do is
/// accept — so the wrong order locks every account out of the product. The row for the version
/// below is db/migrations/2026-09-04-legal-version-bump.sql; the rule it has to satisfy is
/// db/migrations/2026-09-02-legal-consent.sql §4.
///
/// test/legal_consent_test.dart asserts (1) and (2) against each other, so the pair cannot
/// drift silently. Nothing in Dart can check (3) — that one is the deployment order above.
library;

/// The published version of the Terms of Use + Privacy Policy pair that this build shows.
///
/// One string covers BOTH documents: they are presented together and agreed to together, so
/// there is no state in which a person is half-agreed.
const kLegalVersion = '2026-09-04';

/// Human-readable form of [kLegalVersion], for the "last updated" line.
const kLegalVersionLabel = '4 September 2026';

const kTermsUrl = 'https://hostelpro-three.vercel.app/legal/terms';
const kPrivacyUrl = 'https://hostelpro-three.vercel.app/legal/privacy';
const kDeletionUrl = 'https://hostelpro-three.vercel.app/legal/account-deletion';

/// ═══ VALUES THE OPERATOR OWNS, NOT THE ENGINEER ═══
///
/// These MIRROR `lib/legal-config.ts` at the repository root and must be changed in both places
/// at once. They are real-world facts about the business that cannot be derived from the
/// codebase.
///
/// THE CONTACT IS A ROLE, NOT A PERSON, AND THAT IS THE POINT. Google Play requires the privacy
/// policy to give a contact that works, and the DPDP Act 2023 requires a Data Fiduciary to
/// publish the contact of a grievance officer. A role title plus a monitored role mailbox
/// satisfies both without publishing somebody's name and street address to the open web, where
/// they would outlive the person holding the job. Do not put a personal name or a residential
/// address back into these constants.
const kOperatorName = 'NIVORA';
const kGrievanceOfficer = 'The Grievance Officer';
const kGrievanceEmail = 'support@nivora.dhrishtaerf.org';
const kPostalAddress = 'Chittoor, Andhra Pradesh, India';
const kGoverningLaw = 'the laws of India';
const kJurisdiction = 'the courts at Chittoor, Andhra Pradesh';

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENT MODEL
// ─────────────────────────────────────────────────────────────────────────────

/// One block inside a section. Sealed so the renderer is total and a block type added later
/// cannot quietly render as nothing.
sealed class LegalBlock {
  const LegalBlock();
}

/// A paragraph of prose.
final class Para extends LegalBlock {
  const Para(this.text);
  final String text;
}

/// A bulleted list.
final class Bullets extends LegalBlock {
  const Bullets(this.items);
  final List<String> items;
}

/// A term and what it means — used for the data inventory and the retention schedule, where a
/// two-column shape is what the information actually is.
final class Rows extends LegalBlock {
  const Rows(this.entries);
  final List<({String term, String detail})> entries;
}

final class LegalSection {
  const LegalSection({required this.heading, required this.blocks});
  final String heading;
  final List<LegalBlock> blocks;
}

final class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.tagline,
    required this.url,
    required this.sections,
  });

  final String id;
  final String title;

  /// One sentence under the title, so a reader knows what they are opening.
  final String tagline;

  /// Where the canonical published copy lives.
  final String url;
  final List<LegalSection> sections;
}

/// Both documents, in the order the gate presents them.
const kLegalDocuments = <LegalDocument>[kPrivacyPolicy, kTermsOfUse];

// ─────────────────────────────────────────────────────────────────────────────
// PRIVACY POLICY — 10 sections
// ─────────────────────────────────────────────────────────────────────────────
//
// EVERY FACTUAL CLAIM BELOW WAS READ OUT OF THE CODEBASE, not assumed. The field lists come
// from db/schema.sql, the buckets and link lifetimes from lib/storage.ts, the region from
// docs/server-health.md (`ap-southeast-1`), the sub-processors from what the project actually
// calls, and the retention periods from app.apply_retention() and app.erase_student() in
// db/schema.sql, which the pg_cron job 'hostelpro-retention' runs nightly at 03:15 UTC. If any
// of those change, this changes with them and the version bumps.
//
// SHORTER IS NOT VAGUER. This document was cut from eighteen sections to ten by merging and by
// deleting repetition — not by softening a claim. Where a period or a promise could not be
// traced to code it was removed rather than reworded, which is why the twelve-month visitor-log
// and leave-request periods that nothing enforced are gone, and why nothing here points at an
// in-app "delete my account" button the app does not have.

const kPrivacyPolicy = LegalDocument(
  id: 'privacy',
  title: 'Privacy Policy',
  tagline: 'What NIVORA holds about you, why, who can see it, and how to have it erased.',
  url: kPrivacyUrl,
  sections: [
    LegalSection(
      heading: 'Who this policy is from, and how accounts work',
      blocks: [
        Para(
          'NIVORA is software used by a hostel or PG operator to run their building. The '
          'operator decides what to collect about you and why; NIVORA stores and processes it '
          'on their instructions. In the language of the Digital Personal Data Protection Act '
          '2023 your hostel is the Data Fiduciary and NIVORA is the Data Processor. So a '
          'request to see, correct or erase your data is answered by your hostel first. For '
          'platform staff accounts and the security log, NIVORA is the Data Fiduciary itself.',
        ),
        Para(
          'Nobody signs themselves up. The platform creates hostel owners, an owner creates '
          'their manager and warden, and a warden registers residents. Residents sign in with '
          'the phone number their hostel registered, which is why changing it is something '
          'staff do rather than a profile edit. Everyone is given a temporary password and must '
          'set their own at first sign-in; passwords are hashed by the sign-in service and are '
          'never seen by NIVORA, by your hostel or by us.',
        ),
        Para(
          'That is why this policy matters more than it would for an app you chose to install: '
          'most of what is here was typed in by hostel staff, from documents you handed them at '
          'the desk.',
        ),
      ],
    ),
    LegalSection(
      heading: 'What is collected',
      blocks: [
        Rows([
          (
            term: 'Who you are',
            detail: 'Full name, phone number, email address if you have one, and your role.',
          ),
          (
            term: 'Resident details',
            detail: 'Permanent address, guardian\'s name and phone number, date of joining, '
                'monthly fee, the room and bed assigned to you, and whether you are active, on '
                'leave or vacated.',
          ),
          (
            term: 'Photograph and identity document',
            detail: 'A photo and a scan of the ID proof you presented at registration. This is '
                'the most sensitive thing in the system and it is treated as such — see below.',
          ),
          (
            term: 'Money',
            detail: 'Rent due, rent paid, the date and method of each payment, and free-text '
                'notes a warden adds to a receipt. Where rent is paid online, the reference the '
                'payment gateway issues.',
          ),
          (
            term: 'Things you raise',
            detail: 'Complaints — title, description and any photograph you attach — with the '
                'history of who changed their status. Leave requests, including your reason.',
          ),
          (
            term: 'Visitors',
            detail: 'If a visitor is logged at the desk, their name, phone number, relation to '
                'you and their check-in and check-out times.',
          ),
          (
            term: 'Hostel operations',
            detail: 'Notices, staff tasks, mess menus, and expense and revenue records with '
                'their receipt images — which can name whoever appears on them.',
          ),
          (
            term: 'Security log',
            detail: 'A record of significant actions — sign-ins, account changes, money '
                'recorded — with the IP address and browser or device description of the '
                'request. Login rate limits are kept as irreversible hashes, never as a '
                'readable phone number.',
          ),
          (
            term: 'Your agreement to this policy',
            detail: 'Which version you accepted, when, and whether you were using the app or '
                'the website. No IP address and no device details are stored with it. This '
                'record exists because consent that cannot be evidenced is not consent.',
          ),
        ]),
        Para(
          'Free-text boxes — a complaint, a leave reason, a note on a receipt — hold whatever '
          'the person writing them chose to write, including things about other people.',
        ),
      ],
    ),
    LegalSection(
      heading: 'What is never collected',
      blocks: [
        Bullets([
          'No date of birth and no age. The system has no such field.',
          'No card number, UPI ID, CVV or bank account. Where rent is paid online those details '
              'are typed into Razorpay\'s own checkout and never reach NIVORA at all. What comes '
              'back is a reference saying a payment of a stated amount succeeded.',
          'No location, contacts, calendar, microphone or biometrics. The Android app asks for '
              'internet access and nothing else.',
          'No advertising, no advertising identifier and no profiling. Nothing here is used to '
              'build a picture of you or to make an automated decision about you.',
          'No analytics, telemetry, session replay or crash reporting. There is no third-party '
              'tracking code in the app.',
          'No marketing cookies. The only cookies are the session cookies that keep you signed '
              'in, read by the server alone.',
          'No SMS, no marketing email and no mailing list. The only emails sent are the ones '
              'that keep the account working — a confirmation link, a password reset.',
          'No push notifications. Notices appear inside the app when you open it; the app '
              'registers no device token anywhere.',
        ]),
      ],
    ),
    LegalSection(
      heading: 'Photographs and identity documents',
      blocks: [
        Para(
          'Your photo and your identity document are held in private storage. They are never '
          'public, never linked from a shareable address, and are reachable only through a '
          'link created for a member of your hostel\'s staff at the moment they open it — '
          'fifteen minutes for a resident photo or ID document, thirty for a receipt or a '
          'complaint photograph. Every file is filed under its own hostel and the server '
          'refuses a request for a path outside the requester\'s hostel. Uploads are checked by '
          'their actual leading bytes rather than their file name, and capped at 8 MB.',
        ),
        Para(
          'A note on Aadhaar. Aadhaar is governed by its own law and UIDAI guidance restricts '
          'holding copies of the Aadhaar letter. NIVORA does not require Aadhaar and does not '
          'treat it differently from any other document; if your hostel asks for an ID you may '
          'offer a different one, or a masked Aadhaar where that is accepted. A hostel can also '
          'record the document type and skip the scan entirely — the system works with no image '
          'stored at all, and that is the safest option.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Why it is held',
      blocks: [
        Para(
          'The DPDP Act allows processing on consent or on one of the legitimate uses it lists. '
          'For each group of people:',
        ),
        Bullets([
          'Residents and guardians — on the consent your hostel takes at registration, to run '
              'the residency: allocate a bed, keep the rent ledger, answer a complaint, approve '
              'leave, and reach your guardian in an emergency.',
          'Visitors — the safety and security of the building and the people in it. A hostel '
              'must display a visible notice at the desk, because a visitor has no account here '
              'and gets no notice from the app.',
          'Staff and owners — their employment or commercial relationship with the hostel, and '
              'administration of the subscription.',
          'The security log — NIVORA\'s own interest in keeping the system secure and being '
              'able to investigate a compromised account. It exists for that and nothing else.',
        ]),
        Para(
          'Where consent is the basis it can be withdrawn, though withdrawing it may mean the '
          'hostel can no longer accommodate you, because it can no longer keep the record it '
          'needs to. There is no profiling and no automated decision-making in NIVORA.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Who can see it, where it is stored, and how it is protected',
      blocks: [
        Para(
          'Inside your hostel, access is enforced by the database itself through row-level '
          'security, evaluated against your signed-in identity on every request — not by a '
          'filter the app applies and could forget. One hostel cannot read another hostel\'s '
          'data even if its own software asked.',
        ),
        Bullets([
          'You see your own record, fees, complaints, leave and notices. Of your roommates you '
              'see a name and phone number — no photographs and no documents.',
          'Your warden sees the residents of their hostel; the owner sees their hostels.',
          'A manager sees rooms, money and operations, and is cut off from resident personal '
              'data at the database layer.',
          'A platform administrator can reach tenant records for support and billing. Every '
              'such action is written to the security log.',
          'Other residents cannot see anything else about you. There is no resident directory.',
        ]),
        Para(
          'Outside your hostel, five companies process some part of it. That is the complete '
          'list: no analytics vendor, no advertising network, no crash reporter, no messaging '
          'tool and no AI provider.',
        ),
        Rows([
          (
            term: 'Supabase',
            detail: 'The database, sign-in service and private file storage, in the '
                'ap-southeast-1 region — Singapore. Holds everything listed above, including '
                'the password hashes.',
          ),
          (
            term: 'Vercel',
            detail: 'Serves the web application. Keeps request logs, which contain IP addresses '
                'and browser descriptions.',
          ),
          (
            term: 'GitHub',
            detail: 'Holds the source code and the nightly encrypted database backup archive, '
                'for 90 days.',
          ),
          (
            term: 'Razorpay',
            detail: 'Only where you choose to pay rent in the app. Receives your name, email, '
                'phone and the amount; the card, UPI or netbanking details are entered in '
                'Razorpay\'s own checkout and never reach us. We get back the amount, the '
                'identifiers and the method. Razorpay keeps its own record under its own policy.',
          ),
          (
            term: 'Google',
            detail: 'Delivers the few account emails — a confirmation link, a password reset. '
                'Sees your email address and the message.',
          ),
        ]),
        Para(
          'Data is encrypted in transit and at rest. The DPDP Act permits personal data to be '
          'sent outside India except to countries the Central Government has restricted. '
          'Nothing is sold, given to an advertiser or a data broker, or used to train an AI '
          'model. It is disclosed to anyone else only where a law or a court requires it, and '
          'your hostel is told unless the law forbids telling them.',
        ),
        Para(
          'What protects it: row-level security on every table; a manager role deliberately '
          'blocked from resident personal data; two-factor authentication available to every '
          'role and required for the roles that carry the most access; a forced password change '
          'at first sign-in; the security log; TLS with strict transport security on every '
          'response; private storage with short-lived links; password hashes that never reach '
          'the application; login rate limiting keyed on an irreversible hash; and a strict '
          'content security policy. No system is perfectly secure and this policy does not '
          'claim otherwise — it claims these measures are in the product today.',
        ),
        Para(
          'If personal data is exposed, NIVORA tells the affected hostel without delay and '
          'helps them notify the Data Protection Board of India and the people affected, as the '
          'Act requires of them.',
        ),
      ],
    ),
    LegalSection(
      heading: 'How long it is kept, and what deletion reaches',
      blocks: [
        Para(
          'A job inside the database runs every night and applies these without anybody having '
          'to remember:',
        ),
        Rows([
          (
            term: 'A departed resident',
            detail: 'The record, and the photograph and identity document with it, are erased '
                'one month after check-out. Their complaints, leave requests and visitor '
                'entries go at the same time, and so does the login.',
          ),
          (
            term: 'Complaints and notices',
            detail: 'Deleted two months after they are raised or posted, resolved or not, '
                'along with their history and any photograph attached.',
          ),
          (
            term: 'Notifications you have read',
            detail: 'Ninety days.',
          ),
          (
            term: 'Security log',
            detail: 'The IP address and device description are erased after ninety days; the '
                'entry itself after a year. A security alert that is still open stays until it '
                'is closed, because an open alert is an open investigation.',
          ),
          (
            term: 'Fee, expense and revenue records',
            detail: 'Kept indefinitely. This is the one exception and it is not ours to waive: '
                'a business has a statutory duty to keep records of money received. Where that '
                'collides with erasure the person is removed rather than the record — name, '
                'phone, email, photograph, guardian details, address and ID proof are stripped '
                'out and the figures are left attached to nobody.',
          ),
          (
            term: 'Your acceptance of this policy',
            detail: 'For as long as the account exists, and erased with it. It is the record of '
                'the permission everything else rests on.',
          ),
        ]),
        Para(
          'Deletion is not instant everywhere. Encrypted backups are taken nightly and kept for '
          'ninety days, so something erased today disappears from the last backup up to ninety '
          'days later. Backups are never browsed and are never restored except to recover from '
          'a failure; if one ever is restored the erasure is applied again straight away. Logs '
          'held by our hosting providers age out on their own schedules. Most policies leave '
          'this out — it is stated here because it is true.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Your rights, and how to use them',
      blocks: [
        Para(
          'Under the DPDP Act 2023 you may ask for a summary of the data held about you and who '
          'it has been shared with, ask for it to be corrected, completed or erased, nominate '
          'someone to exercise these rights if you cannot, and complain.',
        ),
        Para(
          'Ask your hostel first — they hold the relationship and can act immediately. A wrong '
          'phone number or a misspelled name is a change your warden can make while you stand '
          'there. To be erased, ask them too: checking a resident out schedules the erasure a '
          'month later, and it can be raised sooner on request.',
        ),
        Para(
          'Nothing erases your record on the spot, and that is deliberate rather than an '
          'omission: it is tied to a bed you may still be in and to a ledger the hostel must '
          'keep, and an erasure accepted instantly in someone else\'s name would be a way to '
          'attack them. So a deletion is a request, confirmed with you, and then carried out. '
          'A resident signed in on the website can file one from Profile, then Delete my '
          'account and data. Anyone can file one from the public page at:',
        ),
        Para(kDeletionUrl),
        Para(
          'If your hostel does not answer, or the request is about the security log or a '
          'platform account, write to the Grievance Officer below.',
        ),
        Para(
          'Requests are free. We acknowledge one within 72 hours and aim to finish within 30 '
          'days, and we check who you are first — not to obstruct you, but because acting on an '
          'erasure request without checking is itself a way to harm somebody. If you are not '
          'satisfied you may complain to the Data Protection Board of India.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Children',
      blocks: [
        Para(
          'Hostel and PG residents in India are sometimes under eighteen. The Act requires a '
          'parent or guardian to consent for a child, and prohibits tracking, behavioural '
          'monitoring and advertising directed at children. NIVORA does none of those things '
          'for anybody of any age, so those prohibitions are met by the way the product is '
          'built rather than by a promise.',
        ),
        Para(
          'The system records no date of birth and therefore cannot tell who is a minor. Your '
          'hostel must obtain a guardian\'s consent in its own registration paperwork before '
          'registering one.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Changes to this policy, and the Grievance Officer',
      blocks: [
        Para(
          'When this policy changes materially, its version changes, and you are asked to read '
          'and accept it again the next time you open the app. You will not be quietly moved '
          'onto a policy you never saw.',
        ),
        Para('This version: $kLegalVersion, effective $kLegalVersionLabel.'),
        Rows([
          (term: 'Grievance Officer', detail: kGrievanceOfficer),
          (term: 'Operator', detail: kOperatorName),
          (term: 'Email', detail: kGrievanceEmail),
          (term: 'Post', detail: kPostalAddress),
        ]),
        Para('The published copy of this policy, always current, is at:'),
        Para(kPrivacyUrl),
      ],
    ),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// TERMS OF USE — 8 sections
// ─────────────────────────────────────────────────────────────────────────────

const kTermsOfUse = LegalDocument(
  id: 'terms',
  title: 'Terms of Use',
  tagline: 'The rules for using NIVORA, and what each side is responsible for.',
  url: kTermsUrl,
  sections: [
    LegalSection(
      heading: 'Who these terms bind',
      blocks: [
        Para(
          'These terms are between $kOperatorName, which provides this service, and you — '
          'whether you are a hostel owner who subscribes to it, a manager or warden given an '
          'account by an owner, or a resident given an account by a warden.',
        ),
        Para(
          'Using the app means accepting them. If you do not accept them you cannot use the '
          'app, and you can sign out from the same screen that asks.',
        ),
      ],
    ),
    LegalSection(
      heading: 'What the service does',
      blocks: [
        Para(
          'NIVORA records and organises the running of a hostel or PG: rooms and beds, '
          'residents, rent due and rent received, complaints, leave, visitors, notices, meals, '
          'staff tasks and expenses. It is delivered as a website and an Android app, and needs '
          'an internet connection.',
        ),
        Para(
          'It is a record-keeping tool. It is not an accounting package, not a legal or tax '
          'adviser, and not a substitute for the agreement between you and your hostel. The '
          'rent, the deposit, the notice period and the house rules are matters between the '
          'resident and the operator; NIVORA only records what they tell it.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Your account',
      blocks: [
        Para(
          'There is no self sign-up. Your account was created for you and comes with a '
          'temporary password you must change when you first sign in. An account belongs to the '
          'hostel\'s workspace rather than to you personally, and is deactivated when you check '
          'out or when your employment ends.',
        ),
        Bullets([
          'Keep your password to yourself. Anything done with your account is treated as done '
              'by you, because that is how the security log records it.',
          'Turn on two-factor authentication where it is offered. Where it is required for your '
              'role you will be asked to set it up before you can continue.',
          'Tell your hostel immediately if you think someone else has your password.',
          'Do not use somebody else\'s account, and do not ask a member of staff to act as you.',
        ]),
      ],
    ),
    LegalSection(
      heading: 'Acceptable use',
      blocks: [
        Para('You agree not to:'),
        Bullets([
          'Enter information you know to be false — a payment that did not happen, an invented '
              'complaint against another resident, or someone else\'s identity document.',
          'Try to reach data belonging to another hostel or another person, or probe the '
              'service for a way to do so. Deliberately tripping the rate limits or the '
              'security alerts is itself a breach of these terms.',
          'Upload anything unlawful, or a photograph of a person taken without their knowledge.',
          'Use the visitor log, complaints or any other feature to harass anybody.',
          'Copy, resell, sublicense or reverse-engineer the software, or extract data from it '
              'in bulk by automated means, except where the law says you may despite this.',
        ]),
        Para(
          'Complaints are read by staff, and notices by every resident they are posted to. '
          'Write them accordingly. The software, its design and its documentation stay ours; '
          'you get the right to use the service for the term of the subscription, for running '
          'the hostel it was issued for.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Resident data, and what the hostel is responsible for',
      blocks: [
        Para(
          'If you run a hostel, you decide what personal data is collected about your residents '
          'and you are the Data Fiduciary for it. You are responsible for:',
        ),
        Bullets([
          'Giving residents notice and obtaining their consent before entering their details, '
              'including a parent or guardian\'s consent where a resident is a minor — the '
              'system holds no date of birth and cannot tell.',
          'Displaying a visible notice at the visitor desk, since a visitor whose name and '
              'phone number you log has no account and gets no notice from the app.',
          'Collecting only what you need, and preferring a non-Aadhaar identity document.',
          'Answering residents\' requests to see, correct or erase their data.',
          'Removing accounts for staff who leave.',
        ]),
        Para(
          'What you enter stays yours. You grant NIVORA only the permission needed to store it, '
          'show it to the people entitled to see it, and back it up. It is never sold, never '
          'shared with an advertiser and never used to train anything. NIVORA processes '
          'resident data only on the hostel\'s instructions — so a hostel that records data it '
          'had no lawful basis to hold, and is challenged over it, answers for that itself.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Subscription and payments',
      blocks: [
        Para(
          'A hostel\'s access depends on an active subscription, and the end date is enforced '
          'by the database rather than by the interface, so it behaves the same way everywhere. '
          'In the last fifteen days the workspace shows a renewal warning. Once it expires — or '
          'if the hostel is deactivated — the workspace becomes read-only: everyone can still '
          'sign in and read everything, and any attempt to record something is refused with an '
          'explanation. Nothing is deleted, and renewing makes it writable again immediately.',
        ),
        Para(
          'Rent is either recorded at the desk by a warden, or paid online through Razorpay on '
          'Razorpay\'s own checkout under Razorpay\'s terms. NIVORA never takes, holds, '
          'transfers or refunds money, and never sees a card number, UPI ID, CVV or bank '
          'account.',
        ),
        Para(
          'A receipt records what the hostel entered or what the gateway confirmed; it is not '
          'independent proof that money changed hands. If a receipt is wrong, the hostel '
          'corrects it. Refunds, deposits and disputes are between you and the hostel.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Availability, suspension and liability',
      blocks: [
        Para(
          'The service is provided as it is, without a guaranteed uptime figure or recovery '
          'time. It may be unavailable during maintenance or because something a third party '
          'runs has failed. Encrypted backups are taken nightly and kept for ninety days; they '
          'exist to recover the platform from a failure, not to replace records you are '
          'required to keep. To the fullest extent the law permits we exclude implied '
          'warranties, and we do not warrant that the records in the system are accurate — they '
          'are entered by the hostel\'s staff. Keep your own copy of anything you cannot afford '
          'to lose; a receipt can be shared from the app the moment it is issued.',
        ),
        Para(
          'An account or a whole workspace may be suspended for a breach of these terms, for '
          'non-payment of a subscription, after a security incident, or where leaving it open '
          'would put other people\'s data at risk. Where it is practicable and lawful the '
          'hostel is told first, and access is restored once the reason is resolved. A '
          'resident\'s account is normally closed by their hostel when they leave.',
        ),
        Para(
          'Neither side is liable for indirect or consequential loss, for lost profits, or for '
          'loss arising from information a user entered incorrectly. Our total liability is '
          'limited to the subscription fees paid for the twelve months before the claim, or a '
          'nominal amount where none were paid. Nothing here limits liability that cannot '
          'lawfully be limited, including fraud and death or personal injury caused by '
          'negligence.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Changes, governing law and contact',
      blocks: [
        Para(
          'Material changes bump the version and you are asked to accept again on your next '
          'visit; silence is not taken as agreement. This version: $kLegalVersion, effective '
          '$kLegalVersionLabel. If any part of these terms turns out to be unenforceable, the '
          'rest still stands.',
        ),
        Para(
          'These terms are governed by $kGoverningLaw, and the courts with jurisdiction are '
          '$kJurisdiction.',
        ),
        Rows([
          (term: 'Email', detail: kGrievanceEmail),
          (term: 'Post', detail: kPostalAddress),
        ]),
        Para('The published copy of these terms is at:'),
        Para(kTermsUrl),
      ],
    ),
  ],
);
