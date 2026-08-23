import type { MetadataRoute } from "next";

/**
 * NIVORA is a private, invite-only workspace — there is nothing to index and the
 * login/auth screens should never appear in search results (checklist §17/§28).
 */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", disallow: "/" }],
  };
}
