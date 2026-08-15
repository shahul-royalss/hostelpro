---
name: ios-development
description: Senior iOS engineering judgment for Swift/SwiftUI apps — UI framework choice, Swift concurrency, state/architecture, persistence (SwiftData vs Core Data vs GRDB), testing, code signing, TestFlight, App Store review, performance, and accessibility. Use when building or reviewing iOS features, choosing between SwiftUI/UIKit or persistence layers, debugging hangs/memory/concurrency warnings, setting up release pipelines, or preparing an App Store submission.
---

# iOS Development

## Core defaults

- **SwiftUI for all new UI.** UIKit only where SwiftUI still loses (see table below). Wrap, don't rewrite, existing UIKit.
- **Swift 6 language mode with strict concurrency on** for new modules. Migrate legacy modules incrementally; a sea of warnings you ignore is worse than staying on Swift 5 mode with `targeted` checking.
- **`@Observable` (Observation framework), not `ObservableObject`,** in any code targeting iOS 17+. Finer-grained invalidation, no `@Published` boilerplate.
- **MV over MVVM by default:** plain SwiftUI views + `@Observable` model/service objects. Introduce a per-screen view model only when a screen has real presentation logic worth testing in isolation.
- **Constructor injection + environment for app-wide services.** No DI framework. Protocols only where you actually need a test seam or a second implementation.
- **SwiftData for greenfield simple models on recent OS; GRDB when the database matters.** Core Data only for existing codebases.
- **Swift Package Manager for everything.** CocoaPods is legacy; don't add it to new projects.
- **Swift Testing (`@Test`, `#expect`) for new unit tests.** XCTest remains for UI tests and performance tests.
- **Xcode automatic signing for local dev; App Store Connect API key + explicit signing config in CI** (fastlane match or Xcode Cloud both fine — pick one, never both).
- **Ship behind TestFlight for at least one build cycle** before any App Store submission. Review rejections are cheapest to discover before marketing dates exist.

## SwiftUI vs UIKit

Default SwiftUI. UIKit (wrapped via `UIViewRepresentable`/`UIViewControllerRepresentable`, or a UIKit host screen) is still justified for:

| Case | Why |
|---|---|
| High-performance collections (huge, heterogeneous, prefetch-sensitive feeds) | `UICollectionView` + diffable data source + cell prefetching still beats `LazyVStack`/`List` at the extreme end |
| Rich text editing | `UITextView`/TextKit 2 control that `TextEditor` doesn't expose |
| Fine-grained gesture/scroll interop | Simultaneous custom gestures, scroll position control beyond SwiftUI's scroll APIs |
| Media pipelines | Camera (`AVCaptureSession` preview layers), video editing surfaces |
| Legacy codebase | Incremental adoption: new screens SwiftUI, container/navigation may stay UIKit |

Anti-signal: reaching for UIKit because "SwiftUI can't do X" without checking the current SDK — SwiftUI gains APIs every year; verify against the deployment target before wrapping.

## Swift concurrency

- **async/await everywhere; no new GCD.** `DispatchQueue` in new code is a smell except for tiny interop shims.
- **`@MainActor` on anything that touches UI state.** Annotate the type, not individual methods, or you'll play whack-a-mole. With Swift 6.2+, consider the default-MainActor-isolation module setting for app targets — most app code is main-actor code, and it eliminates a large class of annotation noise. Keep libraries/nonisolated-by-default for compute-heavy modules.
- **Actors are for shared mutable state, not for "background work."** To get off the main thread, use a `nonisolated` async function or explicitly-concurrent execution; an actor used as a job queue gives you reentrancy surprises instead.
- **Actor reentrancy is the bug you will actually hit:** every `await` inside an actor method is a suspension point where state can change under you. Re-validate assumptions after each `await`, or restructure so invariants are established in synchronous sections.
- **`Sendable` warnings: fix the design, don't silence.** `@unchecked Sendable` is acceptable only for types with internal locking or immutable-after-init guarantees — and demands a comment explaining why.
- **Structure your tasks.** Prefer `.task {}` on views (auto-cancelled on disappear), `async let` and task groups for fan-out. Bare `Task {}` fire-and-forget in initializers or button handlers loses cancellation and error propagation; `Task.detached` is almost always wrong (drops actor context, priority, and task-locals).
- **Cancellation is cooperative.** Long loops must check `Task.isCancelled` or call `Task.checkCancellation()`; network calls via URLSession already do.

Failure modes to name in review: data race "fixed" with `@unchecked Sendable`; UI updated from a nonisolated context (crash or Main Thread Checker hit); `Task {}` inside `body` (spawns per render).

## State and architecture

