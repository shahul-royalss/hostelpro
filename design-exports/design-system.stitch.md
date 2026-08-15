---
name: Stitch UI
colors:
  surface: '#fbf8fb'
  surface-dim: '#dbd9dc'
  surface-bright: '#fbf8fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f5f3f5'
  surface-container: '#efedf0'
  surface-container-high: '#eae7ea'
  surface-container-highest: '#e4e2e4'
  on-surface: '#1b1b1d'
  on-surface-variant: '#44474d'
  inverse-surface: '#303032'
  inverse-on-surface: '#f2f0f3'
  outline: '#75777e'
  outline-variant: '#c5c6ce'
  surface-tint: '#505f7b'
  primary: '#06162f'
  on-primary: '#ffffff'
  primary-container: '#1c2b45'
  on-primary-container: '#8492b2'
  inverse-primary: '#b8c7e8'
  secondary: '#5f5e59'
  on-secondary: '#ffffff'
  secondary-container: '#e5e2db'
  on-secondary-container: '#65645f'
  tertiary: '#211400'
  on-tertiary: '#ffffff'
  tertiary-container: '#3a2803'
  on-tertiary-container: '#aa8e5f'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d7e3ff'
  primary-fixed-dim: '#b8c7e8'
  on-primary-fixed: '#0b1b35'
  on-primary-fixed-variant: '#384762'
  secondary-fixed: '#e5e2db'
  secondary-fixed-dim: '#c9c6c0'
  on-secondary-fixed: '#1c1c18'
  on-secondary-fixed-variant: '#474742'
  tertiary-fixed: '#ffdea9'
  tertiary-fixed-dim: '#e1c28f'
  on-tertiary-fixed: '#271900'
  on-tertiary-fixed-variant: '#58431b'
  background: '#fbf8fb'
  on-background: '#1b1b1d'
  surface-variant: '#e4e2e4'
  background-ivory: '#F6F4EF'
  accent-teal: '#3E7C74'
  status-sage: '#8CA687'
  status-sand: '#D8B98A'
  status-red: '#C4574E'
  text-charcoal: '#2A2E35'
  text-muted: '#6E7480'
  glass-fill: rgba(255, 255, 255, 0.65)
  glass-border: rgba(255, 255, 255, 0.50)
typography:
  stat-display:
    fontFamily: Inter
    fontSize: 36px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  stat-display-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  page-margin-desktop: 24px
  page-margin-mobile: 16px
  sidebar-width: 232px
  gutter: 16px
---

# DESIGN.md — Stitch UI Specification (PG / Hostel Management SaaS)

## 1. Design language

> Design system for a premium hostel-management SaaS. Aesthetic: soft "liquid glass" — frosted, translucent white cards floating over a warm ivory background, generous whitespace, calm and expensive-feeling, never flashy.
>
> Colors: background warm ivory `#F6F4EF`; secondary surface stone `#EDEAE3`; cards are frosted translucent white (white at ~65% opacity with a strong background blur and a 1px soft white border) with a very soft, wide shadow. Primary color deep navy ink `#1C2B45` — used for primary buttons, active nav items, headings, and key numbers. Accent teal `#3E7C74` for success, paid, occupied-healthy, and positive trends. Sage `#8CA687` for free/available states. Sand `#D8B98A` for pending/partial/warning states. Muted red `#C4574E` for overdue, unpaid, open complaints, and errors. Body text charcoal `#2A2E35`, secondary text `#6E7480`.
>
> Typography: Inter everywhere. Big stat numbers bold 28–36px, page titles semibold 22–24px, card titles medium 15–16px, body 14px, labels/captions 12px uppercase with letter-spacing.
>
> Shape & components: cards radius 20px; inputs and buttons radius 12px; status chips are full pills. Primary button = solid navy with white text; secondary = frosted glass with navy text. Status pills: paid/success = soft teal tint with teal text; pending = soft sand tint; unpaid/overdue/open = soft red tint; free = soft sage tint. Charts use navy as the main series and teal as the comparison series, with rounded bars and no heavy gridlines. Icons: thin-line, rounded (Lucide style). Avatars are circles with warm-toned initials.
>
> Layout: desktop screens use a fixed left sidebar (232px, frosted glass, navy active pill on menu items, logo top, user card bottom) and a top bar with page title left and a notification bell + avatar right. Mobile screens use a top app bar (greeting or title + bell) and a frosted bottom navigation bar with 4–5 icons, active item in navy. Everything airy: 24px page padding on desktop, 16px on mobile.