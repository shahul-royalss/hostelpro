export const meta = {
  name: 'nivora-ship-audit',
  description: 'Audit NIVORA for crashes, tap feedback, performance, responsiveness, scale, rate limiting and store readiness, then adversarially verify every finding',
  phases: [
    { title: 'Find', detail: 'eight parallel auditors, one per dimension' },
    { title: 'Verify', detail: 'three adversarial lenses per finding; majority refute kills it' },
  ],
}

const APP = 'C:\\Users\\shahu\\OneDrive\\Documents\\pg management system'
const FLUTTER = APP + '\\nivora_app'

const PREAMBLE = `NIVORA is a Flutter + Supabase PG/hostel-management app for India, shipping to
Google Play. Flutter client at ${FLUTTER} (Dart package name is \`mobile\`), Next.js web app and
SQL migrations at ${APP}, Supabase project nimxvgzscbanhtvgnjll.

Five roles: super_admin, owner, manager, warden, student. 180 Dart files, 1194 passing tests,
analyzer clean.

THE OWNER'S ASK, VERBATIM: "check every tab every section every button and main clicks has to
give some feedback according to the clicks and animations everything has to be good...
performance... speed... everything has to be great... and make sure no crashes has to occur...
and it has to fit perfectly in every android model and every ios model... make sure the load
speed, responsive speed everything has to be fast in a scale application... it doesn't has to
depend on how many members are using currently it has to work with same speed... and make sure
include rate limiting which is not gonna crash our system and clear every error which you face."

THIS PASS IS READ-ONLY. Do not edit a single file. Your job is to FIND, with evidence.

RULES FOR WHAT COUNTS AS A FINDING:
- It must be real. Read the code and quote it. A pattern that "could" be slow is not a finding
  unless you can say what input makes it slow and roughly how slow.
- Give file:line for everything.
- Rank by what would actually hurt a user or a Play Store review, not by how easy it is to say.
- If a dimension is genuinely in good shape, SAY SO and say what you checked. A clean report
  that lists what was verified is worth more than invented problems.
- Do not report things the repo has deliberately decided, unless the decision is now wrong —
  the codebase documents its decisions in comments and you should read them before disagreeing.`

const FINDING_SCHEMA = {
  type: 'object',
  properties: {
    dimension: { type: 'string' },
    verdict: { type: 'string', description: 'One paragraph: what state is this dimension actually in' },
    checked: { type: 'array', items: { type: 'string' }, description: 'What you verified and found healthy' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['blocker', 'high', 'medium', 'low'] },
          file: { type: 'string' },
          line: { type: 'number' },
          evidence: { type: 'string', description: 'The code, quoted' },
          impact: { type: 'string', description: 'What a user or reviewer actually experiences' },
          trigger: { type: 'string', description: 'The exact input or condition that causes it' },
          fix: { type: 'string', description: 'Concrete, implementable' },
          userMustDo: { type: 'boolean', description: 'true if only the account owner can do it (console toggle, store setting, Apple hardware)' },
        },
        required: ['title', 'severity', 'file', 'evidence', 'impact', 'trigger', 'fix', 'userMustDo'],
      },
    },
  },
  required: ['dimension', 'verdict', 'checked', 'findings'],
}

phase('Find')

