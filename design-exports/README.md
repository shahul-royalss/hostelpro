# design-exports — raw Google Stitch output

Pulled from Stitch project **`projects/15365392661227774313` — "Design System Framework"** via the Stitch MCP
(`https://stitch.googleapis.com/mcp`) on 2026-08-15. **Never import these files directly** — rebuild each screen as a
React component per `CLAUDE_2.md` §10, keeping the visual language and replacing the dummy data.

## Layout

```
design-exports/
  <SCREEN-ID>/
    index.html        full Stitch export (Tailwind CDN + Google Fonts; a few use Chart.js CDN)
    screenshot.png    Stitch thumbnail (SA-1/2/3 are .jpg)
    meta.json         title, device type, canvas size, Stitch project/screen ids
  index.json          machine-readable list of all screens (same data as meta.json, aggregated)
  design-system.json  the Stitch project's design theme: 56 named colors, font, roundness
  design-system.stitch.md   the DESIGN.md frontmatter (colors / typography / rounded / spacing tokens) as stored in Stitch
../DESIGN.md          the full UI spec that was fed to Stitch (screen prompts + IDs)
```

## Screens (27 + DESIGN.md = 28 items in the Stitch project)

| ID | Role | Stitch title | Device | Canvas | HTML | Screenshot | Stitch screen id |
|---|---|---|---|---|---|---|---|
| A-1 | Auth | Login | DESKTOP | 2560×2048 | [A-1/index.html](A-1/index.html) | [screenshot.png](A-1/screenshot.png) | `f4465226c5a741c4906d9f8f3a3a586c` |
| A-2 | Auth | Change Password (First Login) | DESKTOP | 2560×2048 | [A-2/index.html](A-2/index.html) | [screenshot.png](A-2/screenshot.png) | `e98d00507bef41e68f37c383002b7c24` |
| SA-1 | Super Admin | Super Admin Dashboard | DESKTOP | 2560×2048 | [SA-1/index.html](SA-1/index.html) | [screenshot.jpg](SA-1/screenshot.jpg) | `d09fa12250964ef4877b70f3337aecea` |
| SA-2 | Super Admin | Create Owner & Hostel Wizard | DESKTOP | 2560×2048 | [SA-2/index.html](SA-2/index.html) | [screenshot.jpg](SA-2/screenshot.jpg) | `675ece7cbaf4486ebfafd197fcb04c28` |
| SA-3 | Super Admin | Subscriptions Management | DESKTOP | 2560×2048 | [SA-3/index.html](SA-3/index.html) | [screenshot.jpg](SA-3/screenshot.jpg) | `476b055bec7c4de3a26dfaaf98a1dfe9` |
| SA-4 | Super Admin | Hostel Detail (Monitoring) | DESKTOP | 2560×2048 | [SA-4/index.html](SA-4/index.html) | [screenshot.png](SA-4/screenshot.png) | `cd5e6d2bbf344eeebf1fddb14c12dd7e` |
| OW-1 | Owner | Owner Dashboard | DESKTOP | 2560×2048 | [OW-1/index.html](OW-1/index.html) | [screenshot.png](OW-1/screenshot.png) | `1b1a6e045562401caaae332119c9c467` |
| OW-2 | Owner | Complaints Inbox | DESKTOP | 2560×2048 | [OW-2/index.html](OW-2/index.html) | [screenshot.png](OW-2/screenshot.png) | `b3df07fc809f4b6299d5f1a7736d8c34` |
| OW-3 | Owner | Broadcast Updates | DESKTOP | 2560×2048 | [OW-3/index.html](OW-3/index.html) | [screenshot.png](OW-3/screenshot.png) | `abf001b218f2400ab478f6620b2b6647` |
| OW-4 | Owner | Staff & Tasks | DESKTOP | 2560×2048 | [OW-4/index.html](OW-4/index.html) | [screenshot.png](OW-4/screenshot.png) | `b02b6b8789dc4dd2b51cd019c519faa1` |
| OW-5 | Owner | Students Directory | DESKTOP | 3360×2048 | [OW-5/index.html](OW-5/index.html) | [screenshot.png](OW-5/screenshot.png) | `efb10a74ad27444e9b9557a2ef8a1cf0` |
| OW-6 | Owner | Finance Overview | DESKTOP | 2560×2754 | [OW-6/index.html](OW-6/index.html) | [screenshot.png](OW-6/screenshot.png) | `d4aed9bbcc62405d9da1cea9d1dd7c8b` |
| MG-1 | Manager | Manager Dashboard | DESKTOP | 2560×2048 | [MG-1/index.html](MG-1/index.html) | [screenshot.png](MG-1/screenshot.png) | `a8fda86df9c64da286d524b11757256b` |
| MG-2 | Manager | Daily Expenses | DESKTOP | 2560×2250 | [MG-2/index.html](MG-2/index.html) | [screenshot.png](MG-2/screenshot.png) | `292c0533e606441782d8717833c9e94d` |
| MG-3 | Manager | Daily Revenue | DESKTOP | 2560×2370 | [MG-3/index.html](MG-3/index.html) | [screenshot.png](MG-3/screenshot.png) | `d9a79bde9c9f47059a392dc5e9c06346` |
| MG-4 | Manager | Mess Menu Editor | DESKTOP | 2560×2734 | [MG-4/index.html](MG-4/index.html) | [screenshot.png](MG-4/screenshot.png) | `839b583a6b1a41d6a0c983e8fd657c65` |
| WD-1 | Warden | Warden Home | MOBILE | 780×2332 | [WD-1/index.html](WD-1/index.html) | [screenshot.png](WD-1/screenshot.png) | `e17f32e4c4de4e229c86c40a1bad737a` |
| WD-2 | Warden | Register Student (Form) | MOBILE | 780×1768 | [WD-2/index.html](WD-2/index.html) | [screenshot.png](WD-2/screenshot.png) | `3f73e3869f0f477e876559dd45a2d58a` |
| WD-3 | Warden | Rooms & Beds List | MOBILE | 780×2192 | [WD-3/index.html](WD-3/index.html) | [screenshot.png](WD-3/screenshot.png) | `7af553efeb9141aab4068c9a73b1e8d8` |
| WD-4 | Warden | Room Detail View | MOBILE | 780×2106 | [WD-4/index.html](WD-4/index.html) | [screenshot.png](WD-4/screenshot.png) | `16193162931a4af090072b6d729e8554` |
| WD-5 | Warden | Fees Tracker | MOBILE | 780×1768 | [WD-5/index.html](WD-5/index.html) | [screenshot.png](WD-5/screenshot.png) | `b52be6bbcc0343fca277c555eb9896c9` |
| WD-6 | Warden | Leaves & Visitors Management | MOBILE | 780×1768 | [WD-6/index.html](WD-6/index.html) | [screenshot.png](WD-6/screenshot.png) | `f3f74b31d3554ae6b186525372965e74` |
| ST-1 | Student | Student Home | MOBILE | 780×1956 | [ST-1/index.html](ST-1/index.html) | [screenshot.png](ST-1/screenshot.png) | `667f7f5052c445f980b9138173d3d611` |
| ST-2 | Student | Student Profile | MOBILE | 780×2634 | [ST-2/index.html](ST-2/index.html) | [screenshot.png](ST-2/screenshot.png) | `0b4e14db4ebf4917aea5c2007fb1a6a7` |
| ST-3 | Student | Mess Menu | MOBILE | 780×2000 | [ST-3/index.html](ST-3/index.html) | [screenshot.png](ST-3/screenshot.png) | `4275ee093d9d45e3999368345fbaa72e` |
| ST-4 | Student | My Complaints | MOBILE | 780×1768 | [ST-4/index.html](ST-4/index.html) | [screenshot.png](ST-4/screenshot.png) | `a22766766ef24eff9636573aae39d46f` |
| ST-5 | Student | My Room & Roommates | MOBILE | 780×1768 | [ST-5/index.html](ST-5/index.html) | [screenshot.png](ST-5/screenshot.png) | `cf7779c7a9bb49b295ee7ccd1752f074` |

