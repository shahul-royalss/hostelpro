import { StatusPill } from "@/components/shared/status-pill";
import type { PillTone } from "@/components/shared/status-pill";

/**
 * Hard rule §4.4 — the Super Admin dashboard flags hostels expiring in 7 / 15 / 30 days.
 * Tone tiers: expired / ≤7 days → red · ≤15 days → sand · ≤30 days → navy · >30 days → teal · none → muted.
 */
export function daysLeftTone(daysLeft: number | null): PillTone {
  if (daysLeft === null) return "muted";
  if (daysLeft <= 7) return "red";
  if (daysLeft <= 15) return "sand";
  if (daysLeft <= 30) return "navy";
  return "teal";
}

export function DaysLeftPill({ daysLeft, size = "md" }: { daysLeft: number | null; size?: "sm" | "md" }) {
  if (daysLeft === null) return <StatusPill tone="muted" label="No subscription" size={size} />;
  if (daysLeft < 0) return <StatusPill tone="red" label={`Expired ${Math.abs(daysLeft)}d ago`} size={size} />;
  if (daysLeft === 0) return <StatusPill tone="red" label="Ends today" size={size} />;
  return <StatusPill tone={daysLeftTone(daysLeft)} label={`${daysLeft} day${daysLeft === 1 ? "" : "s"}`} size={size} />;
}