const DIMENSIONS = [
  {
    key: 'crashes',
    prompt: `DIMENSION: CRASHES. The owner said "make sure no crashes has to occur".

Hunt for anything that can throw at runtime in ${FLUTTER}/lib:
- \`!\` bang operators on nullables that can genuinely be null (check each; most are fine).
- \`.first\`, \`.last\`, \`.single\`, \`[index]\` on collections that can be empty or shorter.
- \`int.parse\`/\`double.parse\`/\`DateTime.parse\` on values from the network or a text field.
- \`as\` casts on JSON.
- setState / ref.read after dispose; missing \`mounted\` guards after an await.
- Controllers, AnimationControllers, StreamSubscriptions, FocusNodes not disposed.
- Unawaited futures whose errors become unhandled exceptions.
- Division by zero in any percentage or ratio (occupancy, collection rate, progress bars).
- Any place a Supabase response is assumed non-empty.
Also check main.dart for a top-level error handler: does an unexpected exception show the user
something, or a grey screen?`,
  },
  {
    key: 'feedback',
    prompt: `DIMENSION: TAP FEEDBACK AND ANIMATION. The owner said "every button and main clicks has
to give some feedback according to the clicks and animations everything has to be good".

Go through ${FLUTTER}/lib/features and ${FLUTTER}/lib/shared and check every interactive thing:
- Does it have a visible press state? GestureDetector with no InkWell/Material gives NONE.
  Find every raw GestureDetector/onTap that is not wrapped in an InkWell or an ink-splashing
  widget, with file:line.
- Does every async action show a busy state, and is the control disabled while busy? Find
  buttons whose onPressed fires a Future without any \`_busy\` guard — those double-submit.
- Does every destructive action confirm?
- Does every successful action say something happened (snackbar, sheet close, list update)?
- Are tap targets at least 48dp? Find any IconButton or InkWell smaller than that.
- List the animations that exist and say which screens have NONE — a screen where content
  appears with no transition is the specific thing the owner noticed in the competitor.
Read ${FLUTTER}/lib/shared/motion/ first to see what vocabulary already exists.`,
  },
  {
    key: 'flutter-perf',
    prompt: `DIMENSION: CLIENT PERFORMANCE AND SPEED.

In ${FLUTTER}/lib:
- Find every Column/Row inside a SingleChildScrollView holding a list that grows with data —
  those build every row. Should be ListView.builder / SliverList.
- Find widgets that rebuild too widely: a Consumer/ref.watch high in the tree where a narrow
  one would do; setState on a whole screen for one field.
- Find missing \`const\` on expensive subtrees (only report where it matters, not every literal).
- Find expensive work in build(): sorting, filtering, date formatting, regex, model mapping.
- Find images without cacheWidth/cacheHeight or ResizeImage, and any full-size asset drawn small.
- Find opacity/clip/shadow layers that force saveLayer.
- Check the app's cold-start path (lib/core/boot/startup.dart, main.dart, splash) for anything
  awaited serially that could be parallel, and anything on the main isolate that should not be.
Say concretely which screens would jank and on what data volume.`,
  },
  {
    key: 'responsive',
    prompt: `DIMENSION: FITTING EVERY DEVICE. The owner said "it has to fit perfectly in every
android model and every ios model".

In ${FLUTTER}/lib:
- Find hardcoded pixel sizes that will overflow on a small phone (360x640 logical, e.g. Galaxy
  A-series) — fixed heights on cards, fixed-width Rows, SizedBox widths that add up past 360.
- Find text that will overflow at large system text scale (Android font size Largest, iOS
  Accessibility sizes). Any Text in a Row without Flexible/Expanded/overflow is a candidate.
- Check MediaQuery.textScalerOf handling — does the app clamp it, and should it?
- Find anything that assumes a bottom nav bar height or a status bar height numerically.
- Check SafeArea coverage: notches, punch-holes, iOS home indicator, Android gesture bar.
- Check landscape: does anything assume portrait?
- Check the largest supported: tablets and foldables — is there a max content width, or does a
  form stretch to 1200px?
- Read ${FLUTTER}/lib/core/theme/tokens.dart for the Breakpoints class and see if it is used.
Also check the iOS project at ${FLUTTER}/ios: is it configured at all — bundle id, display
name, permission usage strings (Info.plist NSCameraUsageDescription etc. for image_picker),
deployment target? Say plainly whether an iOS build would even work.`,
  },
  {
    key: 'scale',
    prompt: `DIMENSION: SPEED THAT DOES NOT DEGRADE WITH USERS. The owner said "it doesn't has to
depend on how many members are using currently it has to work with same speed".

This is mostly a database question. Read the SQL in ${APP}/db and the repositories in
${FLUTTER}/lib/features/*/data and ${FLUTTER}/lib/data:
- Find every query with NO pagination that will grow unbounded: notices, audit log, payments,
  complaints, students, notifications. Which screens load "all" of something?
- Find N+1 patterns: a list that fetches per-row detail.
- Find client-side aggregation that should be a database aggregate.
- Read the RLS policies and identify any that call a function per row rather than per query
  (the classic: auth.uid() unwrapped in a policy, which re-evaluates per row — should be
  (select auth.uid())).
- These INFO advisories are live on the project and I already have them, so do not re-derive:
  25 unindexed foreign keys, 4 unused indexes, and multiple permissive policies on beds,
  floors, menus and subscriptions. INSTEAD, tell me which of those actually matter for THIS
  app's query patterns and which are noise, and write the exact CREATE INDEX statements for
  the ones that matter.
- Check realtime subscriptions: how many does a screen open, are they closed on dispose, and
  would 500 concurrent users mean 500 open channels each?`,
  },
  {
    key: 'ratelimit',
    prompt: `DIMENSION: RATE LIMITING. The owner said "make sure include rate limiting which is not
gonna crash our system".

Map what protection exists TODAY and what is missing:
- Read ${FLUTTER}/test/auth_throttle_test.dart and whatever it tests — there is some auth
  throttling already; describe exactly what it covers.
- Read every edge function in ${APP}/supabase/functions (razorpay-order, razorpay-webhook and
  any others). Do they rate limit? Can an authenticated user call razorpay-order in a loop and
  create unlimited orders?
- Read the SECURITY DEFINER RPCs in ${APP}/db — wd_record_payment, wd_register_student,
  rz_open_intent, sa_create_hostel_with_subscription, password_reset_gate. Which of these can
  be called in a tight loop, and what does that cost? password_reset_gate is callable by ANON.
- Is there anything protecting the app from a client retry storm — exponential backoff, a
  circuit breaker, a debounce on refresh?
- Propose a concrete, minimal rate-limiting design that fits this stack (Postgres-based, since
  there is no Redis), with the actual SQL. It must FAIL SOFT: the owner said it must not crash
  the system, so a rate limiter that errors must let the request through, not block it.`,
  },
  {
    key: 'store',
    prompt: `DIMENSION: GOOGLE PLAY READINESS.

Read ${FLUTTER}/android/app/build.gradle.kts (or .gradle), AndroidManifest.xml, and any store
metadata in the repo. Check:
- applicationId, versionCode/versionName, minSdk/targetSdk against Play's current requirement.
- Signing config: does a release build sign with a real keystore, and is the keystore or its
  password committed anywhere? Search the whole repo for leaked secrets.
- Permissions declared vs actually used. Every permission needs a reason a reviewer accepts.
- Is there a Data safety story: what does the app collect, is it declared, does the privacy
  policy URL resolve?
- ProGuard/R8: is minification on, and are there keep rules for Razorpay and Supabase? A
  missing keep rule is a release-only crash, which is the worst kind.
- Does the app handle being backgrounded/killed and restored?
- Check for anything Play rejects: non-compliant target SDK, missing 64-bit, unrestricted
  cleartext traffic, an ad ID permission with no ads, foreground service without a type.
- Read ${FLUTTER}/scripts/release.sh and say whether its gates are sufficient.`,
  },
  {
    key: 'errors',
    prompt: `DIMENSION: ERROR HANDLING AS THE USER SEES IT. The owner said "clear every error which
you face".

- Run \`flutter analyze\` in ${FLUTTER} and report anything (it should be clean; confirm).
- Read every catch block in ${FLUTTER}/lib. Find: empty catches that swallow silently, catches
  that show a raw exception string to the user (\`$e\` in a SnackBar leaks Postgres error text
  and reads as a crash), and catches that catch too broadly.
- Find every place a Supabase PostgrestException code could reach the UI unmapped — 23505
  unique violation, 42501 RLS denial, PGRST116 no rows. What does the user see for each?
- Find loading states that can hang forever: a Future that never completes leaves a spinner up
  with no timeout and no retry. Is there a timeout on network calls anywhere?
- Check offline: what happens with no network on each screen? Is there a distinguishable
  "you are offline" versus "something broke"?
- Check the Supabase project's live logs for real errors in the last 24h if you can reach the
  Supabase MCP tools (project nimxvgzscbanhtvgnjll) — real errors beat theoretical ones.`,
  },
]

