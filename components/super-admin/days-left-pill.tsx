import { StatusPill } from "@/components/shared/status-pill";

/** Days-left pill: sand while running, red once expired, muted when there is no subscription. */
export function DaysLeftPill({ daysLeft, size = "md" }: { daysLeft: number | null; size?: "sm" | "md" }) {
  if (daysLeft === null) return <StatusPill tone="muted" label="No subscription" size={size} />;
  if (daysLeft < 0) return <StatusPill tone="red" label={`Expired ${Math.abs(daysLeft)}d ago`} size={size} />;
  if (daysLeft === 0) return <StatusPill tone="red" label="Ends today" size={size} />;
  return <StatusPill tone={daysLeft <= 30 ? "sand" : "teal"} label={`${daysLeft} day${daysLeft === 1 ? "" : "s"}`} size={size} />;
}
