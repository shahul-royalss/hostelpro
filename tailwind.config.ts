import type { Config } from "tailwindcss";
import animate from "tailwindcss-animate";

/**
 * Design tokens — single source of truth.
 *
 * Two systems live here, and they are the same system:
 *
 *  1. The brand language from DESIGN.md §1 — warm ivory, navy ink, teal accent,
 *     frosted glass. Every one of those token NAMES is unchanged and every one
 *     resolves to the exact colour it always did. They now read through CSS
 *     custom properties defined in app/globals.css, which is what lets the dark
 *     theme and `prefers-contrast: more` re-point them without touching a
 *     single component.
 *
 *  2. Apple's semantic system on top — the label and fill hierarchies, the
 *     system colour set, the five material weights, the optical type ramp, the
 *     spring curves and the radius ladder.
 *
 * Reasoning, usage guidance and the measured contrast ratio for every pair:
 * docs/design-system.md.
 */

/** `rgb(var(--x) / <alpha-value>)` keeps Tailwind's `/50` opacity modifiers working. */
const c = (v: string) => `rgb(var(${v}) / <alpha-value>)`;
/** A token whose alpha is itself a token (the label and fill ladders). */
const ca = (v: string, a: string) => `rgb(var(${v}) / var(${a}))`;

const config: Config = {
  // `.dark` stays the switch it always was; `[data-theme="dark"]` is accepted
  // too so a theme toggle can write an attribute instead of a class. The token
  // layer in globals.css keys off both, so the `dark:` variant and the tokens
  // can never disagree about which theme is active.
  darkMode: ["variant", ["&:is(.dark *)", '&:is([data-theme="dark"] *)']],
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
        // ── Brand tokens (DESIGN.md §1) — same values, now themeable ────
        ivory: c("--brand-ivory"), // page background            #F6F4EF
        stone: c("--brand-stone"), // secondary surface          #EDEAE3
        navy: {
          DEFAULT: c("--brand-navy"), // primary: buttons, active nav, headings, key numbers
          deep: c("--brand-navy-deep"),
          soft: c("--brand-navy-soft"),
        },
        teal: {
          DEFAULT: c("--brand-teal"), // success / paid / occupied-healthy / positive
          soft: c("--brand-teal-soft"),
        },
        sage: {
          DEFAULT: c("--brand-sage"), // free / available
          soft: c("--brand-sage-soft"),
        },
        sand: {
          DEFAULT: c("--brand-sand"), // pending / partial / warning
          deep: c("--brand-sand-deep"),
          soft: c("--brand-sand-soft"),
        },
        red: {
          DEFAULT: c("--brand-red"), // overdue / unpaid / open / error
          soft: c("--brand-red-soft"),
        },
        charcoal: c("--brand-charcoal"), // body text
        muted: c("--brand-muted"), // secondary text
        glass: {
          fill: "rgb(var(--material-tint) / 0.65)",
          border: "rgb(var(--material-tint) / 0.5)",
          strong: "rgb(var(--material-tint) / 0.85)",
        },
        line: c("--brand-line"), // hairline dividers on ivory

        // ── Apple: label hierarchy ──────────────────────────────────────
        // Four rungs of the same ink. Alphas are re-solved for the ivory
        // backdrop (Apple's are calibrated against pure white) so that
        // `label` and `label-secondary` both clear 4.5:1. See the doc.
        label: {
          DEFAULT: ca("--label-ink", "--label-a1"), // 12.40:1 on ivory
          secondary: ca("--label-ink", "--label-a2"), //  4.62:1 — body copy
          tertiary: ca("--label-ink", "--label-a3"), //  3.02:1 — large text, icons
          quaternary: ca("--label-ink", "--label-a4"), // decorative only
        },

        // ── Apple: fill hierarchy ───────────────────────────────────────
        // Translucent greys for control backgrounds, track fills and
        // pressed states. Backgrounds only — never put meaning in a fill.
        fill: {
          DEFAULT: ca("--fill-ink", "--fill-a1"),
          secondary: ca("--fill-ink", "--fill-a2"),
          tertiary: ca("--fill-ink", "--fill-a3"),
          quaternary: ca("--fill-ink", "--fill-a4"),
        },

        separator: ca("--separator-ink", "--separator-a"),

        // ── Accessible inks: the brand hues at AA strength ──────────────
        // Same hue, darkened until they clear 4.5:1 on ivory, on a glass
        // card and on their own soft tint. Any text that carries meaning
        // (status pills, amounts, inline warnings) belongs on these.
        ink: {
          navy: c("--ink-navy"),
          teal: c("--ink-teal"),
          sage: c("--ink-sage"),
          sand: c("--ink-sand"),
          red: c("--ink-red"),
          muted: c("--ink-muted"),
        },

        // ── Graphical marks: the 3:1 floor for non-text objects ─────────
        mark: {
          sage: c("--mark-sage"),
          sand: c("--mark-sand"),
        },

        // ── Apple system colours (light/dark/increase-contrast aware) ───
        sys: {
          blue: c("--sys-blue"),
          green: c("--sys-green"),
          indigo: c("--sys-indigo"),
          orange: c("--sys-orange"),
          pink: c("--sys-pink"),
          purple: c("--sys-purple"),
          red: c("--sys-red"),
          teal: c("--sys-teal"),
          yellow: c("--sys-yellow"),
          gray: c("--sys-gray"),
        },

        material: {
          tint: "rgb(var(--material-tint) / <alpha-value>)",
          border: "var(--material-border)",
          strong: "var(--material-border-strong)",
        },

        // ── shadcn semantic aliases (mapped onto brand tokens) ──────────
        border: c("--brand-line"),
        input: c("--brand-input"),
        ring: c("--brand-navy"),
        background: c("--brand-ivory"),
        foreground: c("--brand-charcoal"),
        primary: {
          DEFAULT: c("--brand-navy"),
          foreground: "#FFFFFF",
        },
        secondary: {
          DEFAULT: c("--brand-stone"),
          foreground: c("--brand-navy"),
        },
        destructive: {
          DEFAULT: c("--brand-red"),
          foreground: "#FFFFFF",
        },
        muted2: {
          DEFAULT: c("--brand-stone"),
          foreground: c("--brand-muted"),
        },
        accent: {
          DEFAULT: c("--brand-teal-soft"),
          foreground: c("--brand-navy"),
        },
        popover: {
          DEFAULT: "rgb(var(--material-tint))",
          foreground: c("--brand-charcoal"),
        },
        card: {
          DEFAULT: "rgb(var(--material-tint) / 0.65)",
          foreground: c("--brand-charcoal"),
        },
      },

      borderRadius: {
        // Apple's continuous-corner ramp: 6 / 10 / 14 / 20 / 28.
        xs: "6px", // badges, bed dots, chart bars, avatars ≤24px
        sm: "8px", // legacy step, kept for shadcn menu items
        md: "10px", // ramp: surfaces nested inside a card
        lg: "12px", // legacy step == control
        control: "12px", // inputs & buttons
        "control-lg": "14px", // ramp: 44pt+ controls, segmented controls
        card: "20px", // ramp: cards
        sheet: "28px", // ramp: sheets, modals, hero surfaces
      },

      fontFamily: {
        // -apple-system resolves to the real SF Pro (and its optical
        // Text→Display switch) on Apple platforms; Inter, already loaded by
        // next/font, renders everywhere else. Full stack in globals.css.
        sans: ["var(--font-sans)"],
        mono: ["var(--font-mono)"],
      },

      fontSize: {
        // ── The scale this app already speaks ───────────────────────────
        // Sizes and line-heights are FROZEN — they drive every layout in
        // the app. Only tracking moved, onto the optical curve below.
        stat: ["36px", { lineHeight: "1.2", letterSpacing: "-0.016em", fontWeight: "700" }],
        "stat-sm": ["28px", { lineHeight: "34px", letterSpacing: "-0.013em", fontWeight: "700" }],
        title: ["24px", { lineHeight: "32px", letterSpacing: "-0.011em", fontWeight: "600" }],
        "title-sm": ["22px", { lineHeight: "30px", letterSpacing: "-0.01em", fontWeight: "600" }],
        "card-title": ["16px", { lineHeight: "24px", letterSpacing: "-0.004em", fontWeight: "500" }],
        body: ["14px", { lineHeight: "20px", fontWeight: "400" }],
        // The uppercase eyebrow role (.label-caps). Caps need positive
        // tracking; this is deliberately NOT Apple's caption1 tracking.
        caption: ["12px", { lineHeight: "16px", letterSpacing: "0.05em", fontWeight: "600" }],

        // ── Apple's semantic ramp, verbatim sizes and leading ───────────
        // Tracking is the web adaptation: SF tightens optically on its own
        // at display sizes, Inter does not, so the ramp carries an explicit
        // negative curve above 17px and neutral-to-positive below 13px.
        "large-title": ["34px", { lineHeight: "41px", letterSpacing: "-0.015em", fontWeight: "700" }],
        "title-1": ["28px", { lineHeight: "34px", letterSpacing: "-0.013em", fontWeight: "700" }],
        "title-2": ["22px", { lineHeight: "28px", letterSpacing: "-0.01em", fontWeight: "600" }],
        "title-3": ["20px", { lineHeight: "25px", letterSpacing: "-0.008em", fontWeight: "600" }],
        headline: ["17px", { lineHeight: "22px", letterSpacing: "-0.005em", fontWeight: "600" }],
        "body-lg": ["17px", { lineHeight: "22px", letterSpacing: "-0.005em", fontWeight: "400" }],
        callout: ["16px", { lineHeight: "21px", letterSpacing: "-0.004em", fontWeight: "400" }],
        subhead: ["15px", { lineHeight: "20px", letterSpacing: "-0.002em", fontWeight: "400" }],
        footnote: ["13px", { lineHeight: "18px", letterSpacing: "0em", fontWeight: "400" }],
        "caption-1": ["12px", { lineHeight: "16px", letterSpacing: "0em", fontWeight: "400" }],
        "caption-2": ["11px", { lineHeight: "13px", letterSpacing: "0.006em", fontWeight: "400" }],
      },

      letterSpacing: {
        display: "-0.015em", // ≥28px
        title: "-0.011em", // 20–24px
        text: "-0.004em", // 15–17px
        caps: "0.05em", // uppercase eyebrows
      },

      spacing: {
        sidebar: "232px",
        "page-desktop": "24px",
        "page-mobile": "16px",
        gutter: "16px",
      },

      boxShadow: {
        // Legacy names, unchanged values.
        glass: "0 8px 32px 0 rgba(6, 22, 47, 0.04)",
        "glass-lg": "0 16px 48px -8px rgba(6, 22, 47, 0.08)",
        nav: "0 -4px 20px rgba(0,0,0,0.04)",
        // The elevation ramp: a tight contact shadow plus a wide ambient one.
        "elev-1": "var(--shadow-1)", // resting chip, inline control
        "elev-2": "var(--shadow-2)", // raised button, hovered row
        "elev-3": "var(--shadow-3)", // card at rest
        "elev-4": "var(--shadow-4)", // popover, dropdown, sheet
        "elev-5": "var(--shadow-5)", // modal over a dimmed page
        // The specular top edge that makes a material read as glass.
        highlight: "var(--material-highlight)",
        material: "var(--material-highlight), var(--shadow-3)",
      },

      backdropBlur: {
        glass: "20px",
        "ultra-thin": "12px",
        thin: "20px",
        regular: "20px",
        thick: "30px",
        chrome: "24px",
      },

      backdropSaturate: {
        160: "1.6",
        180: "1.8", // the Apple material default
        190: "1.9",
      },

      transitionTimingFunction: {
        // CAMediaTimingFunction .default and the three UIView curves.
        sys: "var(--ease-sys)",
        "sys-in": "var(--ease-sys-in)",
        "sys-out": "var(--ease-sys-out)",
        "sys-in-out": "var(--ease-sys-in-out)",
        // Real damped-harmonic springs, sampled into linear(). Pair each with
        // its matching duration-* or the overshoot lands in the wrong place.
        spring: "var(--ease-spring)", // .spring(response .55, damping .825)
        smooth: "var(--ease-smooth)", // .smooth  (bounce 0)
        snappy: "var(--ease-snappy)", // .snappy  (bounce 0.15)
        bouncy: "var(--ease-bouncy)", // .bouncy  (bounce 0.30)
      },

      transitionDuration: {
        quick: "200ms", // hover, tint, opacity
        standard: "300ms", // most state changes
        emphasized: "500ms", // full-screen or hero transitions
        spring: "730ms",
        smooth: "700ms",
        snappy: "660ms",
        bouncy: "750ms",
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
        // Apple's popover/alert entrance: scale up from just under 1 while
        // fading, so the surface feels like it grew out of its anchor.
        "scale-in": {
          from: { opacity: "0", transform: "scale(0.96)" },
          to: { opacity: "1", transform: "scale(1)" },
        },
        // Sheet / bottom-sheet rise.
        "sheet-in": {
          from: { opacity: "0", transform: "translateY(12px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
      },

      animation: {
        "accordion-down": "accordion-down 0.2s var(--ease-sys-out)",
        "accordion-up": "accordion-up 0.2s var(--ease-sys-out)",
        "fade-in": "fade-in 0.25s var(--ease-sys-out)",
        "scale-in": "scale-in var(--duration-snappy) var(--ease-snappy)",
        "sheet-in": "sheet-in var(--duration-smooth) var(--ease-smooth)",
      },
    },
  },
  plugins: [animate],
};

export default config;
