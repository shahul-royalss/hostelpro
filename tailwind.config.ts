import type { Config } from "tailwindcss";
import animate from "tailwindcss-animate";

/**
 * Design tokens — single source of truth, taken from DESIGN.md §1 and
 * design-exports/design-system.json. Every screen must use these names
 * (never raw hex) so the "liquid glass" language stays consistent.
 */
const config: Config = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    container: {
      center: true,
      padding: "24px",
    },
    extend: {
      colors: {
        // ── Brand tokens (DESIGN.md §1) ────────────────────────────────
        ivory: "#F6F4EF", // page background
        stone: "#EDEAE3", // secondary surface
        navy: {
          DEFAULT: "#1C2B45", // primary: buttons, active nav, headings, key numbers
          deep: "#06162F",
          soft: "#384762",
        },
        teal: {
          DEFAULT: "#3E7C74", // success / paid / occupied-healthy / positive
          soft: "#E4EFED",
        },
        sage: {
          DEFAULT: "#8CA687", // free / available
          soft: "#EAF0E8",
        },
        sand: {
          DEFAULT: "#D8B98A", // pending / partial / warning
          deep: "#A8834B", // sand text on light tint (contrast-safe)
          soft: "#F7EFE1",
        },
        red: {
          DEFAULT: "#C4574E", // overdue / unpaid / open / error
          soft: "#F8E7E5",
        },
        charcoal: "#2A2E35", // body text
        muted: "#6E7480", // secondary text
        glass: {
          fill: "rgba(255,255,255,0.65)",
          border: "rgba(255,255,255,0.5)",
          strong: "rgba(255,255,255,0.85)",
        },
        line: "#E5E1D8", // hairline dividers on ivory
        // ── shadcn semantic aliases (mapped onto brand tokens) ─────────
        border: "#E5E1D8",
        input: "#DDD9CF",
        ring: "#1C2B45",
        background: "#F6F4EF",
        foreground: "#2A2E35",
        primary: {
          DEFAULT: "#1C2B45",
          foreground: "#FFFFFF",
        },
        secondary: {
          DEFAULT: "#EDEAE3",
          foreground: "#1C2B45",
        },
        destructive: {
          DEFAULT: "#C4574E",
          foreground: "#FFFFFF",
        },
        muted2: {
          DEFAULT: "#EDEAE3",
          foreground: "#6E7480",
        },
        accent: {
          DEFAULT: "#E4EFED",
          foreground: "#1C2B45",
        },
        popover: {
          DEFAULT: "#FFFFFF",
          foreground: "#2A2E35",
        },
        card: {
          DEFAULT: "rgba(255,255,255,0.65)",
          foreground: "#2A2E35",
        },
      },
      borderRadius: {
        card: "20px", // cards
        control: "12px", // inputs & buttons
        lg: "12px",
        md: "10px",
        sm: "8px",
      },
      fontFamily: {
        sans: ["var(--font-inter)", "Inter", "system-ui", "sans-serif"],
      },
      fontSize: {
        // DESIGN.md typography scale
        stat: ["36px", { lineHeight: "1.2", letterSpacing: "-0.02em", fontWeight: "700" }],
        "stat-sm": ["28px", { lineHeight: "34px", letterSpacing: "-0.02em", fontWeight: "700" }],
        title: ["24px", { lineHeight: "32px", fontWeight: "600" }],
        "title-sm": ["22px", { lineHeight: "30px", fontWeight: "600" }],
        "card-title": ["16px", { lineHeight: "24px", fontWeight: "500" }],
        body: ["14px", { lineHeight: "20px", fontWeight: "400" }],
        caption: ["12px", { lineHeight: "16px", letterSpacing: "0.05em", fontWeight: "600" }],
      },
      spacing: {
        sidebar: "232px",
        "page-desktop": "24px",
        "page-mobile": "16px",
        gutter: "16px",
      },
      boxShadow: {
        glass: "0 8px 32px 0 rgba(6, 22, 47, 0.04)",
        "glass-lg": "0 16px 48px -8px rgba(6, 22, 47, 0.08)",
        nav: "0 -4px 20px rgba(0,0,0,0.04)",
      },
      backdropBlur: {
        glass: "20px",
      },
      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
          to: { height: "0" },
        },
        "fade-in": {
          from: { opacity: "0", transform: "translateY(4px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
      },
      animation: {
        "accordion-down": "accordion-down 0.2s ease-out",
        "accordion-up": "accordion-up 0.2s ease-out",
        "fade-in": "fade-in 0.25s ease-out",
      },
    },
  },
  plugins: [animate],
};

export default config;