- View-local, value-typed state: `@State`. Reference-model ownership: `@State` holding an `@Observable` object. Write access from children: `@Bindable`/`@Binding`. App-wide services: `.environment(...)` with `@Observable` types.
- Do not migrate working `ObservableObject` code just to migrate — but never mix both patterns in one screen; observation semantics differ (whole-object vs property-level) and produce confusing invalidation behavior.
- **MVVM's honest cost:** a view model per view doubles file count and often just proxies. Use one when: the screen has nontrivial derived/presentation state, needs unit tests without rendering, or coordinates multiple services. Otherwise let the view read the model directly.
- **TCA (or similar unidirectional frameworks):** justified when a team is already fluent in it or the app has deeply shared, replayable state (collab editing, complex undo). Do not introduce it into an existing MV/MVVM codebase incrementally — the seams are miserable.
- **DI approach:** pass dependencies through initializers; for wide-reach services (API client, analytics, feature flags) define environment values. For tests, swap at the injection point. Singletons only for genuinely process-global, stateless-ish facilities (logging), and even then behind an injectable handle.
- Modularize with local SPM packages once the app passes roughly "one team, one feature area": Feature packages depending on small Core/Networking/DesignSystem packages. Enforce direction: features never import features.

## Persistence

| Choice | Pick when | Avoid when |
|---|---|---|
| **SwiftData** | Greenfield, iOS 17+ floor, modest model graph, SwiftUI-first, want CloudKit sync with minimal code | Complex migrations, large datasets, background-heavy pipelines, need SQL-level control — maturity gaps still bite |
| **GRDB** | You care about queries, migrations-as-code, FTS, performance, testability; comfortable owning schema | You need CloudKit-managed sync out of the box |
| **Core Data** | Existing Core Data codebase; need battle-tested `NSPersistentCloudKitContainer` behavior with old-OS support | Greenfield — the API tax is no longer worth it |

- Whatever the store: **repository-style boundary** so views never import the persistence framework directly. This is the single cheapest decision for later testability and migration.
- SwiftData gotchas: model objects are not `Sendable` — fetch/mutate on the actor that owns the `ModelContext`; keep contexts per-actor. Versioned schemas + migration plans from day one, not when the first breaking change lands.
- Don't put blobs in the database; store files, reference paths.
- UserDefaults is for preferences, not data. Keychain for secrets — never UserDefaults.

## Testing

| Layer | Tool | Notes |
|---|---|---|
| Unit / logic | **Swift Testing** | `@Test`, `#expect`, `#require`; parameterized tests replace copy-pasted cases; suites are structs — fresh instance per test |
| Async | Swift Testing | `async` test functions; use confirmations for callback APIs |
| Performance | XCTest `measure` | Swift Testing has no equivalent; keep these in an XCTest target |
| UI flows | XCUITest | Expensive and flake-prone: reserve for a small smoke suite of critical paths (launch, sign-in, core purchase/creation flow) |
| Snapshot | Third-party (e.g. pointfree snapshot-testing) | Good for design-system components; pin simulator/OS in CI or diffs churn |

- Test the model/view-model layer hard; test views sparingly. If a behavior is only reachable via XCUITest, that's usually an architecture smell.
- Deterministic tests: inject clocks, UUID/random generators, and URLSession (protocol or `URLProtocol` stub). Never `sleep` in tests; await the actual condition.
- XCTest and Swift Testing coexist in one target — migrate opportunistically, don't big-bang.

## Release engineering

