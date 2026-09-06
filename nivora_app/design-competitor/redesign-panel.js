export const meta = {
  name: 'nivora-redesign-design',
  description: 'Map NIVORA\'s visual system, then run a judge panel to pick a palette + shape direction that beats the PG Manager competitor',
  phases: [
    { title: 'Map', detail: 'six parallel readers over NIVORA\'s theme, widgets, shells, auth and dashboards' },
    { title: 'Propose', detail: 'four independent redesign directions from different angles' },
    { title: 'Judge', detail: 'three judges score all four on distinct lenses' },
    { title: 'Synthesize', detail: 'write the single design spec the implementation will follow' },
  ],
}

const APP = 'C:\\Users\\shahu\\OneDrive\\Documents\\pg management system\\nivora_app'
const BRIEF = APP + '\\design-competitor\\PG-MANAGER-TEARDOWN.md'

const PREAMBLE = `You are working on NIVORA, a Flutter PG/hostel-management app for India, at ${APP}.
It ships to Google Play. Five roles: super_admin, owner, manager, warden, student.

FIRST, read ${BRIEF}. That is a teardown of the competitor the user wants NIVORA to beat.

THIS TASK IS READ-ONLY UNLESS TOLD OTHERWISE. Do not edit any file. Report what is actually
there, with file paths and line numbers, verified by reading — never from assumption.`

const MAP_SCHEMA = {
  type: 'object',
  properties: {
    area: { type: 'string' },
    summary: { type: 'string', description: 'What this area looks like today, in plain prose' },
    keyFiles: {
      type: 'array',
      items: {
        type: 'object',
        properties: { path: { type: 'string' }, role: { type: 'string' }, lines: { type: 'number' } },
        required: ['path', 'role'],
      },
    },
    visualFacts: { type: 'array', items: { type: 'string' }, description: 'Concrete measured facts: hexes, radii, spacings, elevations, widget names' },
    constraints: { type: 'array', items: { type: 'string' }, description: 'Things a redesign MUST NOT break, each with the file that enforces it' },
    weaknesses: { type: 'array', items: { type: 'string' }, description: 'Where this area looks worse than the competitor, specifically' },
    changeCost: { type: 'string', description: 'How expensive is it to restyle this area, and what would break' },
  },
  required: ['area', 'summary', 'keyFiles', 'visualFacts', 'constraints', 'weaknesses', 'changeCost'],
}

phase('Map')

