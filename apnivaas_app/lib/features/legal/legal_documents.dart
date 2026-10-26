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
/// accept — so the wrong order locks every account out of the product: Agree fails with 22023
/// "Unknown legal document version" and Sign out is the only way off the screen. The row for the
/// version below is db/migrations/2026-10-26-legal-version-round3.sql; the rule it has to
/// satisfy is db/migrations/2026-09-02-legal-consent.sql §4.
///
/// test/legal_consent_test.dart asserts (1) and (2) against each other, so the pair cannot
/// drift silently, and also checks [kLegalVersionLabel] against [kLegalVersion] and the
/// operator constants below against their web twins. Nothing in Dart can check (3) — that one is
/// the deployment order above.
library;

/// The published version of the Terms of Use + Privacy Policy pair that this build shows.
///
/// One string covers BOTH documents: they are presented together and agreed to together, so
/// there is no state in which a person is half-agreed. A plain YYYY-MM-DD date, always — the web
/// pages parse the same string for their "Last updated" line.
///
/// 2026-10-12 gave the product its current name, Apnivaas, and named ShaReshi Tech as the
/// operator.
///
/// 2026-10-17 added "Continue with Google": who may use it, what Google shares, and Google's
/// third job as a recipient. Row: db/migrations/2026-10-17-legal-version-google.sql, which must
/// be live before any build carrying this string reaches anybody.
///
/// 2026-10-25 added self sign-up (Google; Facebook and Truecaller once switched on), profile
/// photos, identity documents, the tenant's own details, approximate location for "PGs near
/// you", the PG's position, join requests, demo requests and Razorpay plan payments, and moved
/// the permission count to eleven. Row: db/migrations/2026-10-25-legal-version-signup.sql.
///
/// 2026-10-26 (round 3) added email and password sign-up, staff sign-up requests, precise
/// location, the on-device biometric lock, PG profiles and reviews, check-out requests, UPI rent
/// paid straight to the owner, and what a permanent deletion keeps; the permission count went to
/// thirteen. Row: db/migrations/2026-10-26-legal-version-round3.sql.
const kLegalVersion = '2026-10-26';

/// Human-readable form of [kLegalVersion], for the "last updated" line.
const kLegalVersionLabel = '26 October 2026';

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
///
/// THE OPERATOR IS AN ENTITY, THE PRODUCT IS A NAME, and the two are not interchangeable.
/// [kOperatorName] is the party to the Terms and the developer name on the Play listing; Play's
/// User Data policy wants the privacy policy to name that entity, and until 2026-10-12 this held
/// the product's old name in capitals, which is neither. [kLegalProductName] is what the app is called, written exactly as
/// in the logo — never upper-cased. Both mirror `LEGAL.operatorName` / `LEGAL.productName`.
const kOperatorName = 'ShaReshi Tech';
const kLegalProductName = 'Apnivaas';
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
// and leave-request periods that nothing enforced are gone.
//
// The in-app "Delete my account and data" control (features/legal/account_deletion.dart, added
// 2026-09-13) is named below from version 2026-09-13, which changed this text anyway to correct
// the permission list and to describe what Razorpay's in-app checkout handles.
//
// Version 2026-10-12 changed the product's name (to Apnivaas, through [kLegalProductName])
// and named the operator, ShaReshi Tech, in section 1 and beside the terms' contact details. No
// claim about data changed with it, which is what that version's legal_versions summary says.

