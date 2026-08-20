/**
 * The one file to fill in before publishing to Google Play.
 *
 * The privacy policy, terms and account-deletion pages are all public URLs that a Play reviewer
 * fetches WITHOUT signing in, and Play requires the policy to identify the operator and give a
 * contact that actually works. Until the placeholders below are replaced, those pages render a
 * visible "not ready to publish" notice — which is deliberate: shipping a policy that says
 * "[OPERATOR LEGAL NAME — NOT YET SET]" reads to a reviewer as an unfinished app.
 *
 * These are real-world facts about the business, so they cannot be derived from the codebase.
 * Replace every value marked PLACEHOLDER, then `isConfigured` flips to true on its own and the
 * notices disappear.
 *
 * `.invalid` is a reserved TLD (RFC 2606) that can never resolve. It is used on purpose so a
 * placeholder address can never silently swallow a real data-subject request.
 */

export const LEGAL = {
  /** Registered legal name of the entity operating HostelPro. */
  operatorName: "[OPERATOR LEGAL NAME — NOT YET SET]",

  /** Trading name shown to users. Safe to leave as-is. */
  productName: "HostelPro",

  /** Monitored mailbox for privacy, grievance and data-deletion requests. */
  grievanceEmail: "grievance@placeholder.invalid",

  /** Monitored mailbox for legal/terms correspondence. May be the same as above. */
  legalEmail: "legal@placeholder.invalid",

  /** Full postal address of the operator. Required by the DPDP Act for a Data Fiduciary. */
  postalAddress: "[POSTAL ADDRESS — NOT YET SET]",

  /** Named Grievance Officer, as the DPDP Act 2023 requires a Data Fiduciary to publish. */
  grievanceOfficer: "[GRIEVANCE OFFICER NAME — NOT YET SET]",

  /** e.g. "the laws of India". */
  governingLaw: "[GOVERNING LAW — NOT YET SET]",

  /** e.g. "the courts at Bengaluru, Karnataka". */
  jurisdiction: "[COURTS OF EXCLUSIVE JURISDICTION — NOT YET SET]",

  /** Shown as "last updated" on the published documents. Bump when you change them. */
  lastUpdated: "21 August 2026",
} as const;

/** Android application id, so the deletion page can name the app Play users installed. */
export const ANDROID_PACKAGE = "app.hostelpro.twa";

/**
 * True only when every placeholder has been replaced. The legal pages use this to decide whether
 * to show the "not ready to publish" notice, so nobody has to remember to remove it by hand.
 */
export const isConfigured =
  !Object.values(LEGAL).some((v) => v.includes("NOT YET SET") || v.includes(".invalid"));