const AREAS = [
  {
    key: 'theme',
    prompt: `Map NIVORA's THEME LAYER exhaustively.
Read in full: lib/core/theme/tokens.dart, lib/core/theme/theme.dart, lib/core/theme/typography.dart.
Then read test/theme_contrast_test.dart in full.

I need to know, precisely:
- Every colour token, its hex, and its role. Both the dark scheme (drawn from Figma) and the light scheme (currently ColorScheme.fromSeed on gold #C9A96E).
- The NivoraSemantics ThemeExtension: what it holds, how resolve() works, the light/dark ink sets.
- The domain tones (food/rooms/people + gold) and how NivoraDomain maps to them.
- Radius, Space, IconSize, Shadows, motion tokens — the exact vocabulary and values.
- Typography: which font, which weights are bundled, the type scale slot by slot.

CRITICAL, and the main reason you exist: enumerate EXACTLY which tests in
test/theme_contrast_test.dart would fail if the LIGHT scheme stopped being fromSeed output and
became a hand-drawn palette. Give test names and line numbers. Say for each whether it would
need deleting, rewriting, or would still pass because it recomputes from the token.
Also say what the file's total line count is and roughly how many assertions are light-specific.`,
  },
  {
    key: 'widgets',
    prompt: `Map NIVORA's SHARED WIDGET VOCABULARY.
Read in full every file under lib/shared/ — glass/glass.dart, dashboard.dart, aurora.dart,
beam_card.dart, illustrations.dart, meter.dart, smiley.dart, wordmark.dart, sign_in_again.dart,
and everything under motion/ and rooms/.

For each public widget: its name, what it draws, its shape (radius, border, fill, shadow),
and roughly how many call sites it has (grep for it under lib/features/).

Then answer: which of these already do the job of one of the competitor's five devices
(curved hero, single elevated form card, big rounded outlined input, gradient pill CTA,
full-bleed onboarding carousel)? Which device has NO existing NIVORA widget at all?`,
  },
  {
    key: 'shells',
    prompt: `Map NIVORA's NAVIGATION SHELLS and page chrome.
Read in full: lib/features/shell/role_shell.dart, lib/features/shell/staff_profile_sheet.dart,
lib/features/warden/warden_shell.dart, lib/features/manager/manager_shell.dart,
lib/features/super_admin/sa_shell.dart, lib/features/owner/owner_tabs.dart.
Also read lib/main.dart and whatever router file exists (grep for GoRouter).

I need: how each role's tabs are declared, what the bottom navigation looks like (colours,
labels, icons, indicator), what the header/masthead looks like per role, and where the
scaffold background comes from.

Then: how would a CURVED COLOURED HERO be introduced into these shells? Is there one place it
could go, or would it have to be added per screen? Name the exact insertion point with a line
number.`,
  },
  {
    key: 'auth',
    prompt: `Map NIVORA's AUTH + FIRST-RUN FLOW — the screens a new user sees before anything else,
which is exactly where the competitor beats NIVORA hardest.
Read in full: lib/features/splash/splash_screen.dart, lib/features/auth/login_screen.dart,
lib/features/auth/mfa_screen.dart, lib/features/auth/change_password_screen.dart,
lib/features/auth/verify_email_screen.dart, lib/features/auth/code_field.dart,
lib/features/legal/consent_gate.dart.

Describe the CURRENT visual composition of each screen precisely — what is at the top, what
holds the form, what the fields look like, what the primary button looks like.

Then: is there ANY onboarding carousel in this app? Search the whole of lib/ for one. If there
is none, say so plainly and describe exactly where in the boot sequence one would have to be
inserted (which file, which line, and how it would be gated so it shows once).`,
  },
  {
    key: 'dashboards',
    prompt: `Map NIVORA's FIVE DASHBOARDS — the home screen of each role.
Read in full: lib/features/student/home_screen.dart, lib/features/owner/owner_dashboard_screen.dart,
lib/features/warden/home/warden_home_screen.dart, lib/features/manager/home/manager_home_screen.dart,
lib/features/super_admin/sa_overview_screen.dart.
Also read lib/shared/dashboard.dart since they all build on it.

For each: what is the layout skeleton (greeting? bands? grid of tiles? list?), what widgets it
composes, and what it actually looks like on screen.

Then answer the question that matters: the competitor's screens are CURVED, ELEVATED and
ROUNDED; NIVORA's are FLAT, EDGED and rectangular (there is a deliberate design decision in
tokens.dart that a resting card casts no shadow, only a 1px hairline). Screen by screen, say
what specifically would have to change for NIVORA to read as warm and modern rather than
austere — and whether the shared dashboard.dart vocabulary can carry that change centrally.`,
  },
  {
    key: 'colour-usage',
    prompt: `Map how COLOUR IS ACTUALLY USED across NIVORA's 180 dart files — the blast radius of a
palette change.

Do this empirically with grep, not by reading everything:
- Count call sites of each NivoraColors.* token under lib/. Give the top 25 by frequency.
- Count call sites of context.tones.* and Theme.of(context).colorScheme.*.
- Find every hardcoded Color(0x...) literal under lib/ that is NOT in lib/core/theme/ — these
  are palette leaks. List them with file:line. tokens.dart says features/ may not hardcode
  colours; report every violation.
- Find every place a gradient is already used (LinearGradient, RadialGradient, SweepGradient)
  under lib/, with file:line.
- Find every place a BoxShadow or elevation > 0 is used under lib/, with file:line.
- Find every BorderRadius literal that is not from the Radius token vocabulary.

Then state, as a number: if the light scheme's hexes changed, how many files would visibly
change without any edit to them (i.e. they go through tokens/scheme), versus how many are
hardcoded and would be left behind and look broken.`,
  },
]

const maps = (await parallel(AREAS.map(a => () =>
  agent(PREAMBLE + '\n\n' + a.prompt, { label: 'map:' + a.key, phase: 'Map', schema: MAP_SCHEMA })
))).filter(Boolean)

log('Mapped ' + maps.length + '/' + AREAS.length + ' areas of NIVORA\'s visual system')