## Re-fetching / editing screens

The Stitch MCP server is registered as `stitch` (project scope, `~/.claude.json`). After a Claude Code restart it exposes
`list_projects`, `list_screens`, `get_screen`, `generate_screen_from_text`, `edit_screens`, `generate_variants`,
`apply_design_system`, etc. To pull a screen again: `get_screen` with `name = projects/15365392661227774313/screens/<stitch screen id>`
and download `htmlCode.downloadUrl` / `screenshot.downloadUrl`.

## Design tokens (from `design-system.json` / DESIGN.md §1)

| Token | Value | Use |
|---|---|---|
| background-ivory | `#F6F4EF` | page background |
| primary (navy ink) | `#1C2B45` | buttons, active nav, headings, key numbers |
| accent-teal | `#3E7C74` | success / paid / positive |
| status-sage | `#8CA687` | free / available |
| status-sand | `#D8B98A` | pending / partial / warning |
| status-red | `#C4574E` | overdue / unpaid / open / error |
| text-charcoal | `#2A2E35` | body text |
| text-muted | `#6E7480` | secondary text |
| glass-fill / glass-border | `rgba(255,255,255,.65)` / `rgba(255,255,255,.5)` | frosted cards |
| radius | cards 20px · inputs/buttons 12px · pills full | shape |
| font | Inter | everything |
