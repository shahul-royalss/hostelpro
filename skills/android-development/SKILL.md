---
name: android-development
description: Senior Android engineering judgment — Kotlin/Compose app architecture, Hilt DI, Room/DataStore, coroutines/Flow, Gradle version catalogs, testing, Play release engineering, and performance. Use when building or reviewing Android apps or features, choosing between Compose and Views, designing ViewModel/StateFlow state, setting up Hilt/Room/Gradle modules, debugging recomposition or ANR/startup issues, or preparing a Play Store release.
---

# Android Development

## Core defaults

- **Kotlin only.** New Java files in an Android app need a justification; there isn't one in 2026.
- **Jetpack Compose for all new UI.** The View system is maintenance-mode for app code.
- **MVVM with unidirectional data flow**: ViewModel exposes a single immutable `UiState` via `StateFlow`; UI sends events up. Full MVI machinery (reducers, intent sealed classes) only when state transitions are genuinely complex.
- **Hilt for DI.** It's the path the rest of Jetpack assumes (`hiltViewModel()`, WorkManager integration). Koin is acceptable in KMP-shared codebases; manual DI only in tiny apps or samples.
- **Room for structured/queryable data, DataStore for key-value and small typed settings.** SharedPreferences is legacy — migrate, don't extend.
- **KSP, never kapt.** kapt is deprecated in practice and slow; every major processor (Room, Hilt, Moshi) supports KSP.
- **Coroutines + Flow end to end.** RxJava only survives in legacy modules; don't add it to new code.
- **Gradle version catalog (`libs.versions.toml`) + convention plugins** for any multi-module project. Copy-pasted `build.gradle.kts` blocks rot.
- **Single-activity app.** Navigation lives in Compose (type-safe routes); activities exist for process entry, deep-link roots, and little else.
- **AAB + Play App Signing + R8 enabled in release.** Shipping an unminified release build is a size and IP mistake.

## Compose vs Views — when the default is wrong

Stay on (or interop with) the View system when:

| Situation | Why |
|---|---|
| Large legacy XML surface, low churn | Rewriting stable screens is negative ROI; interop per-screen instead |
| `WebView`, `SurfaceView`/`TextureView`, camera preview, maps, ad SDKs | These are Views; wrap with `AndroidView` |
| Complex `RecyclerView` with heavily tuned custom layout managers | Port only when you can benchmark parity |
| Remote views: widgets, notifications | Use Glance (Compose-like) for widgets; notifications are RemoteViews regardless |

Interop rule: new screens in Compose, embed legacy Views via `AndroidView`; avoid the reverse (`ComposeView` islands inside XML) except as a migration stepping stone — nesting direction affects how painful state hoisting is.

## Architecture and state

- Layering: **UI (Compose) → ViewModel → Repository → data sources (Room/network/DataStore)**. UI never touches a repository; repositories never import anything from `androidx.compose`.
- One `UiState` data class per screen. Model loading/error explicitly (sealed interface or nullable fields) — don't infer state from "list is empty".
- Expose state as:

```kotlin
val uiState: StateFlow<UiState> = combine(...) { ... }
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Loading)
```

`WhileSubscribed(5_000)` survives rotation without keeping upstream hot in background. `Lazily`/`Eagerly` are usually wrong for screen state.
- Collect in UI with `collectAsStateWithLifecycle()`. Plain `collectAsState()` keeps collecting when the app is backgrounded.
- One-shot effects (navigation, snackbars): prefer modeling as *state the UI consumes and acknowledges* over `SharedFlow` event channels — events fired while no collector is attached are silently lost. If you must use a channel, `Channel(BUFFERED).receiveAsFlow()` and understand the tradeoff.
- ViewModels must not hold `Context`, Views, or composable lambdas. Need resources? Inject `@ApplicationContext` or resolve strings in the UI layer from resource IDs in state.
- Process death is real: anything needed to reconstruct the screen (IDs, query text) goes in `SavedStateHandle`, not just memory.

## Coroutines / Flow conventions

- Inject dispatchers (`@IoDispatcher CoroutineDispatcher`), never hardcode `Dispatchers.IO` at call sites — untestable otherwise.
- Repositories expose cold `Flow`s or `suspend` functions; they do **not** launch their own coroutines except into an injected app-scoped `CoroutineScope` for work that must outlive the caller (e.g., write-behind sync).
- `flowOn` belongs in the data layer next to the blocking work, not in the ViewModel.
- Never `GlobalScope`. Never `runBlocking` on the main thread outside tests/main().
- Wrap callback APIs with `callbackFlow` + `awaitClose`; forgetting `awaitClose` leaks the listener and crashes the flow.
- Don't catch `CancellationException` (or catch-all without rethrowing it) — swallowing it breaks structured cancellation.
- Room and DataStore already move work off the main thread; don't wrap their `Flow`s in extra `withContext`.