const MAP_DIGEST = maps.map(m =>
  '### ' + m.area + '\n' + m.summary +
  '\n\nKEY FILES:\n' + m.keyFiles.map(f => '- ' + f.path + ' — ' + f.role).join('\n') +
  '\n\nVISUAL FACTS:\n' + m.visualFacts.map(v => '- ' + v).join('\n') +
  '\n\nCONSTRAINTS THAT MUST HOLD:\n' + m.constraints.map(c => '- ' + c).join('\n') +
  '\n\nWEAKNESSES VS THE COMPETITOR:\n' + m.weaknesses.map(w => '- ' + w).join('\n') +
  '\n\nCOST TO CHANGE: ' + m.changeCost
).join('\n\n---\n\n')

phase('Propose')

const PROPOSAL_SCHEMA = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    thesis: { type: 'string', description: 'One paragraph: what this direction is and why it beats peach-and-brown' },
    lightPalette: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          token: { type: 'string' },
          hex: { type: 'string' },
          role: { type: 'string' },
          contrast: { type: 'string', description: 'Measured WCAG ratio against the surface it is used on' },
        },
        required: ['token', 'hex', 'role', 'contrast'],
      },
    },
    darkPaletteChanges: { type: 'array', items: { type: 'string' }, description: 'What changes in the dark scheme, or "nothing" with the reason' },
    shapeMoves: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          device: { type: 'string' },
          newWidget: { type: 'string', description: 'The Dart widget name to add, or the existing one to change' },
          file: { type: 'string' },
          how: { type: 'string' },
          callSites: { type: 'string', description: 'Which screens adopt it' },
        },
        required: ['device', 'newWidget', 'file', 'how', 'callSites'],
      },
    },
    onboarding: { type: 'string', description: 'The onboarding carousel: how many pages, what colour each, what copy, where it is gated' },
    beatsCompetitorBecause: { type: 'string' },
    testImpact: { type: 'string', description: 'Exactly which tests break and what it costs to fix them' },
    risks: { type: 'array', items: { type: 'string' } },
  },
  required: ['name', 'thesis', 'lightPalette', 'darkPaletteChanges', 'shapeMoves', 'onboarding', 'beatsCompetitorBecause', 'testImpact', 'risks'],
}

const ANGLES = [
  {
    key: 'keep-dark-fix-light',
    angle: `ANGLE: MINIMUM BLAST RADIUS. The dark theme is a real designed thing from Figma and is
already better than the competitor's peach-and-brown. The rot is entirely in the LIGHT theme,
which is ColorScheme.fromSeed slop on a gold seed and lands in the same bronze-beige family the
user just called worse. So: leave the dark scheme untouched, DRAW a light scheme properly for
the first time, and add the competitor's five shape devices. Argue for this and specify it.`,
  },
  {
    key: 'brand-forward',
    angle: `ANGLE: GIVE NIVORA A COLOUR IT OWNS. The competitor is amber/teal/blue/orchid with a peach
chrome — four unrelated accents and no identity. NIVORA should be instantly recognisable by one
colour the way Spotify is green. Pick that colour, build both schemes around it, and let the
domain tones become a supporting family rather than four equals. Be specific and opinionated
about which colour and why it suits an Indian PG product used by 19-year-old students and
40-year-old owners. Argue for this and specify it.`,
  },
  {
    key: 'shape-first',
    angle: `ANGLE: COLOUR IS NOT THE PROBLEM, SHAPE IS. NIVORA's palette is already better than the
competitor's. What actually makes PG Manager look more finished is that it is curved, elevated
and rounded while NIVORA is flat, edged and rectangular — and tokens.dart made that flatness a
deliberate rule ("a resting card casts NO shadow"). Argue that the single highest-value change
is to overturn that rule and rebuild the shape vocabulary: curved hero, soft elevation, larger
radii, taller inputs, gradient CTAs. Keep palette changes minimal and justify each one.
Argue for this and specify it.`,
  },
  {
    key: 'material3-native',
    angle: `ANGLE: STOP FIGHTING THE FRAMEWORK. The user has repeatedly asked for "colorful, like
Google applications". Google's own apps are Material 3 Expressive: tonal surfaces, large corner
radii, colour-role-driven containers, and a real dynamic light scheme. Argue that NIVORA should
adopt a proper M3 tonal palette (primary/secondary/tertiary containers used as actual containers,
not decoration) rather than a hand-drawn one, which also gives a light theme that cannot be
accused of being undesigned. Specify the seed(s), the surface ramp, and how the five shape
devices land inside M3 idiom. Argue for this and specify it.`,
  },
]

