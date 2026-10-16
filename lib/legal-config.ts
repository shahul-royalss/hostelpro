/**
 * The one file to fill in before publishing to Google Play.
 *
 * The privacy policy, terms and account-deletion pages are all public URLs that a Play reviewer
 * fetches WITHOUT signing in, and Play requires the policy to identify the operator and give a
 * contact that actually works. Until the placeholders below are replaced, those pages render a
 * visible "not ready to publish" notice — which is deliberate: shipping a policy that names no
 * responsible operator reads to a reviewer as an unfinished app.
 *
 * These are real-world facts about the business, so they cannot be derived from the codebase.
 * Replace every value marked PLACEHOLDER, then `isConfigured` flips to true on its own and the
 * notices disappear.
 *
 * `.invalid` is a reserved TLD (RFC 2606) that can never resolve. It is used on purpose so a
 * placeholder address can never silently swallow a real data-subject request.
 */

export const LEGAL = {
  /**
   * The entity that operates the product and is the party to the Terms — the developer name on
   * the Google Play listing. NEVER the product name: Play's User Data policy wants the privacy
   * policy to name the entity on the listing, and the DPDP Act wants a Data Fiduciary to
   * identify itself. Until 2026-10-12 this held the product's old name, which was neither.
   *
   * Printed as the operator on the privacy policy, as the party bound by the terms, and in the
   * copyright line of every legal page. Changing it changes both documents' wording, so it is a
   * version bump (LEGAL_VERSION below). If the registered form of the name carries a suffix
   * (a proprietorship's trade name, "LLP", "Private Limited"), it goes here exactly as registered.
   */
  operatorName: "ShaReshi Tech",

  /**
   * The product's name as users see it, title case exactly as in the logo: "Apnivaas" — never
   * "APNIVAAS" or "ApniVaas".
   *
   * The legal pages read THIS, not NEXT_PUBLIC_APP_NAME. An environment variable is set in a
   * hosting dashboard and fixed at build time, so reading it let a Vercel setting rewrite every
   * published legal page without a commit and without a version bump — text that people are
   * recorded as having agreed to must only ever change in git, together with LEGAL_VERSION.
   * Mirrored as `kLegalProductName` in apnivaas_app/lib/features/legal/legal_documents.dart.
   */
  productName: "Apnivaas",

  /** Monitored mailbox for privacy, grievance and data-deletion requests. */
  grievanceEmail: "support@nivora.dhrishtaerf.org",

  /** Monitored mailbox for legal/terms correspondence. May be the same as above. */
  legalEmail: "support@nivora.dhrishtaerf.org",

  /**
   * Postal address published on the legal pages. A locality, not a doorstep: the DPDP Act wants
   * a Data Fiduciary to be reachable, and the monitored mailbox above is the channel that
   * actually answers. A street-level home address on a public page is not reachability, it is
   * exposure — do not put one back.
   */
  postalAddress: "Chittoor, Andhra Pradesh, India",

  /**
   * The Grievance Officer the DPDP Act 2023 requires a Data Fiduciary to publish — named by
   * ROLE, not by person. Play needs a working contact and the Act needs a grievance contact; a
   * role title plus the monitored mailbox above satisfies both, and it does not go stale the
   * day somebody else takes the job. Do not replace this with an individual's name.
   */
  grievanceOfficer: "The Grievance Officer",

  /** e.g. "the laws of India". */
  governingLaw: "the laws of India",

  /** e.g. "the courts at Bengaluru, Karnataka". */
  jurisdiction: "the courts at Chittoor, Andhra Pradesh",

} as const;

/**
 * THE VERSION OF THE TERMS + PRIVACY PAIR THAT IS CURRENTLY PUBLISHED.
 *
 * One string covers both documents: they are presented together and agreed to together, so
 * there is no state in which somebody is half-agreed.
 *
 * ═══ THIS STRING LIVES IN THREE PLACES AND THEY MUST MOVE TOGETHER ═══
 *
 *   1. here                                                  — the published web pages
 *   2. apnivaas_app/lib/features/legal/legal_documents.dart     — `kLegalVersion`, what the
 *      Android app shows and what it records an acceptance against
 *   3. `public.legal_versions.version`                        — a migration; an acceptance may
 *      only name a version that exists there
 *
 * Change the wording of either document → bump all three → every user is asked to agree again,
 * because the app's consent gate compares the version it ships against the versions that user
 * has accepted. Leaving this behind means people are quietly moved onto text they never saw,
 * which is the one failure mode a consent record exists to make impossible.
 *
 * (1) and (2) are cross-checked by apnivaas_app/test/legal_consent_test.dart, so they cannot
 * drift silently. (3) is a deployment order, not a check: the migration publishing a version
 * row must land BEFORE an app build carrying that string, because `accept_legal_terms()`
 * refuses a version it has never heard of and at the gate the only thing a user may do is
 * agree.
 *
 * IT MUST STAY A PLAIN YYYY-MM-DD DATE. app/legal/layout.tsx formatDate() parses it for the
 * "Last updated" line, and a suffix such as "2026-10-12b" renders there as "Invalid Date".
 *
 * 2026-10-12: the product took its current name, Apnivaas, and ShaReshi Tech is named as the
 * operator. The row is db/migrations/2026-10-12-legal-version-apnivaas.sql, and it must be on
 * the live database BEFORE the website is pushed or any app build carrying this string reaches
 * anybody — see docs/play-console-submission.md, Step 5, for the whole order.
 *
 * 2026-10-17: "Continue with Google" — who may use it, what Google shares, and Google's third job
 * as a recipient. Row: db/migrations/2026-10-17-legal-version-google.sql, same order as above.
 */
export const LEGAL_VERSION = "2026-10-17";

/**
 * Android application id, so the deletion page can name the app Play users installed.
 *
 * THIS IS THE FLUTTER APP, which is the artifact that goes to Play Console: the AAB built by
 * apnivaas_app/scripts/release.sh from apnivaas_app/android/app/build.gradle.kts, where
 * `applicationId = "com.nivorasr.app"`.
 *
 * The earlier browser-wrapper builds had other ids, and NEITHER belongs here: the product moved
 * off the wrapper to a native client, and the wrapper project was removed from this repository
 * on 2026-10-14. The older of those ids was once hardcoded into the deletion page, which meant
 * the data-deletion URL a Play reviewer opens named an app that is not the one under review.
 * Import this constant; do not re-declare it next to the text that prints it.
 */
export const ANDROID_PACKAGE = "com.nivorasr.app";

/**
 * True only when every placeholder has been replaced. The legal pages use this to decide whether
 * to show the "not ready to publish" notice, so nobody has to remember to remove it by hand.
 */
export const isConfigured =
  !Object.values(LEGAL).some((v) => v.includes("NOT YET SET") || v.includes(".invalid"));