## Dependency injection (Hilt)

- Modules per layer, installed in `SingletonComponent` unless a narrower scope is genuinely needed. Over-scoping to `@Singleton` everything is fine; under-scoping causes duplicated OkHttp clients and caches.
- Constructor injection everywhere possible; `@Inject lateinit var` only at framework entry points.
- Bind interfaces (`@Binds`) so tests can swap fakes; `@Provides` for builders/third-party types.
- For tests: `@HiltAndroidTest` + `@UninstallModules` replacing real modules with fakes. If you find yourself mocking Retrofit, bind a fake repository instead — mock at the boundary you own.

## Persistence

| Need | Use |
|---|---|
| Queryable, relational, observable lists | Room (Flow-returning DAOs) |
| Settings, flags, small typed state | DataStore (Proto if schema matters, Preferences for trivial cases) |
| Large media / documents | MediaStore / Storage Access Framework — not app-private copies |
| Secrets/tokens | EncryptedFile or Keystore-backed encryption; never plain DataStore |

- Room: write migrations from schema v2 onward, keep `exportSchema = true` with schemas checked into VCS, and add a migration test per migration. `fallbackToDestructiveMigration` in release wipes user data — it is a data-loss bug, not a shortcut.
- DataStore: one instance per file per process (double-instantiation throws). Reads are async — never block startup waiting on it synchronously; design initial UI state to tolerate a pending read.

## Gradle

