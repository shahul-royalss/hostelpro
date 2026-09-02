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
/// accept — so the wrong order locks every account out of the product. See
/// db/migrations/2026-09-02-legal-consent.sql §4.
///
/// test/legal_consent_test.dart asserts (1) and (2) against each other, so the pair cannot
/// drift silently. Nothing in Dart can check (3) — that one is the deployment order above.
library;

/// The published version of the Terms of Use + Privacy Policy pair that this build shows.
///
/// One string covers BOTH documents: they are presented together and agreed to together, so
/// there is no state in which a person is half-agreed.
const kLegalVersion = '2026-09-02';

/// Human-readable form of [kLegalVersion], for the "last updated" line.
const kLegalVersionLabel = '2 September 2026';

const kTermsUrl = 'https://hostelpro-three.vercel.app/legal/terms';
const kPrivacyUrl = 'https://hostelpro-three.vercel.app/legal/privacy';
const kDeletionUrl = 'https://hostelpro-three.vercel.app/legal/account-deletion';

/// ═══ VALUES THE OPERATOR OWNS, NOT THE ENGINEER ═══
///
/// These MIRROR `lib/legal-config.ts` at the repository root and must be changed in both places
/// at once. They are real-world facts about the business that cannot be derived from the
/// codebase, and every one of them is still awaiting confirmation from the owner — see
/// docs/legal-consent.md §6, which lists exactly what must be verified before the privacy-policy
/// URL is pasted into Play Console.
///
/// Nothing here was invented for the sake of filling a field. Where a value is not yet
/// confirmed it stays as the operator last set it rather than being replaced by something
/// plausible, because a plausible wrong address in a privacy policy is worse than an obviously
/// unfinished one: it silently swallows the requests it was published to receive.
const kOperatorName = 'NIVORA';
const kGrievanceOfficer = 'Shaik.Shahul';
const kGrievanceEmail = 'support@nivora.dhrishtaerf.org';
const kPostalAddress = 'RVS Nagar, Chittoor, Andhra Pradesh, India';
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
// PRIVACY POLICY
// ─────────────────────────────────────────────────────────────────────────────
//
// EVERY FACTUAL CLAIM BELOW WAS READ OUT OF THE CODEBASE, not assumed. The field lists come
// from db/schema.sql, the buckets from lib/storage.ts, the region from docs/server-health.md
// (`ap-southeast-1`), the sub-processors from what the project actually calls, and the
// retention periods from app.apply_retention() plus the schedule in
// docs/data-retention-and-privacy.md §5.2. If any of those change, this changes with them and
// the version bumps.