const proposals = (await parallel(ANGLES.map(a => () =>
  agent(
    PREAMBLE +
    '\n\nHere is a full map of NIVORA\'s current visual system, produced by six readers:\n\n' + MAP_DIGEST +
    '\n\n═══════════════════════════════════════\n\n' + a.angle +
    `\n\nProduce a COMPLETE, IMPLEMENTABLE redesign direction. Requirements you must respect:
- Every hex you propose must come with a MEASURED WCAG ratio against the surface it sits on.
  Body text needs 4.5:1 (WCAG 1.4.3). Graphics, borders and controls need 3:1 (1.4.11).
  Compute these properly from relative luminance. A ratio you guessed is worse than no ratio.
- NIVORA must NOT look like the competitor. Do not propose peach, do not propose brown.
- NIVORA keeps its own features; this is a visual change, not a product change.
- The app must keep working in BOTH light and dark. The user's phone is on ThemeMode.system.
- Say honestly what your direction costs in test churn and risk.
Read whatever files you need to make this concrete. Be specific enough that another engineer
could implement it without asking you a question.`,
    { label: 'propose:' + a.key, phase: 'Propose', schema: PROPOSAL_SCHEMA, effort: 'high' }
  )
))).filter(Boolean)

log('Got ' + proposals.length + ' independent redesign directions')

const PROPOSAL_DIGEST = proposals.map((p, i) =>
  '## PROPOSAL ' + (i + 1) + ': ' + p.name +
  '\n\nTHESIS: ' + p.thesis +
  '\n\nLIGHT PALETTE:\n' + p.lightPalette.map(c => '- ' + c.token + ' = ' + c.hex + ' (' + c.role + ') — ' + c.contrast).join('\n') +
  '\n\nDARK CHANGES:\n' + p.darkPaletteChanges.map(d => '- ' + d).join('\n') +
  '\n\nSHAPE MOVES:\n' + p.shapeMoves.map(s => '- ' + s.device + ' → ' + s.newWidget + ' in ' + s.file + '. ' + s.how + ' Adopted by: ' + s.callSites).join('\n') +
  '\n\nONBOARDING: ' + p.onboarding +
  '\n\nBEATS COMPETITOR BECAUSE: ' + p.beatsCompetitorBecause +
  '\n\nTEST IMPACT: ' + p.testImpact +
  '\n\nRISKS:\n' + p.risks.map(r => '- ' + r).join('\n')
).join('\n\n═══════════════════════════════════════\n\n')

phase('Judge')

const SCORE_SCHEMA = {
  type: 'object',
  properties: {
    lens: { type: 'string' },
    scores: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          proposal: { type: 'string' },
          score: { type: 'number', description: '0-10' },
          why: { type: 'string' },
          fatalFlaw: { type: 'string', description: 'The single thing most likely to make this fail in practice, or "none"' },
        },
        required: ['proposal', 'score', 'why', 'fatalFlaw'],
      },
    },
    winner: { type: 'string' },
    graft: { type: 'array', items: { type: 'string' }, description: 'Specific ideas from the losers that the winner should absorb' },
  },
  required: ['lens', 'scores', 'winner', 'graft'],
}

const LENSES = [
  {
    key: 'user',
    lens: `LENS: THE USER'S ACTUAL ASK. Re-read what the user wants: they installed the competitor,
said "see how clean it was and see the animations and designs and everything they were looking
great than our app", and asked that NIVORA's UI "has to look like that in our application not
identical change color combinations which looks better than this and our features". They have
also said repeatedly, across this whole project, that they want it "colorful… like google
applications". Score each proposal on how much it actually closes the gap the user SAW —
not on engineering elegance.`,
  },
  {
    key: 'accessibility',
    lens: `LENS: DOES THE COLOUR MATH SURVIVE. Independently VERIFY the WCAG ratios each proposal
claims. Compute relative luminance yourself for the pairs that matter most: body text on the
card, secondary text on the card, the primary colour as a button fill with its on-colour, the
control border on the field fill, and each status tone as small text. Any proposal quoting a
ratio that is wrong should be heavily penalised — this app enforces contrast in a test suite
that will simply fail the build. Also judge whether the proposal works in BOTH themes.`,
  },
  {
    key: 'delivery',
    lens: `LENS: WILL IT ACTUALLY SHIP. This app is going to Google Play and the user wants an APK
and AAB out of this. There are 180 dart files, 49 test files, and a 1600-line contrast test that
pins the light scheme to fromSeed output hex for hex. Score each proposal on: how much of the
change lands centrally in tokens.dart versus screen-by-screen, how many tests break and how
mechanically, how likely it is to leave half the app restyled and half not, and whether it can
be finished in one sitting rather than becoming a half-migrated mess.`,
  },
]

