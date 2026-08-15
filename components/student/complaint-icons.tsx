import { CircleHelp, Sparkles, Users, UtensilsCrossed, Wifi, Wrench, type LucideIcon } from "lucide-react";
import type { ComplaintCategory } from "@/lib/types";

export const COMPLAINT_ICON: Record<ComplaintCategory, LucideIcon> = {
  food: UtensilsCrossed,
  cleaning: Sparkles,
  maintenance: Wrench,
  wifi: Wifi,
  roommate: Users,
  other: CircleHelp,
};

export const COMPLAINT_CATEGORY_LABEL: Record<ComplaintCategory, string> = {
  food: "Food",
  cleaning: "Cleaning",
  maintenance: "Maintenance",
  wifi: "Wi-Fi",
  roommate: "Roommate",
  other: "Other",
};