const kPrivacyPolicy = LegalDocument(
  id: 'privacy',
  title: 'Privacy Policy',
  tagline: 'What NIVORA holds about you, why, who can see it, and how to have it erased.',
  url: kPrivacyUrl,
  sections: [
    LegalSection(
      heading: 'Who is responsible for your data',
      blocks: [
        Para(
          'NIVORA is software used by a hostel or PG operator to run their building. The '
          'operator — the hostel you live in or work for — decides what to collect about you '
          'and why. In the language of the Digital Personal Data Protection Act 2023 they are '
          'the Data Fiduciary and NIVORA is the Data Processor acting on their instructions.',
        ),
        Para(
          'What this means in practice: a request to see, correct or erase your data is '
          'answered by your hostel. NIVORA\'s job is to make sure they can answer it. If you '
          'cannot get a response from them, the contact at the end of this policy will reach '
          'NIVORA directly.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Nobody signs themselves up',
      blocks: [
        Para(
          'There is no public registration in this app. Every account is created by somebody '
          'above it: the platform creates hostel owners, an owner creates their manager and '
          'warden, and a warden registers residents. You were given a temporary password and '
          'asked to change it on first sign-in.',
        ),
        Para(
          'That is why this policy matters more than it would for an app you chose to install: '
          'most of the information here was typed in by a member of hostel staff, from '
          'documents you handed them at the desk.',
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
                'notes a warden adds to a receipt. Where rent is paid online, the payment '
                'reference issued by the payment gateway.',
          ),
          (
            term: 'Things you raise',
            detail: 'Complaints — the title, description and any photograph you attach — and '
                'the history of who changed their status. Leave requests, including the reason '
                'you give.',
          ),
          (
            term: 'Visitors',
            detail: 'If a visitor is logged at the desk, their name, phone number, relation to '
                'you and their check-in and check-out times.',
          ),
          (
            term: 'Security records',
            detail: 'A log of significant actions — sign-ins, account changes, money recorded — '
                'with the IP address and browser or device description of the request.',
          ),
          (
            term: 'Your agreement to this policy',
            detail: 'When you accepted these documents, which version you accepted, and whether '
                'you were using the app or the website. This record exists because consent that '
                'cannot be evidenced is not consent.',
          ),
        ]),
      ],
    ),
    LegalSection(
      heading: 'What is never collected',
      blocks: [
        Bullets([
          'No advertising identifiers, and no advertising of any kind.',
          'No analytics, no behavioural profiling and no tracking across other apps or sites.',
          'No location data. The app never asks for your location and could not use it.',
          'No contacts, no calendar, no microphone.',
          'No card number, UPI ID, CVV or bank account. Where rent is paid online those details '
              'are typed into the payment gateway\'s own screen and never reach NIVORA at all. '
              'What comes back is a reference saying a payment of a certain amount succeeded.',
          'No password. Your password is stored only as a one-way hash by the authentication '
              'service and cannot be read by NIVORA, by your hostel, or by us.',
        ]),
      ],
    ),
    LegalSection(
      heading: 'Photographs and identity documents',
      blocks: [
        Para(
          'Your photo and ID scan are held in private storage. They are never public, never '
          'linked from a shareable address, and are reachable only through a short-lived link '
          'generated for a specific member of your hostel\'s staff at the moment they open it — '
          'fifteen minutes for identity documents.',
        ),
        Para(
          'A note on Aadhaar specifically. Aadhaar is governed by its own law and UIDAI '
          'guidance restricts holding copies of the Aadhaar letter. If your hostel asks for an '
          'ID, you may offer a different one, or a masked Aadhaar where that is accepted. '
          'NIVORA does not require Aadhaar and does not treat it differently from any other '
          'document you present.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Why it is held',
      blocks: [
        Bullets([
          'To run the residency: allocate a bed, record the rent, answer a complaint, approve '
              'leave, and know who is in the building.',
          'To meet the hostel\'s own legal duties, particularly keeping accounting records of '
              'money received.',
          'To keep the account secure — the security log exists so that a compromised account '
              'can be investigated, and for no other purpose.',
        ]),
        Para(
          'None of it is used to profile you, to advertise to you, or to make an automated '
          'decision about you. There is no automated decision-making in NIVORA.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Who can see it',
      blocks: [
        Para(
          'Only the staff of the hostel you belong to. This is enforced by the database itself '
          'through row-level security, evaluated against your signed-in identity on every '
          'single request — it is not a filter the app applies and could forget. One hostel '
          'cannot read another hostel\'s residents even if its own software asked.',
        ),
        Bullets([
          'You can see your own record, your own fees, your own complaints and your own notices.',
          'Your warden and manager can see the residents of their hostel.',
          'The owner can see their hostels.',
          'A platform super administrator can reach tenant records for support and billing. '
              'This is logged.',
          'Other residents cannot see anything about you. There is no directory and no resident '
              'list in the resident app.',
        ]),
      ],
    ),
    LegalSection(
      heading: 'Where it is stored, and who else touches it',
      blocks: [
        Para(
          'The database and file storage are hosted by Supabase in the ap-southeast-1 region — '
          'Singapore. Data is encrypted in transit and at rest.',
        ),
        Para('The complete list of companies that process any part of it:'),
        Rows([
          (
            term: 'Supabase',
            detail: 'The database, file storage and sign-in service. Holds everything above.',
          ),
          (
            term: 'Vercel',
            detail: 'Serves the web application. Sees requests in transit and keeps short-lived '
                'operational logs.',
          ),
          (
            term: 'Razorpay',
            detail: 'Only where rent is paid online. Receives your name, email, phone and the '
                'amount so it can take the payment, and holds its own record of the '
                'transaction under its own policy. It never sends card or UPI details back.',
          ),
          (
            term: 'Google (Gmail)',
            detail: 'Delivers the small number of emails the system sends — a verification '
                'link, a password reset. Sees your email address and the message.',
          ),
        ]),
        Para(
          'That is the whole list. There is no analytics vendor, no advertising network, no '
          'crash-reporting service and no customer-messaging tool in the picture.',
        ),
      ],
    ),
    LegalSection(
      heading: 'How long it is kept',
      blocks: [
        Rows([
          (
            term: 'While you live there',
            detail: 'Your record is kept for as long as you are a resident.',
          ),
          (
            term: 'After you leave',
            detail: 'Your resident record, and your photograph and ID document with it, are '
                'erased one month after your departure is recorded.',
          ),
          (
            term: 'Complaints and notices',
            detail: 'Two months, after which they are deleted along with their history.',
          ),
          (
            term: 'Notifications you have read',
            detail: 'Ninety days.',
          ),
          (
            term: 'Security log',
            detail: 'The IP address and device description are erased after ninety days, and '
                'the entry itself after a year.',
          ),
          (
            term: 'Payment history',
            detail: 'Kept permanently. This is the one exception and it is not ours to waive: '
                'a hostel has a statutory duty to keep records of money received, and those '
                'duties run for years. What is kept is the transaction, not your ID document.',
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
          'days later. Backups are never browsed; they exist to restore the system after a '
          'failure. Most policies leave this out — it is stated here because it is true.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Your rights',
      blocks: [
        Para(
          'Under the DPDP Act 2023 you may ask for a summary of the data held about you, ask '
          'for it to be corrected, completed or erased, nominate someone to exercise these '
          'rights if you are unable to, and complain. Where the GDPR or UK GDPR applies to you, '
          'you additionally have rights of access, portability, restriction and objection, and '
          'the right to complain to your supervisory authority.',
        ),
        Para(
          'Ask your hostel first — they hold the relationship and they can act immediately. If '
          'that does not work, write to the Grievance Officer below. A request will be answered '
          'within thirty days.',
        ),
        Para(
          'Correcting something is usually faster than you expect: a wrong phone number or a '
          'misspelled name is a change your warden can make while you stand there.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Erasing your account',
      blocks: [
        Para(
          'Nobody can delete their own account from inside the app, and that is deliberate '
          'rather than an omission. Your record is tied to a bed you may still be occupying and '
          'to a fee ledger the hostel is required to keep, and a deletion accepted on the spot '
          'in someone else\'s name would be a way to attack them.',
        ),
        Para(
          'So a deletion is a request, confirmed with you, and then carried out. Residents can '
          'file one from More, then My details. Anyone can file one from the public page at:',
        ),
        Para(kDeletionUrl),
        Para(
          'What is erased: your name, phone, email, address, guardian details, photograph and '
          'ID document, complaints, leave records and login. What survives, with your name '
          'removed from it where possible: the fee ledger, for the statutory period described '
          'above. A policy that promises total erasure and then quietly keeps the accounts is '
          'worse than one that tells you where the line is.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Children',
      blocks: [
        Para(
          'Hostel and PG residents in India are sometimes under eighteen. NIVORA does not record '
          'anyone\'s date of birth and therefore cannot tell. The Act requires a parent or '
          'guardian to consent for a child, and because the software cannot identify who that '
          'applies to, your hostel must obtain that consent in their own registration paperwork.',
        ),
        Para(
          'What the absence of an age field does guarantee is that the Act\'s prohibitions are '
          'satisfied outright: there is no tracking, no behavioural monitoring and no '
          'advertising directed at anybody, of any age.',
        ),
      ],
    ),
    LegalSection(
      heading: 'If something goes wrong',
      blocks: [
        Para(
          'If personal data is exposed, NIVORA notifies the affected hostel operator without '
          'delay and assists them in notifying the Data Protection Board and the people '
          'affected, as the Act requires of them.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Changes to this policy',
      blocks: [
        Para(
          'When this policy changes materially, its version changes, and you are asked to read '
          'and accept it again the next time you open the app. You will not be quietly moved '
          'onto a new policy you never saw.',
        ),
        Para('This version: $kLegalVersion, effective $kLegalVersionLabel.'),
      ],
    ),
    LegalSection(
      heading: 'Contact',
      blocks: [
        Rows([
          (term: 'Grievance Officer', detail: kGrievanceOfficer),
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
// TERMS OF USE
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
          'These terms are between $kOperatorName, which provides NIVORA, and you — whether you '
          'are a hostel owner who subscribes to it, a manager or warden given an account by an '
          'owner, or a resident given an account by a warden.',
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
          'residents, rent due and rent received, complaints, leave, visitors, notices, meals '
          'and staff tasks. It is a record-keeping tool.',
        ),
        Para(
          'It is not an accounting package, not a legal or tax adviser, and not a substitute '
          'for the agreement between you and your hostel. The rent, the deposit, the notice '
          'period and the house rules are matters between the resident and the operator; NIVORA '
          'only records what they tell it.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Accounts are issued, not registered',
      blocks: [
        Para(
          'There is no self sign-up. Your account was created for you and comes with a '
          'temporary password you are required to change when you first sign in.',
        ),
        Bullets([
          'Keep your password to yourself. Anything done with your account is treated as done '
              'by you.',
          'Owners, managers and platform administrators must set up two-factor authentication. '
              'This is not optional for those roles.',
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
          'Enter information you know to be false — a fabricated payment, an invented complaint '
              'against another resident, or someone else\'s identity document.',
          'Try to reach data belonging to another hostel or another person, or probe the '
              'service for ways to do so.',
          'Upload anything unlawful, or a photograph of a person taken without their knowledge.',
          'Use the service to harass anybody.',
          'Copy, resell or reverse-engineer the software, or use automated means to extract '
              'data from it in bulk.',
        ]),
        Para(
          'Complaints and notices are read by staff and, in the case of notices, by every '
          'resident in the audience. Write them accordingly.',
        ),
      ],
    ),
    LegalSection(
      heading: 'The operator\'s responsibilities',
      blocks: [
        Para(
          'If you run a hostel, you decide what personal data is collected about your '
          'residents, and you are the Data Fiduciary for it. You are responsible for:',
        ),
        Bullets([
          'Giving residents notice and obtaining their consent before entering their details, '
              'including a parent or guardian\'s consent where a resident is a minor.',
          'Displaying a visible notice at the visitor desk, since a visitor whose name and '
              'phone number you log has no account and gets no notice from the app.',
          'Only collecting what you actually need, and preferring a non-Aadhaar identity '
              'document.',
          'Answering residents\' requests to see, correct or erase their data, and passing on '
              'anything you need help with.',
          'Removing accounts for staff who leave.',
        ]),
      ],
    ),
    LegalSection(
      heading: 'Content you put in',
      blocks: [
        Para(
          'What you enter stays yours. You grant NIVORA only the permission needed to store it, '
          'display it to the people entitled to see it, and back it up. It is never sold, never '
          'shared with an advertiser, and never used to train anything.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Subscription, and what happens when it lapses',
      blocks: [
        Para(
          'A hostel\'s access depends on an active subscription. When one expires the hostel '
          'becomes read-only: everything can still be read, and nothing further can be '
          'recorded, until it is renewed. Data is not deleted when a subscription lapses.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Payments',
      blocks: [
        Para(
          'Rent can be recorded at the desk by a warden, or paid online through the payment '
          'gateway. Where it is paid online, the gateway takes the money — NIVORA never holds '
          'your funds and never sees your card, UPI or bank details.',
        ),
        Para(
          'A receipt in NIVORA records what the hostel entered or what the gateway confirmed. '
          'If a receipt is wrong, it is the hostel that corrects it. Refunds, deposits and '
          'disputes are between you and the hostel.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Availability and support',
      blocks: [
        Para(
          'The service is provided as it is, without a guaranteed uptime figure. It may be '
          'unavailable during maintenance or because something a third party runs has failed. '
          'Encrypted backups are taken nightly and kept for ninety days.',
        ),
        Para(
          'Keep your own copy of anything you cannot afford to lose. A receipt can be shared '
          'from the app the moment it is issued.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Suspension',
      blocks: [
        Para(
          'An account may be suspended for a breach of these terms, for non-payment of a '
          'subscription, or where leaving it open would put other people\'s data at risk. A '
          'resident\'s account is normally closed by their hostel when they leave.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Liability',
      blocks: [
        Para(
          'NIVORA is not liable for indirect or consequential loss, for lost profits, or for '
          'loss arising from information that a user entered incorrectly. Nothing in these '
          'terms limits liability for anything that cannot lawfully be limited, including fraud '
          'and death or personal injury caused by negligence.',
        ),
        Para(
          'Because NIVORA processes resident data on a hostel\'s instructions, a hostel that '
          'collects data without notice or consent, and is challenged over it, answers for that '
          'itself.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Changes to these terms',
      blocks: [
        Para(
          'Material changes bump the version and you are asked to accept again on your next '
          'visit. Continuing to use the app after accepting is what makes the new version '
          'binding — silence is not taken as agreement.',
        ),
        Para('This version: $kLegalVersion, effective $kLegalVersionLabel.'),
      ],
    ),
    LegalSection(
      heading: 'Governing law',
      blocks: [
        Para('These terms are governed by $kGoverningLaw, and the courts with jurisdiction are '
            '$kJurisdiction.'),
      ],
    ),
    LegalSection(
      heading: 'Contact',
      blocks: [
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