**Signing.** Automatic signing locally. In CI: authenticate with an App Store Connect API key (not a personal Apple ID), and manage distribution certs/profiles explicitly (fastlane match with a private repo, or Xcode Cloud's managed signing). The classic failure is a revoked/expired distribution cert silently breaking CI — put cert expiry on a calendar.

**Debugging signing errors:** read the actual error. "Provisioning profile doesn't include signing certificate" = profile references an old cert — regenerate the profile. Entitlement mismatches (push, App Groups, associated domains) fail at install/runtime, not build — check the built app's entitlements with `codesign -d --entitlements`.

**TestFlight.** Internal testers get builds instantly; external testers require Beta App Review (usually faster and more lenient than full review, but not a rubber stamp). Use build groups to stage rollouts. Increment build number every upload — automate it in CI, never by hand.

**App Store review gotchas** (each has caused real rejections/removals):
- Missing or wrong **purpose strings** (`NSCameraUsageDescription` etc.) — crash on access, instant rejection.
- **Privacy manifest** and required-reason API declarations must cover your third-party SDKs too; audit SDK manifests when adding dependencies.
- **Privacy nutrition labels** must match actual data collection — mismatch with observed network traffic gets flagged.
- Offering third-party login without **Sign in with Apple** (unless you qualify for an exemption).
- Accounts without **in-app account deletion**.
- Digital goods/features sold outside IAP — rules on external purchase links vary by region and change; verify current policy before building, don't assume.
- **Crashes on iPad** — reviewers test iPad even for iPhone-focused apps; run the app on an iPad simulator before every submission.
- `ITSAppUsesNonExemptEncryption` unset — blocks every TestFlight build on an export-compliance question; set it in the Info.plist once.
- Placeholder content, dead links in-app, or a demo account that doesn't work in the review notes.

**Phased release** for anything risky; keep the previous build's rollback plan in mind — there is no server-side rollback of a shipped binary, only expedited review of a fix. Design remote kill-switches (feature flags) for new risky features.

## Performance

- **Measure before optimizing, on the oldest device you support, in Release configuration.** Debug-build SwiftUI performance is not representative.
- **Hangs:** main-thread work >250ms is a hang. Tools, in order: Thread Performance Checker (on in dev), Instruments' hang detection in Time Profiler, MetricKit + Xcode Organizer hang-rate reports from the field. Usual culprits: synchronous disk/decode on main, giant view diffs, implicit main-actor hops around large data transforms.
- **SwiftUI rendering:** use the SwiftUI Instruments template to find views whose `body` evaluates excessively. Fixes in order of value: split large views so invalidation is scoped; make dependencies explicit and minimal; move derived computation out of `body`; check `Equatable` conformance on row models. `@Observable`'s property-level tracking already avoids most over-invalidation — excessive updates usually mean one god-object every view reads.
- **Memory:** Memory Graph Debugger for retain cycles — the recurring offenders are closures capturing `self` in stored handlers, timers, and long-lived `Task`s holding view models. `[weak self]` in escaping closures owned by the object; audit any `Task` stored in a property for lifetime.
- **Launch time:** defer everything nonessential off the launch path; measure with Instruments' App Launch template. Static initializers and eager DI containers are common regressions.
- Track field metrics (hang rate, launch time, memory, crash rate) via MetricKit or Organizer per release; a perf regression you don't measure shipped successfully.

## HIG and accessibility essentials

- Standard components first: navigation stacks, tab bars, sheets, context menus, SF Symbols. Custom chrome costs accessibility, Dynamic Type, and future-OS adaptation (large OS-wide design shifts — e.g. the 2025 material redesign — are nearly free if you used system components, expensive if you didn't).
- Sheets for scoped subtasks; full-screen covers sparingly; never build custom modal systems.
- Respect safe areas; test landscape and iPad multitasking widths even for "iPhone apps."
- Tap targets ≥ 44pt. Destructive actions get confirmation and use destructive roles/styles.
- **Dynamic Type is non-negotiable:** use text styles (`.body`, `.headline`), never fixed point sizes; test at the largest accessibility size — layouts must reflow, not truncate. `@ScaledMetric` for dimensions tied to text.
- **VoiceOver:** every interactive element needs a sensible label (icons especially); use `accessibilityLabel`, traits, and combine decorative subviews with `.accessibilityElement(children: .combine)`. Test by actually turning VoiceOver on and completing your core flow — the Accessibility Inspector catches less than a real pass.
- Honor Reduce Motion (`accessibilityReduceMotion`) for large/parallax animations, and check color contrast in both light and dark mode. Support dark mode from day one — retrofitting is painful.

## Anti-patterns and the failures they cause

| Anti-pattern | Failure |
|---|---|
| `Task {}` inside `body` | New task per render: duplicated work, races, wasted battery |
| Fire-and-forget `Task {}` / `Task.detached` for view-driven work | Lost cancellation and error propagation; work outlives the screen |
| `@unchecked Sendable` to silence concurrency warnings | The data race ships; crashes that never reproduce locally |
| One god `@Observable` object every view reads | App-wide invalidation; SwiftUI performance cliffs |
| Views importing the persistence framework directly | Untestable views; changing stores becomes a rewrite |
| Fixed point sizes instead of text styles | Dynamic Type broken; clipped/truncated text at accessibility sizes |
| Secrets or app data in UserDefaults | Readable off-device; Keychain existed the whole time |
| Synchronous disk/decode on the main actor | Field hang-rate regressions; visible freezes on older devices |
| Hand-bumped build numbers; personal Apple ID auth in CI | Blocked uploads; CI dies when that person's session or cert lapses |
| Skipping the iPad pass on iPhone-only apps | Reviewer runs it on iPad, hits the crash, rejects the build |

## Pre-ship checklist

- [ ] Release build profiled on oldest supported device; no hangs on core flows; launch time acceptable
- [ ] Crash-free smoke pass on iPhone SE-class size, largest iPhone, and iPad (yes, even iPhone-only apps)
- [ ] Dynamic Type at largest accessibility size: no clipped/overlapping text on key screens
- [ ] VoiceOver pass on core flow; all tappables labeled
- [ ] Dark mode visual pass
- [ ] All purpose strings present and honest; privacy manifest + nutrition labels match reality (including SDKs)
- [ ] Account deletion works; Sign in with Apple present if other social logins are
- [ ] Build number bumped by CI; export-compliance key set; correct entitlements verified on the built product
- [ ] Migration path tested: upgrade install over the previous App Store version with real user data
- [ ] Offline / poor-network behavior on core flows (Network Link Conditioner)
- [ ] Kill-switch/feature flags wired for the risky new surface
- [ ] Review notes include a working demo account; no placeholder content or dead links
- [ ] Phased release enabled; field metrics (crash, hang, launch) dashboards ready for the new version
