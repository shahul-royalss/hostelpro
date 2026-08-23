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

  /** Full postal address of the operator. Required by the DPDP Act for a Data Fiduciary. */
  postalAddress: "RVS Nagar, Chittoor, Andhra Pradesh, India",

  /** Named Grievance Officer, as the DPDP Act 2023 requires a Data Fiduciary to publish. */
  grievanceOfficer: "Shaik.Shahul",

  /** e.g. "the laws of India". */
  governingLaw: "the laws of India",

  /** e.g. "the courts at Bengaluru, Karnataka". */
  jurisdiction: "the courts at Chittoor, Andhra Pradesh",

  /** Shown as "last updated" on the published documents. Bump when you change them. */
  lastUpdated: "21 August 2026",
} as const;

/** Android application id, so the deletion page can name the app Play users installed. */
export const ANDROID_PACKAGE = "app.nivora.twa";

/**
 * True only when every placeholder has been replaced. The legal pages use this to decide whether
 * to show the "not ready to publish" notice, so nobody has to remember to remove it by hand.
 */
export const isConfigured =
  !Object.values(LEGAL).some((v) => v.includes("NOT YET SET") || v.includes(".invalid"));