const kPrivacyPolicy = LegalDocument(
  id: 'privacy',
  title: 'Privacy Policy',
  tagline: 'What $kLegalProductName holds about you, why, who can see it, and how to have it '
      'erased.',
  url: kPrivacyUrl,
  sections: [
    LegalSection(
      heading: 'Who this policy is from, and how accounts work',
      blocks: [
        Para(
          '$kLegalProductName is software used by a hostel or PG operator to run their building. '
          'The operator decides what to collect about you and why; $kLegalProductName stores and '
          'processes it on their instructions. In the language of the Digital Personal Data '
          'Protection Act 2023 your hostel is the Data Fiduciary and $kLegalProductName is the '
          'Data Processor. So a request to see, correct or erase your data is answered by your '
          'hostel first. For platform staff accounts and the security log, $kLegalProductName is '
          'the Data Fiduciary itself — and so it is for an account you create yourself, with '
          'the photo, details and documents you add to it, the PGs you ask to join, a demo you '
          'book and a plan you pay for, until a PG accepts you as its resident or its staff.',
        ),
        Para(
          '$kLegalProductName is operated by $kOperatorName. Wherever this policy says that '
          '$kLegalProductName does something, or says we or us, it means $kOperatorName.',
        ),
        Para(
          'Accounts are made in two ways. An owner, a tenant or a member of staff may create '
          'their own account in the Android app, with their email address and a password or '
          'with Continue with Google, and — only where the app offers them — Continue with '
          'Facebook or Continue with Truecaller. A staff sign-up has no access to anything: it '
          'is a request to join a PG, and only that PG\'s owner can accept it and make the '
          'person its manager or warden. Otherwise accounts are made '
          'by people: the platform creates hostel owners, and a warden registers residents, who '
          'sign in with the phone number their hostel registered — which is why changing it is '
          'something staff do rather than a profile edit. An account made by people comes with '
          'a temporary password that must be changed at first sign-in; passwords are hashed by '
          'the sign-in service and are never seen by $kLegalProductName, by your hostel or by '
          'us.',
        ),
        Para(
          'Owners and residents whose login is an email address that is also a Google account '
          'may sign in with Continue with Google instead of their password. A manager or warden '
          'an owner created, and every platform administrator, cannot use Google, Facebook or '
          'Truecaller: the database refuses it, and they sign in only with the login they were '
          'given. A manager or warden who signed up themselves may keep using the sign-in they '
          'signed up with.',
        ),
        Para(
          'If a hostel registered you, most of what is here was typed in by its staff, from '
          'documents you handed them at the desk. If you made your own account, it is what you '
          'typed and uploaded yourself.',
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
            term: 'Google sign-in',
            detail: 'Only if you use Continue with Google: your Google account ID, and the name, '
                'email address and profile photo link Google shares when you sign in. They are '
                'kept by the sign-in service with your login and used only to sign you in. '
                'Nothing is posted to your Google account and nothing else is read from it.',
          ),
          (
            term: 'Facebook or Truecaller sign-in',
            detail: 'Only where the app offers it and you choose it. Facebook: your Facebook user '
                'ID, name and email address if it shares one. Truecaller: your Truecaller ID, the '
                'phone number Truecaller has verified, and your name. The ID is kept with your '
                'login and used only to sign you in; nothing is posted and nothing else is read.',
          ),
          (
            term: 'Email and password sign-up',
            detail: 'If you sign up with a password: your name, phone number, email address and, '
                'for an owner or a tenant, your city and pincode. The password is hashed by the '
                'sign-in service, and your email address is confirmed by a link.',
          ),
          (
            term: 'Your own details',
            detail: 'If you sign up as a tenant: gender, date of birth, and an emergency '
                'contact\'s name and phone number, which you type in yourself and can change.',
          ),
          (
            term: 'Profile photo',
            detail: 'A photo you choose for your account, from the camera or your gallery, '
                'cropped square and reduced to at most 512 pixels. Any role may add one.',
          ),
          (
            term: 'Resident details',
            detail: 'Permanent address, guardian\'s name and phone number, date of joining, '
                'monthly fee, the room and bed assigned to you, and whether you are active, on '
                'leave or vacated.',
          ),
          (
            term: 'Photograph and identity document',
            detail: 'A photo and a scan of the ID proof you presented at registration, or the '
                'identity documents you upload yourself (a masked Aadhaar, PAN, driving licence, '
                'voter ID, passport, college or work ID) with the kind of each. This is the most '
                'sensitive thing in the system and it is treated as such — see below.',
          ),
          (
            term: 'Join requests',
            detail: 'When a tenant asks to join a PG: which PG, an optional message, when it was '
                'sent, and the answer — accepted, declined with an optional note, cancelled or '
                'lapsed — with who gave it.',
          ),
          (
            term: 'Staff requests',
            detail: 'When someone who signed up as staff asks to join a PG: which PG, an optional '
                'message, when, and the owner\'s answer — the role given, or a note on declining.',
          ),
          (
            term: 'Check-out requests',
            detail: 'When a tenant asks to check out: the preferred date, an optional reason, and '
                'the warden\'s answer — the check-out date, or a note on declining.',
          ),
          (
            term: 'Your PG',
            detail: 'If you are an owner: the PG\'s name, type, who it is for, address, locality, '
                'city and pincode, its floors and rooms, and — only if you set it — its exact '
                'position on the map, from your phone\'s precise location or a pin you place. '
                'Also its profile: a logo, up to six cover photos, a description, amenities and '
                'house rules.',
          ),
          (
            term: 'Reviews',
            detail: 'A current tenant may rate their PG from 1 to 5 with an optional comment. '
                'The review is stored with your account and shown with your first name.',
          ),
          (
            term: 'Plan payments and demo requests',
            detail: 'If you are an owner: the plan you paid for, the amount, the method, the '
                'Razorpay order and payment references and whether it succeeded; and, if you book '
                'a demo, the name, phone number, PG name, city, size and time slot you give.',
          ),
          (
            term: 'Money',
            detail: 'Rent due from your check-in date, rent paid, the date and method of each '
                'payment, and free-text notes a warden adds to a receipt. Where rent is paid '
                'online, the reference the payment gateway issues.',
          ),
          (
            term: 'UPI rent payments',
            detail: 'An owner\'s UPI ID and payee name, which the tenants of that PG can see. '
                'When a tenant pays by UPI: the amount, the month, the UTR (transaction ID) they '
                'enter, and whether staff confirmed or rejected it, with any note.',
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
            term: 'Notification device',
            detail: 'When you sign in on a phone, a Firebase registration token identifying that '
                'handset, which platform it runs, and when it was first and last seen. It is '
                'registered whether or not you allow notifications to be shown, so that turning '
                'them on later works at once; it is released when you sign out, removed if your '
                'account is deleted, and dropped automatically after 90 days without use.',
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
                'readable phone number. Also a list of deleted accounts: who, their role and '
                'PG, when, by whom and why.',
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
          'No date of birth from anybody a hostel registers. Only a tenant who signs up gives '
              'one, on their own details form; nothing in $kLegalProductName uses it to decide '
              'anything about them.',
          'No card number, CVV or bank account, and no tenant\'s UPI ID, is ever received or '
              'stored by $kLegalProductName. '
              'Where rent is paid online those details are typed into Razorpay\'s checkout, which '
              'on Android runs inside this app, and go to Razorpay (see Razorpay below). What '
              'comes back is a reference saying a payment of a stated amount succeeded. A UPI '
              'payment to the owner is made in your own UPI app, straight to the owner\'s UPI '
              'ID: $kLegalProductName never receives or holds that money, and stores only the '
              'UTR, amount and month you enter.',
          'No location history, and no contacts, calendar, microphone or biometric data. The '
              'Android app declares thirteen permissions and no others. Seven are '
              '$kLegalProductName\'s own: internet access; the ability to tell whether you are '
              'online; the camera, used only when you choose to take a photo of yourself, an '
              'identity document, a resident, a receipt or your PG; permission to show '
              'notifications; precise location and approximate location (Android lets you choose '
              'which to give), asked for in words first and used only when you tap "PGs near '
              'you" or set your PG\'s position; and the biometric permission, used only by the '
              'optional app lock. Four more are added by the libraries that '
              'deliver notifications and '
              'run the app: waking the device, vibrating, receiving a message, and an internal '
              'permission only this app can hold. The last two come from Razorpay\'s checkout: '
              'NFC, so a payment card can be tapped, and a basic phone-state permission; '
              '$kLegalProductName reads neither. The advertising-ID permission is removed from the '
              'app explicitly.',
          'No advertising, no advertising identifier and no profiling. Nothing here is used to '
              'build a picture of you or to make an automated decision about you.',
          // NOT "there is no third-party tracking code in the app". That sentence was true of the
          // WEBSITE and was copied here while the two documents were being harmonised, which made
          // it false of the thing a resident actually installs: this app bundles razorpay_flutter,
          // Razorpay's native Checkout SDK, and docs/play-submission-pack.md §2.9 records that it
          // runs its own device and session telemetry during a payment — which is why the Data
          // Safety form declares "Device or other IDs · Fraud prevention". A policy the user must
          // accept cannot contradict the form the same app files. On the web that SDK at least
          // runs inside a cross-origin iframe; here it runs in-process, so the claim was weaker
          // still. What is true, and is what this now says, is that none of it is ours and none of
          // it reaches us.
          'No analytics, session replay or crash reporting of our own, no advertising, and no '
              'tracking across other apps or sites. Razorpay\'s checkout runs its own device and '
              'session checks while a payment is open, for its own fraud prevention; '
              '$kLegalProductName receives none of it.',
          'No marketing cookies. The only cookies are the session cookies that keep you signed '
              'in, read by the server alone.',
          'No SMS, no marketing email and no mailing list. The only emails sent are the ones '
              'that keep the account working — a confirmation link, a password reset.',
          'No location history and no tracking. Your precise location is read once, when you '
              'ask for PGs near you, sent to the server only to measure distances, and not saved '
              '— not with your account, not in the security log. An owner\'s PG position is '
              'different: that is saved, as the PG\'s location.',
          'No fingerprint, face or PIN. The optional app lock — on by default for owners — asks '
              'your phone\'s own screen lock to check it is you. That check happens on the phone; '
              'nothing biometric reaches $kLegalProductName, and whether the lock is on is kept '
              'only on the phone.',
          'No notification content beyond what you already see in the app. Push notifications '
              'ARE sent — see "What is collected" above for the device registration they '
              'require, and section 6 for the part Google plays in delivering them.',
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
          'their actual leading bytes rather than their file name, and capped at 3 MB in the '
              'app (8 MB on the website, which uploads by a different route).',
        ),
        Para(
          'Profile photos and the identity documents you upload yourself are kept in two more '
          'private stores, each file filed under your own account, and only you can add one. A '
          'profile photo can be seen by you; the owner of your PG; its wardens; its managers, '
          'except a resident\'s photo; and the owner and wardens of a PG you have asked to '
          'join, while the request is open. An identity document can be seen by you, the owner '
          'and wardens of your PG — never a manager — and the owner and wardens of a PG you have '
          'asked to join, while the request is open. Platform administrators can see both, for '
          'support. Other residents never can. Each is shown through a link that lasts one '
          'minute. A photo is at most 1 MB; a document at most 5 MB, as an image or a PDF.',
        ),
        Para(
          'The copy on your phone is not kept after an identity document is uploaded. A new '
          'profile photo replaces the old one, which is deleted. When you leave a PG, its staff '
          'lose access to your photo and documents. Both are deleted with your account, and '
          'anything uploaded but never saved to your account is deleted after a day.',
        ),
        Para(
          'A PG\'s logo and cover photos are different: they are meant to be seen. They are '
          'held in private storage under the PG, only its owner can add them, and they can be '
          'opened by its own people and by anyone signed in while the PG is listed and its plan '
          'or free month is running. Do not put people in them.',
        ),
        Para(
          'A note on Aadhaar. Aadhaar is governed by its own law and UIDAI guidance restricts '
          'holding copies of the Aadhaar letter. $kLegalProductName does not require Aadhaar and '
          'does not '
          'treat it differently from any other document; if your hostel asks for an ID you may '
          'offer a different one, or a masked Aadhaar where that is accepted. If you upload one '
          'yourself, upload a masked Aadhaar — downloaded from UIDAI with only the last four '
          'digits showing — or a different document. A hostel can also '
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
              'administration of the subscription, including a plan an owner pays for and a demo '
              'an owner asks for.',
          'An account you create yourself — your consent, given when you sign up and agree to '
              'this policy, to run the account, find you a PG, send your join or staff request '
              'to the PG you chose, and let that PG check who you are. Your location is used '
              'only on the occasion you ask for it. A review is published because you chose to '
              'write it.',
          'The security log — $kLegalProductName\'s own interest in keeping the system secure '
              'and being able to investigate a compromised account. It exists for that and '
              'nothing else.',
        ]),
        Para(
          'Where consent is the basis it can be withdrawn, though withdrawing it may mean the '
          'hostel can no longer accommodate you, because it can no longer keep the record it '
          'needs to. There is no profiling and no automated decision-making in '
          '$kLegalProductName.',
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
          'When you ask to join a PG, its owner and wardens see your name, phone number, email '
              'address, gender, date of birth, emergency contact and message, and can open your '
              'photo and identity documents until they answer. The request stays in their list '
              'until it is deleted. If they accept, they become your PG.',
          'When a staff applicant asks to join a PG, its owner sees their name, phone number, '
              'email address and message, and chooses whether to make them its manager or warden.',
          'A tenant\'s check-out request is seen by the wardens and the owner of their PG.',
          'Anyone signed in who is looking for a PG sees its name, type, who it is for, '
              'locality, city, distance, logo, cover photos, description, amenities, house rules, '
              'rating and reviews, each review with the reviewer\'s first name — never its full '
              'address, its map position or the owner\'s contact details. A PG appears while it '
              'is listed and its plan or free month is running. The owner can read reviews but '
              'not change or remove them.',
          'The tenants of a PG see its UPI ID and payee name, so they can pay. A UPI payment '
              'they submit is seen by its wardens and owner, who confirm or reject it.',
          'A demo you book is seen by you and by the platform\'s own staff, who call you to '
              'arrange it.',
          'A manager sees rooms, money and operations, and is cut off from resident personal '
              'data at the database layer.',
          'A platform administrator can reach tenant records for support and billing. Every '
              'such action is written to the security log.',
          'Other residents cannot see anything else about you. There is no resident directory.',
        ]),
        Para(
          'Outside your hostel, five companies process some part of it, and two more only if '
          'you choose to sign in with them. That is the complete list: no analytics vendor, no '
          'advertising network, no crash reporter, no messaging tool and no AI provider.',
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
            detail: 'Only where you choose to pay rent in the app, or an owner pays for a '
                '$kLegalProductName plan. Receives your name, email, phone and the amount. Its checkout runs inside this app on Android: while a '
                'payment is open it takes the card, UPI or netbanking details you type, and checks '
                'which UPI apps are installed so it can offer them. Those details go to Razorpay '
                'and never reach us. We get back the amount, the identifiers and the method. '
                'Razorpay keeps its own record under its own policy.',
          ),
          (
            term: 'Google',
            detail: 'Three jobs. It delivers the few account emails — a confirmation link, a '
                'password reset — and sees your email address and the message. Through Firebase '
                'Cloud Messaging it also delivers push notifications to your phone, and receives '
                'the phone\'s registration token and each notification\'s title and body. And if '
                'you choose Continue with Google, it confirms who you are when you sign in, so it '
                'learns that you signed in to this app.',
          ),
          (
            term: 'Meta (Facebook)',
            detail: 'Only if the app offers Continue with Facebook and you choose it. It confirms '
                'who you are and shares your Facebook user ID, name and email address; it learns '
                'that you signed in to this app.',
          ),
          (
            term: 'Truecaller',
            detail: 'Only if the app offers Continue with Truecaller and you choose it. It confirms '
                'your phone number and shares it with your name and Truecaller ID; it learns that '
                'you signed in to this app.',
          ),
        ]),
        Para(
          'Your location is worked out by your phone\'s own location service — on most Android '
          'phones that is Google Play services, under Google\'s own settings, which also shows '
          'the "Turn on location" prompt — and $kLegalProductName passes it to nobody. A UPI '
          'payment is handled by your own UPI app and bank, not by $kLegalProductName or any '
          'company named above.',
        ),
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
          'role and required for the roles that carry the most access; an optional app lock on '
          'the phone; a forced password change '
          'at first sign-in; the security log; TLS with strict transport security on every '
          'response; private storage with short-lived links; password hashes that never reach '
          'the application; login rate limiting keyed on an irreversible hash; and a strict '
          'content security policy. No system is perfectly secure and this policy does not '
          'claim otherwise — it claims these measures are in the product today.',
        ),
        Para(
          'If personal data is exposed, $kLegalProductName tells the affected hostel without '
          'delay and '
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
                'entries go at the same time, and so does a login the hostel made. A tenant who '
                'made their own account keeps it on leaving, so they can find another PG; the PG '
                'loses access to it at once.',
          ),
          (
            term: 'Profile photos and documents you upload',
            detail: 'Kept while your account exists and deleted with it. A replaced photo is '
                'deleted at once, and an upload never saved to an account after a day.',
          ),
          (
            term: 'Join requests',
            detail: 'A request nobody answers lapses after 30 days. An answered, cancelled or '
                'lapsed request is deleted 180 days later.',
          ),
          (
            term: 'Demo requests',
            detail: 'Deleted 180 days after the booked time slot, and with the owner\'s account.',
          ),
          (
            term: 'Your location',
            detail: 'Not kept at all. A PG\'s saved position stays with the PG.',
          ),
          (
            term: 'Staff requests',
            detail: 'Kept with the PG\'s records, and deleted with the applicant\'s account.',
          ),
          (
            term: 'Reviews and check-out requests',
            detail: 'A review stays after you leave the PG and is deleted with your account. A '
                'check-out request stays with the resident\'s record.',
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
            // A DISCLOSED CATEGORY NEEDS A STATED PERIOD. Section 2 lists staff tasks and mess
            // menus as personal data (a task names who it was assigned to), and the previous
            // policy published "24 months" for them — a period app.apply_retention() never
            // enforced. Deleting the false figure was right; leaving the category with no period
            // at all was not, because retention is one of the disclosures Play checks for. This
            // is what the code actually does: nothing ages them, and they go when the hostel does.
            term: 'Staff tasks and mess menus',
            detail: 'Kept for as long as the hostel keeps its workspace, and removed with it. '
                'The nightly job does not age these: a task names the staff member it was '
                'assigned to, and deleting it while they still work there would erase the '
                'operating history of the hostel itself.',
          ),
          (
            term: 'Fee, expense, revenue, UPI payment and plan payment records',
            detail: 'Kept indefinitely. This is the one exception and it is not ours to waive: '
                'a business has a statutory duty to keep records of money received. Where that '
                'collides with erasure the person is removed rather than the record — name, '
                'phone, email, photograph, guardian details, address and ID proof are stripped '
                'out and the figures are left attached to nobody.',
          ),
          (
            term: 'An account permanently deleted',
            detail: 'When the platform administrator permanently deletes an account, the login, '
                'profile details, photos, documents, reviews and requests are erased. Payments, '
                'receipts, dues and the security log are kept, for legal and accounting reasons, '
                'and show the person as "Deleted user".',
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
          'there. To be erased, ask them too: checking a resident out schedules the erasure, and '
          'it runs a month later. That month is fixed; it is not shortened on request.',
        ),
        Para(
          'Nothing erases your record on the spot, and that is deliberate rather than an '
          'omission: it is tied to a bed you may still be in and to a ledger the hostel must '
          'keep, and an erasure accepted instantly in someone else\'s name would be a way to '
          'attack them. So a deletion is a request, confirmed with you, and then carried out. '
          'In this app, open your profile — residents on the Profile tab, staff by tapping '
          'their picture at the top left — and choose Delete my account and data. Residents '
          'signed in on the website can file one from Profile. Anyone can file one from the '
          'public page at:',
        ),
        Para(kDeletionUrl),
        Para(
          'If your hostel does not answer, or the request is about the security log, a platform '
          'account, or an account you made yourself and is not in a PG, write to the Grievance '
          'Officer below — or file the same request in the app. Your own details and photo you '
          'can change in the app at any time.',
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
          'monitoring and advertising directed at children. $kLegalProductName does none of '
          'those things '
          'for anybody of any age, so those prohibitions are met by the way the product is '
          'built rather than by a promise.',
        ),
        Para(
          'Only a tenant who signs up gives a date of birth, and nothing checks it, so the '
          'system cannot tell who is a minor. Creating your own account is for people aged 18 '
          'or over. A resident under 18 is registered by their hostel, which must obtain a '
          'guardian\'s consent in its own registration paperwork first.',
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
  tagline: 'The rules for using $kLegalProductName, and what each side is responsible for.',
  url: kTermsUrl,
  sections: [
    LegalSection(
      heading: 'Who these terms bind',
      blocks: [
        Para(
          'These terms are between $kOperatorName (we, us), which provides this service, and '
          'you — whether you are a hostel owner who subscribes to it, a manager or warden given '
          'an account by an owner, a resident given an account by a warden, or an owner, tenant '
          'or member of staff who created their own account. Wherever these '
          'terms say that $kLegalProductName does something, they mean $kOperatorName.',
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
          '$kLegalProductName records and organises the running of a hostel or PG: rooms and beds, '
          'residents, rent due and rent received, complaints, leave, visitors, notices, meals, '
          'staff tasks and expenses, check-out requests, and a PG profile with photos and '
          'tenant reviews. A tenant\'s dues start from their check-in date. It is delivered as a '
          'website and an Android app, and needs an internet connection.',
        ),
        Para(
          'It is a record-keeping tool. It is not an accounting package, not a legal or tax '
          'adviser, and not a substitute for the agreement between you and your hostel. The '
          'rent, the deposit, the notice period and the house rules are matters between the '
          'resident and the operator; $kLegalProductName only records what they tell it.',
        ),
      ],
    ),
    LegalSection(
      heading: 'Your account',
      blocks: [
        Para(
          'An owner, a tenant or a member of staff may create their own account in the Android '
          'app, with an email address and a password, with Continue with Google or, where the '
          'app offers them, Continue with Facebook or Continue with Truecaller. You must be 18 or '
          'over to do so, and the details you give must be your own and true. A staff sign-up '
          'gets no access until the owner of the PG it asked to join accepts it and chooses the '
          'role; an owner may also create staff accounts. Any other account was '
          'created for you and comes with a temporary password you must change when you first '
          'sign in; owners and residents whose login is a Google account\'s address may also '
          'sign in with Continue with Google.',
        ),
        Para(
          'An account a hostel created belongs to the hostel\'s workspace rather than to you '
          'personally, and is deactivated when you check out or when your employment ends. An '
          'account you created stays yours when you leave a PG, and an owner may delete the '
          'account of a manager or warden who works for them.',
        ),
        Bullets([
          'Keep your password to yourself, and keep the Google account you sign in with secure '
              'if you use one. Anything done with your account is treated as done by you, '
              'because that is how the security log records it.',
          'Turn on two-factor authentication where it is offered. Where it is required for your '
              'role you will be asked to set it up before you can continue.',
          'Use the app lock where you can. It is on by default for owners, anyone may turn it on '
              'in Security, and it uses your phone\'s own fingerprint, face or screen lock.',
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
          'Use the visitor log, complaints, join requests or any other feature to harass '
              'anybody, or send a join request to a PG you do not mean to stay in.',
          'Upload an identity document that is not yours, or an Aadhaar that is not masked '
              'when a masked one would do.',
          'Write a review of a PG you have not stayed in, or one that is false or abusive; put '
              'people in a PG\'s photos without their agreement; or enter a UTR for a UPI '
              'payment you did not make.',
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
              'system does not check ages and cannot tell.',
          'Displaying a visible notice at the visitor desk, since a visitor whose name and '
              'phone number you log has no account and gets no notice from the app.',
          'Collecting only what you need, and preferring a non-Aadhaar identity document.',
          'Answering residents\' requests to see, correct or erase their data.',
          'Answering join requests honestly, and using a requester\'s photo and identity '
              'documents only to decide whether to accept them. Answering staff requests and '
              'check-out requests promptly.',
          'Keeping your PG profile, its photos and your UPI ID accurate, and confirming a UPI '
              'payment only after you have seen it arrive in your UPI app or bank.',
          'Removing accounts for staff who leave.',
        ]),
        Para(
          'What you enter stays yours. You grant $kLegalProductName only the permission needed to '
          'store it, show it to the people entitled to see it, and back it up. It is never sold, '
          'never shared with an advertiser and never used to train anything. $kLegalProductName '
          'processes resident data only on the hostel\'s instructions — so a hostel that records '
          'data it '
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
          'An owner who creates their own account gets their first PG free for one month, once. '
          'After that a plan is bought in the app: the plans and their prices are the ones the '
          'app shows at the time, set by us. The payment is taken by Razorpay in its own '
          'checkout and is paid to us. The plan starts only once our server has verified the '
          'payment with Razorpay, and adds its months to the end of the current plan. A plan '
          'does not renew by itself. If a payment went wrong, write to us at the contact below. '
          'A free demo you book is a request for a call from us, which we confirm or rearrange.',
        ),
        Para(
          'Rent is recorded at the desk by a warden, paid online through Razorpay on Razorpay\'s '
          'own checkout under Razorpay\'s terms, or paid by UPI from the tenant\'s own UPI app '
          'straight to the owner\'s UPI ID. A UPI payment counts as paid only when the owner or '
          'a warden confirms the UTR the tenant entered; the app never takes the phone\'s word '
          'for it. $kLegalProductName never takes, holds, transfers or refunds rent, and never '
          'sees a card number, CVV, bank account or the tenant\'s UPI ID — for rent or for a '
          'plan.',
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
          'resident\'s account is normally closed by their hostel when they leave, unless they '
          'created it themselves. When an account is permanently deleted, its payments, '
          'receipts, dues and security log entries are kept, marked "Deleted user", for legal '
          'and accounting reasons.',
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
          (term: 'Operator', detail: kOperatorName),
          (term: 'Email', detail: kGrievanceEmail),
          (term: 'Post', detail: kPostalAddress),
        ]),
        Para('The published copy of these terms is at:'),
        Para(kTermsUrl),
      ],
    ),
  ],
);