const reports = (await parallel(DIMENSIONS.map(d => () =>
  agent(PREAMBLE + '\n\n' + d.prompt, {
    label: 'audit:' + d.key,
    phase: 'Find',
    schema: FINDING_SCHEMA,
    effort: 'high',
  })
))).filter(Boolean)

const all = reports.flatMap(r => (r.findings || []).map(f => ({ ...f, dimension: r.dimension })))
log('Found ' + all.length + ' candidate findings across ' + reports.length + ' dimensions')

phase('Verify')

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true if this finding is wrong, already handled, or not worth acting on' },
    why: { type: 'string' },
    severityShouldBe: { type: 'string', enum: ['blocker', 'high', 'medium', 'low', 'drop'] },
    fixIsRight: { type: 'boolean' },
    betterFix: { type: 'string', description: 'Empty if the proposed fix is right' },
  },
  required: ['refuted', 'why', 'severityShouldBe', 'fixIsRight', 'betterFix'],
}

const LENSES = ['does-it-reproduce', 'is-it-already-handled', 'is-the-fix-worse-than-the-bug']

const verified = await parallel(all.map((f, i) => () =>
  parallel(LENSES.map(lens => () =>
    agent(
      PREAMBLE +
      `\n\n═══ VERIFY ONE FINDING, THROUGH THE "${lens}" LENS ═══\n\n` +
      'DIMENSION: ' + f.dimension +
      '\nTITLE: ' + f.title +
      '\nSEVERITY CLAIMED: ' + f.severity +
      '\nFILE: ' + f.file + (f.line ? ':' + f.line : '') +
      '\nEVIDENCE: ' + f.evidence +
      '\nIMPACT CLAIMED: ' + f.impact +
      '\nTRIGGER CLAIMED: ' + f.trigger +
      '\nPROPOSED FIX: ' + f.fix +
      `\n\nTRY TO REFUTE IT. Open the file. Read the surrounding code AND its comments — this
codebase documents its decisions, and a "bug" that a comment explains as deliberate is not a
bug. Check whether a test already covers it. Check whether the trigger can actually occur given
how the screen is reached.

Default to refuted=true when you are not convinced. A false finding costs more than a missed
one here, because acting on it churns working code.`,
      { label: 'verify:' + i + ':' + lens.slice(0, 12), phase: 'Verify', schema: VERDICT_SCHEMA }
    )
  )).then(votes => {
    const v = votes.filter(Boolean)
    const kills = v.filter(x => x.refuted).length
    return { finding: f, votes: v, survives: v.length > 0 && kills < 2 }
  })
))

const survivors = verified.filter(Boolean).filter(v => v.survives)
const killed = verified.filter(Boolean).filter(v => !v.survives)
log('Verified: ' + survivors.length + ' survived, ' + killed.length + ' refuted by majority')

const rank = { blocker: 0, high: 1, medium: 2, low: 3 }
const final = survivors.map(v => {
  // Take the harshest severity any surviving lens argued for, and the first better fix offered.
  const sev = v.votes.map(x => x.severityShouldBe).filter(s => s !== 'drop')
  sev.sort((a, b) => (rank[a] ?? 9) - (rank[b] ?? 9))
  const better = v.votes.find(x => !x.fixIsRight && x.betterFix)
  return {
    ...v.finding,
    severity: sev[0] || v.finding.severity,
    fix: better ? better.betterFix : v.finding.fix,
    verifierNotes: v.votes.map(x => x.why),
  }
}).sort((a, b) => (rank[a.severity] ?? 9) - (rank[b.severity] ?? 9))

return {
  healthy: reports.map(r => ({ dimension: r.dimension, verdict: r.verdict, checked: r.checked })),
  findings: final,
  refuted: killed.map(v => ({ title: v.finding.title, why: v.votes.map(x => x.why)[0] })),
}