- Version catalog is the single source of truth for versions; renovate/dependabot against it.
- Multi-module once the app is non-trivial: `:app`, `:core:*` (model, network, database, designsystem), `:feature:*`. Feature modules depend on core, never on each other.
- Convention plugins (`build-logic/`) for shared android/kotlin/compose config. Duplicated `compileSdk`/`jvmTarget` blocks across 15 modules is how upgrades get missed.
- Build variants: `debug` + `release` is enough for most apps. Add flavor dimensions only for real product splits (free/paid, brand whitelabels, distinct backend environments that can't be a `BuildConfig` field). Every flavor multiplies build/test/CI cost.
- `debug` should be installable alongside `release`: `applicationIdSuffix = ".debug"`.
- Keep secrets out of the repo — inject API keys via CI env / `local.properties`, not committed `BuildConfig` constants.

## Testing pyramid

| Layer | Tool | Notes |
|---|---|---|
| Unit (ViewModel, repo, use case) | JUnit + kotlinx-coroutines-test + Turbine | Bulk of your tests. `runTest`, injected `TestDispatcher`, Turbine's `awaitItem()` for Flow assertions |
| DB / persistence | Room in-memory + Robolectric or instrumented | Migration tests are mandatory once you have migrations |
| UI (Compose) | `createComposeRule` + semantics matchers | Test behavior via semantics, not implementation. Runs on device or Robolectric |
| Screenshot | Roborazzi or Paparazzi | Cheap regression net for the design system module |
| E2E / interop | Espresso / UiAutomator | Only for View interop and true cross-screen journeys; keep this layer thin — it's slow and flaky |

- Fakes over mocks for repositories and data sources. Mockito/MockK are for third-party boundaries you can't fake cheaply.
- A ViewModel that needs Robolectric to unit-test has an architecture problem (Android dependency leaked in).
- Instrumented tests still run on JUnit4; don't fight it.

## Release engineering

- **AAB only** for Play; keep the upload key in a secured keystore + CI secret, enroll in Play App Signing (the app signing key stays with Google; a lost upload key is recoverable, a lost signing key without Play App Signing is not).
- **R8**: `isMinifyEnabled = true` + `isShrinkResources = true` in release. Fix keep rules properly — a blanket `-keep class ** { *; }` silently disables the shrinker. Reflection-using libs need targeted rules; check R8's missing-rules output rather than guessing.
- Upload the mapping file (and native debug symbols if you have NDK code) so Play Console / Crashlytics deobfuscate stack traces.
- **Staged rollout always**: 1% → 5-10% → 25% → 50% → 100%, gated on crash-free rate and ANR rate vs the prior release. Halting a rollout is cheap; a bad 100% push is not. Remember: halted users keep the bad build — ship a fix forward, don't just halt.
- Use internal testing track for every build, closed track for dogfood, pre-launch report before production.
- Watch Android Vitals: staying under Play's bad-behavior thresholds for ANRs and crashes directly affects store visibility.
- `versionCode` strictly monotonic; automate it from CI, don't hand-edit.
- In-app updates API (flexible/immediate) if you need to force-upgrade old clients; design your API versioning assuming you can't.

## Performance

- **Startup**: measure cold start with Macrobenchmark, not stopwatch. Common killers: eager SDK init in `Application.onCreate`, `ContentProvider` auto-init (use androidx.startup or disable providers), synchronous disk reads before first frame, oversized launch activity themes.
- **Baseline Profiles**: generate with the baseline-profile Gradle plugin + Macrobenchmark on your critical journeys; ship them in the AAB. Routinely 20-30% faster cold start for free. Verify with a benchmark comparing `None` vs `Partial`/`Full` compilation modes.
- **Recomposition**:
  - Read state as low as possible; pass lambdas (`() -> T`) instead of frequently-changing values into expensive subtrees (classic case: scroll offset).
  - `derivedStateOf` for values computed from fast-changing state where only threshold changes matter (`firstVisibleItemIndex > 0`).
  - Stable `key`s in `LazyColumn`/`LazyRow` items — without them, inserts recompose everything below.
  - Unstable parameters (List, third-party types) defeat skipping; strong skipping in current Compose compilers mitigates lambdas and default-equality cases, but immutable collections or `@Immutable` wrappers are still the honest fix.
  - Diagnose with Layout Inspector recomposition counts and the Compose compiler metrics reports — don't optimize blind.
- Never do allocation-heavy work in a composable body without `remember`; never launch coroutines in composition (use `LaunchedEffect`).
- ANRs: nothing blocking on main — no synchronous IPC, disk, or `runBlocking`. StrictMode in debug builds catches most of it before users do.

## Permissions and privacy

- Request runtime permissions **in context**, at the moment of use, with rationale UI when `shouldShowRequestPermissionRationale` — never a wall of requests at first launch. Handle permanent denial by deep-linking to app settings, not re-prompting forever.
- Notification permission is runtime on Android 13+; assume a meaningful fraction of users decline and design accordingly.
- **Prefer permission-less APIs**: Photo Picker instead of media read permissions; SAF/`ACTION_CREATE_DOCUMENT` for user files; approximate location when precise isn't needed. Every permission you don't request is review friction and Data-safety-form scope you avoid.
- Scoped storage is the world: app-private via `Context` dirs, shared media via MediaStore, documents via SAF. `MANAGE_EXTERNAL_STORAGE` will get you rejected unless you're a file manager.
- Foreground services need declared types (and some types need eligibility) on Android 14+; deferrable background work belongs in WorkManager, not services.
- The Play Data safety form must match actual SDK behavior — audit third-party SDK data collection; the form covers them too.
- Edge-to-edge is enforced on Android 15+ targets: handle insets deliberately (`WindowInsets` in Compose) rather than discovering clipped UI in QA. Same for predictive back — opt in and test it.

## Anti-patterns and the failures they cause

| Anti-pattern | Failure |
|---|---|
| Business logic in composables | Untestable, recomposition re-runs it, migration pain |
| Must-complete work (writes, sync) launched in `viewModelScope` | Work dies on screen close; lost writes |
| Collecting flows with lifecycle-unaware collectors | Battery drain, background crashes on UI updates |
| `SharedFlow` for must-deliver events | Dropped navigation/snackbars during config change |
| God `UiState` for multiple screens | Every keystroke recomposes unrelated screens |
| `fallbackToDestructiveMigration` in release | Silent user data wipe on upgrade |
| kapt in new modules | 2-5x annotation-processing build-time tax |
| Blanket ProGuard keeps | APK bloat, dead-code shipped, no obfuscation |
| Skipping staged rollout "for a small fix" | The one crash you didn't test hits 100% of users |
| Hardcoded `Dispatchers.IO` | Flaky/impossible unit tests |
| Requesting permissions at app launch | Denial rates spike; users can't connect request to value |
| Ignoring process death (memory-only state) | Crashes and blank screens that never reproduce on dev devices |

## Pre-ship checklist

1. Crash-free and ANR rates on internal/closed track ≥ previous release; Vitals reviewed.
2. R8 enabled, release build actually smoke-tested (minification bugs never appear in debug); mapping file uploaded.
3. Room migrations for every schema change, with tests; no destructive fallback in release.
4. Process death test: enable "Don't keep activities" + background-kill the app on key screens.
5. Config changes, dark theme, font scale 200%, RTL locale, edge-to-edge insets, predictive back — one pass each.
6. All permissions requested in context; denial paths handled; Data safety form matches reality.
7. Deep links and app links verified on a physical device (`autoVerify` state checked).
8. Baseline profile generated for current release and covered by a startup benchmark.
9. `targetSdk` at the current Play requirement; deprecation warnings triaged.
10. Offline / airplane-mode behavior sane on core flows; no infinite spinners.
11. versionCode bumped by CI; release notes and staged rollout plan (with halt criteria) written down.
12. Accessibility pass: TalkBack on main flows, touch targets ≥ 48dp, content descriptions on icon buttons.