const verdicts = (await parallel(LENSES.map(l => () =>
  agent(
    PREAMBLE +
    '\n\nFour independent redesign directions were produced for NIVORA. Score all four.\n\n' + PROPOSAL_DIGEST +
    '\n\n═══════════════════════════════════════\n\n' + l.lens +
    '\n\nBe adversarial. Look for the flaw each proposal is hiding. Read files in the repo to check any claim you doubt.',
    { label: 'judge:' + l.key, phase: 'Judge', schema: SCORE_SCHEMA, effort: 'high' }
  )
))).filter(Boolean)

const tally = {}
for (const v of verdicts) {
  for (const s of v.scores) {
    tally[s.proposal] = (tally[s.proposal] || 0) + s.score
  }
}
const ranked = Object.entries(tally).sort((a, b) => b[1] - a[1])
log('Judge tally: ' + ranked.map(r => r[0] + '=' + r[1]).join('  |  '))

const VERDICT_DIGEST = verdicts.map(v =>
  '### Lens: ' + v.lens + '\nWinner: ' + v.winner +
  '\n' + v.scores.map(s => '- ' + s.proposal + ': ' + s.score + '/10. ' + s.why + ' FATAL FLAW: ' + s.fatalFlaw).join('\n') +
  '\nGRAFT: ' + v.graft.join(' | ')
).join('\n\n')

phase('Synthesize')

const spec = await agent(
  PREAMBLE +
  '\n\nFour redesign directions were proposed and three adversarial judges scored them.\n\n' +
  PROPOSAL_DIGEST +
  '\n\n═══════════ JUDGES ═══════════\n\n' + VERDICT_DIGEST +
  '\n\nAGGREGATE SCORE: ' + ranked.map(r => r[0] + ' = ' + r[1]).join(', ') +
  `\n\n═══════════════════════════════════════

YOUR JOB: write the single design specification NIVORA will actually be built to. Start from the
highest-scoring direction, graft in every good idea the judges flagged from the others, and
throw out anything a judge showed to be wrong.

WRITE IT TO: ${APP}\\design-competitor\\NIVORA-REDESIGN-SPEC.md

The spec must be implementable without further design decisions. It must contain:

1. THE PALETTE, as a table of exact hexes with token names matching the existing NivoraColors
   naming, one row per token, each with its measured WCAG ratio against the surface it is used
   on. Light and dark. VERIFY every ratio yourself from relative luminance before writing it —
   the repo's test/theme_contrast_test.dart recomputes them and the build fails on a wrong one.
2. THE SHAPE VOCABULARY: the exact radii, elevations/shadows, input heights, and the decision
   on whether a resting card now casts a shadow (tokens.dart currently says it must not — if the
   spec overturns that, say so explicitly and say what replaces the hairline rule).
3. THE FIVE DEVICES, one section each: curved hero, single elevated form card, big rounded
   outlined input, gradient pill CTA, onboarding carousel. For each: the Dart widget name, the
   file it lives in, its API, and the exact list of screens that adopt it.
4. THE ONBOARDING CAROUSEL in full: page count, the flat colour of each page with its hex, the
   icon, the heading and the subtitle copy for each, and exactly how it is gated to show once
   (which storage, which key, which file, which line of the boot sequence).
5. THE MIGRATION ORDER: a numbered list of edits, each naming its file, in an order where the
   app compiles and the tests pass after every step.
6. THE TEST CHANGES: every test that must change, by name and line number, and what it becomes.
7. WHAT IS DELIBERATELY NOT CHANGING, and why.

Be concrete. No "consider" or "could". Every sentence should be a decision.
After writing the file, return a 300-word summary of the decisions you made and, separately,
anything you deliberately left for a human to choose.`,
  { label: 'synthesize:spec', phase: 'Synthesize', effort: 'high' }
)

return { ranked, spec, specPath: APP + '\\design-competitor\\NIVORA-REDESIGN-SPEC.md' }
