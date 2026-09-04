/**
 * The one file to fill in before publishing to Google Play.
 *
 * The privacy policy, terms and account-deletion pages are all public URLs that a Play reviewer
 * fetches WITHOUT signing in, and Play requires the policy to identify the operator and give a
 * contact that actually works. Until the placeholders below are replaced, those pages render a
 * visible "not ready to publish" notice — which is deliberate: shipping a policy that says
 * "NIVORA" reads to a reviewer as an unfinished app.
 *
 * These are real-world facts about the business, so they cannot be derived from the codebase.
 * Replace every value marked PLACEHOLDER, then `isConfigured` flips to true on its own and the
 * notices disappear.
 *
 * `.invalid` is a reserved TLD (RFC 2606) that can never resolve. It is used on purpose so a
 * placeholder address can never silently swallow a real data-subject request.
 */

export const LEGAL = {
  /** Registered legal name of the entity operating NIVORA. */
  operatorName: "NIVORA",

  /** Trading name shown to users. Safe to leave as-is. */
  productName: "NIVORA",

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
 *   2. nivora_app/lib/features/legal/legal_documents.dart     — `kLegalVersion`, what the
 *      Android app shows and what it records an acceptance against
 *   3. `public.legal_versions.version`                        — a migration; an acceptance may
 *      only name a version that exists there
 *
 * Change the wording of either document → bump all three → every user is asked to agree again,
 * because the app's consent gate compares the version it ships against the versions that user
 * has accepted. Leaving this behind means people are quietly moved onto text they never saw,
 * which is the one failure mode a consent record exists to make impossible.
 *
 * (1) and (2) are cross-checked by nivora_app/test/legal_consent_test.dart, so they cannot
 * drift silently. (3) is a deployment order, not a check: the migration publishing a version
 * row must land BEFORE an app build carrying that string, because `accept_legal_terms()`
 * refuses a version it has never heard of and at the gate the only thing a user may do is
 * agree.
 */
export const LEGAL_VERSION = "2026-09-04";

/**
 * Android application id, so the deletion page can name the app Play users installed.
 *
 * THIS IS THE FLUTTER APP, which is the artifact that goes to Play Console: the AAB built by
 * nivora_app/scripts/release.sh from nivora_app/android/app/build.gradle.kts, where
 * `applicationId = "app.nivora.mobile"`.
 *
 * Two other ids exist in this repository and NEITHER belongs here. `app.nivora.twa` is the
 * Trusted Web Activity — the browser wrapper that public/.well-known/assetlinks.json still
 * vouches for — and the product deliberately moved off it to a native client. `app.hostelpro.twa`
 * is that wrapper's retired predecessor, and it was hardcoded into the deletion page until now,
 * which meant the data-deletion URL a Play reviewer opens named an app that is not the one under
 * review. Import this constant; do not re-declare it next to the text that prints it.
 */
export const ANDROID_PACKAGE = "app.nivora.mobile";

/**
 * True only when every placeholder has been replaced. The legal pages use this to decide whether
 * to show the "not ready to publish" notice, so nobody has to remember to remove it by hand.
 */
export const isConfigured =
  !Object.values(LEGAL).some((v) => v.includes("NOT YET SET") || v.includes(".invalid"));
