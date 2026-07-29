# SwiftLint Rule Studio v1.0 Requirements Status

> **Last audited: 2026-07-29** against commit `b1da9a9`. Every ✅/❌ below was
> re-verified against the source tree on that date, not carried forward from a
> previous revision. The prior revision of this document was written
> **2026-01-24** and had drifted badly — most of what it listed as missing had
> since been built. See *Audit note* at the bottom for what changed and why.

## Overview

This document tracks the implementation status of features required for v1.0
release according to the PRD.

---

## 🔬 Verification snapshot (2026-07-29)

| Target | Command | Result |
|---|---|---|
| Core package | `swift test --package-path SwiftLintRuleStudioCore` | ✅ **594 tests in 90 suites passed** |
| App unit | `xcodebuild test -only-testing:SwiftLintRuleStudioTests` | ✅ **650 tests in 112 suites passed** |
| UI tests | `xcodebuild test -only-testing:SwiftLintRuleStudioUITests` | ✅ **9 tests executed, 0 failures** |

### ✅ Resolved — the disable-routing regression

Three app unit tests were failing when this document was audited. **Fixed.**

The rule at issue: **opt-in and analyzer rules are disabled by *absence* from
`opt_in_rules` / `analyzer_rules`; only default rules go into `disabled_rules`.**

`93edd2e` (2026-07-21) had made `YAMLConfigurationEngine+Serialization` fold
every `config.rules` entry marked `enabled == false` into `disabled_rules`. That
layer *cannot* be correct: `YAMLConfig` carries no rule metadata, so the
serializer has no way to tell a default rule from an opt-in or analyzer one. It
therefore pushed all three kinds into the same list, overriding the kind-aware
routing `RuleDetailViewModel.addDisabledRuleIfNeeded` had been doing since
`66c58bc` (2026-05-18).

**Behaviour verified against SwiftLint 0.65.0 rather than assumed:**

| Config | SwiftLint 0.65.0 |
|---|---|
| Rule in `disabled_rules` **and** carrying a config mapping | ⚠️ warns: *"Found a configuration for 'line_length' rule, but it is disabled in 'disabled_rules'."* |
| Opt-in rule listed in `disabled_rules` | silently inert — identical to baseline |
| Analyzer rule listed in `disabled_rules` | silently inert — identical to baseline |

So 93edd2e's *other* half — suppressing the config mapping for a disabled rule —
is correct and was kept. Only the kind-blind fold was removed.

**The fix, in three parts:**

1. **Core serializer** emits `disabled_rules` verbatim from `config.disabledRules`
   and no longer infers it. A comment records why this layer must not.
2. **`RuleBrowserViewModel.disableSelectedRules`** (bulk) now does its own
   kind-aware routing, mirroring the single-rule path — it had been relying on
   the serializer fold. A rule missing from the registry is treated as a default
   rule, so disabling still takes effect.
3. **`RuleDetailViewModel.generateDiff`** now delegates to `applyRuleChanges`
   instead of duplicating the mutation. The duplicate omitted the routing
   entirely, so the diff preview of a disabled default rule showed *no change* —
   preview and save can no longer diverge.

A regression guard (`foldIsNotPerformed`) pins that the serializer does not
re-introduce the fold.

### ⚠️ Known flakiness — not the above, and pre-existing

The app unit target intermittently fails 1–5 tests in the `RuleDetailViewModel*`
suites, with a **different set each run** and clean full-green runs in between.
Root cause identified: each full run leaks ~15 `TemporaryDirectory.*` entries
into `$TMPDIR` (Foundation's atomic-write staging). Once roughly 900 accumulate,
`mktemp` starts failing with `errno 2` and any test creating a temp config dies
with *"Creating a temporary file via mktemp failed."*

**Telling the two apart** — the signature is unambiguous, so a flaky run never
needs to be mistaken for a real break:

- *Flake*: `Caught error: … mktemp failed`, reported at the test's **declaration**
  line (e.g. `…Tests.swift:17:6`) because the throw happens in the setup helper.
  Usually a whole suite fails at once, at the same instant.
- *Real failure*: `Expectation failed: …`, reported at the **assertion** line.

Workaround until fixed:

```bash
find "$TMPDIR" -maxdepth 1 -name "TemporaryDirectory.*" -exec rm -rf {} +
```

With a cleaned `$TMPDIR` the target passes 650/650 consistently. This is the same
instability `TEST_PARALLELIZATION_STATUS.md` recorded in December 2025, now with
a concrete cause. **Unresolved, but independent of feature work.**

---

## 🏗️ Technical Infrastructure

### Swift 6 Migration ✅ **COMPLETE**
- ✅ Swift 6.0 with strict concurrency checking
- ✅ `ViolationStorage` is an actor (`ViolationStorageActor` + 4 extensions)
- ✅ Actor isolation and `Sendable` conformance throughout
- ✅ All concurrency-annotated code is compiler-checked

### Testing Framework ✅ **COMPLETE**
- ✅ Unit tests use Swift Testing (Core + app targets)
- ✅ UI tests remain XCTest (`XCUIApplication` requires it)
- ✅ Isolation helpers for UserDefaults, workspaces, cache dirs, file trackers

### Package & target layout ✅ **COMPLETE**

Not present at all in the previous revision of this doc:

- **`SwiftLintRuleStudioCore/`** — local Swift package holding all models,
  services and utilities. 50 service files.
- **`SwiftLintInProcessBackend/`** — links SwiftLint in-process rather than
  shelling out.
- **`LintStudioUI` 1.4.0** — shared UI package consumed from GitHub (11 import
  sites).
- **Four Xcode targets**: `SwiftLintRuleStudio`, `SwiftLintRuleStudioTests`,
  `SwiftLintRuleStudioUITests`, **`SwiftLintRuleExplorer`**.

### Two editions ✅ **COMPLETE** — and this resolves the App Store sandbox question

`Core/Utilities/AppCapability.swift` defines the capability set the shared UI
conditions on, injected via `@Environment(\.appCapabilities)`:

| Capability | Studio (non-sandboxed) | Explorer (sandboxed) |
|---|---|---|
| `detectInstalledSwiftLint` | ✅ subprocess | ❌ SwiftLint linked in-process |
| `openInXcode` | ✅ via `xed` | ❌ sandbox blocks launching executables |
| `sourceKitRules` | ✅ | ❌ SourceKit cannot load; rules marked unavailable |

`ExplorerApp/SwiftLintRuleExplorerApp.swift` injects `[]` — no capabilities.
This is the architecture that makes a Mac App Store submission viable; see
`docs/SUBMISSION_CHECKLIST.md`.

---

## ✅ P0 Features for v1.0

### 1. Rule Browser ✅ **COMPLETE**
Searchable, filterable catalog; master-detail split view; category badges;
enabled/disabled/opt-in state indicators; CLI-backed loading with caching.

`UI/Views/RuleBrowser/` (6 files), `UI/ViewModels/RuleBrowserViewModel.swift`

### 2. Rule Detail Panel ✅ **COMPLETE**

The four gaps the previous revision listed are **all now built**:

- ✅ **"Why this matters"** — `RuleDetailView+Header.swift:202`
- ✅ **Swift Evolution links** — `RuleDetailView+RationaleHelpers.swift:75`
  (`extractSwiftEvolutionLinks`), rendered at `RuleDetailView+Sections.swift:247`
- ✅ **Current violation count in workspace** — `RuleDetailView.swift:85`
  (`violationCount`, `isLoadingViolationCount`, `loadViolationCount()`)
- ✅ **Related rules** — `RuleDetailView+Sections.swift:202`
- ✅ **"Open in Xcode"** — see §5

Plus: full description, triggering/non-triggering examples, syntax highlighting,
severity selector, parameter editor, markdown rendering, auto-correctable
indicator, diff preview, pending-change tracking, impact simulation.

`UI/Views/RuleDetail/` (8 files), `UI/ViewModels/RuleDetailViewModel.swift`

### 3. YAML Configuration Engine ✅ **MOSTLY COMPLETE**
- ✅ Round-trip preservation (comments, key order, formatting)
- ✅ Diff engine, validation, atomic writes with timestamped backups
- ✅ Multi-config support (parent/child inheritance)
- ✅ **Undo** — superseded by full version history:
  `ConfigVersionHistoryService` (`listBackups` / `loadBackup` / `restoreBackup` /
  `pruneOldBackups`) with `ConfigVersionHistoryView` + view model
- ✅ **Git integration** — `GitBranchDiffService` + `GitBranchDiffView` compare
  config across branches
- ◐ **"Explain changes"** — partial. `RuleChangeSummary` renders added/removed/
  modified *counts*; there is no prose generation.
- ❌ **Dry-run mode UI** — no `dryRun` symbol anywhere in the tree

Engine split across `YAMLConfigurationEngine.swift` + `+Comments` / `+Parsing` /
`+Serialization` / `Protocol`.

**Verified by property-based tests** — `serialize ↔ parse` round-trip, key
ordering stability, diff set-algebra, merge invariants. See `docs/pbt-candidates.md`.

### 4. Workspace Analyzer ✅ **COMPLETE**
Background engine, SQLite violation storage, progress, cancellation, file
watching, history, configurable scope.

`WorkspaceAnalyzer.swift` + `+Helpers` / `+Types`

### 5. Violation Inspector ✅ **COMPLETE**

All six gaps the previous revision listed are **built**:

- ✅ **Open in Xcode** — `XcodeIntegrationService`, wired at
  `ViolationDetailLocationView.swift:55` and `ViolationListItem.swift:75`,
  gated on the `openInXcode` capability, ⌘O
- ✅ **Grouping** — `ViolationGroupingOption`, menu at
  `ViolationInspectorView+ListViews.swift:130`, grouped list at `:313`
- ✅ **Bulk operations UI** — `BulkOperationToolbar`, selection menu, Suppress
  Selected (⇧⌘S), Mark as Resolved (⇧⌘R)
- ✅ **Export** — HTML / JSON / CSV via `UI/Views/Export/` and a separate
  inspector-scoped export (`ViolationInspectorView+Export.swift`)
- ✅ **Next/Previous navigation** — `selectNextViolation()` /
  `selectPreviousViolation()`, ⌘→ / ⌘←
- ✅ **Keyboard shortcuts** — ⌘A select all, ⇧⌘A clear, plus the above

### 6. Workspace Management ✅ **COMPLETE**
File picker, persisted recents, selection UI, sidebar indicator, auto-detected
`.swiftlint.yml`, validation, `SecurityScopedBookmarkStore` for sandboxed access.

`WorkspaceManager.swift` + `+Config` / `+Persistence` / `+RecentWorkspaces` /
`+WorkspaceValidation`

### 7. Rule Configuration Persistence ✅ **COMPLETE**
Enable/disable, save to YAML, diff preview modal, validation, atomic saves with
backup, notification-based component communication.

Disable routing is kind-aware: default rules go to `disabled_rules`, opt-in and
analyzer rules are disabled by absence from their own lists. Diff preview and
save share one code path (`applyRuleChanges`), so they cannot diverge.

### 8. Basic Onboarding Flow ✅ **COMPLETE**
Welcome screen, SwiftLint detection with retry, install guidance (Homebrew,
Mint, direct download), workspace selection, progress indicator, state
persistence, reset.

`OnboardingManager.swift`, `UI/Views/Onboarding/` (4 files)

### 9. Impact Simulation & Zero-Violation Discovery ✅ **COMPLETE**
Single-rule and batch simulation, progress tracking, zero-violation detection,
bulk enable, temp-config generation with cleanup.

⚠️ **`SafeRulesDiscoveryView` no longer exists** — the previous revision named
it. Bulk discovery is now **`RuleAuditView`** ("Disabled Rule Audit" in the
sidebar), `UI/Views/ImpactSimulation/` (11 files).

---

## 🆕 Shipped since the last revision, absent from the previous document

None of the following appeared anywhere in the 2026-01-24 revision. All are
built and reachable from the sidebar (`AppSection` has **12** cases).

| Feature | Entry point |
|---|---|
| Export Report (HTML / JSON / CSV) | `UI/Views/Export/` |
| Disabled Rule Audit | `RuleAuditView.swift` |
| Config Map (nested-config tree) | `ConfigMapView.swift`, `ConfigTreeDiscovery` |
| Resolved-config inspector | `ResolvedConfigInspectorView.swift`, `ResolvedConfigurationEngine` |
| Version History (browse + restore backups) | `ConfigVersionHistoryView.swift` |
| Compare Configs | `ConfigComparisonView.swift`, `ConfigComparisonService` |
| SwiftLint Version Check | `VersionCompatibilityView.swift`, `VersionCompatibilityChecker` |
| Import Config (incl. from URL) | `ConfigImportView.swift`, `ConfigImportService`, `URLConfigFetcher` |
| Branch Diff | `GitBranchDiffView.swift`, `GitBranchDiffService` |
| Migration Assistant | `MigrationAssistantView.swift`, `MigrationAssistant` |
| Config health score + recommendations | `ConfigHealthScoreView.swift`, `ConfigurationHealthAnalyzer` |
| Template library / presets | `TemplateLibraryView.swift`, `BuiltInTemplates`, `ConfigurationTemplateManager` |
| Custom-rule conflict detection | `CustomRuleConflictBanner.swift`, `CustomRuleConflictDetector` |
| PR comment generation | `PRCommentGenerator.swift` |
| Config verification harness | `ConfigVerificationHarness.swift` |

Also shipped: 47 property-law tests across 9 suites, and the two production bugs
they surfaced (see `docs/pbt-candidates.md`).

---

## ❌ Still missing

### Dashboard ⚠️ **NOT IMPLEMENTED** (unchanged)

`AppSection.dashboard` exists and the sidebar links to it, but
`ContentView+Sections.swift:27` renders a bare `Text("Dashboard")` placeholder.
No analytics, trends, or quality metrics.

*(Correction: the previous revision said "Dashboard folder exists but empty" —
there is no Dashboard folder at all.)*

**Priority: LOW** — deferred to v1.1 per PRD.

### Exclusion Path Recommendations ◐ **PARTIAL**

`ConfigurationHealthAnalyzer+Recommendations.swift:49` emits a **high-priority**
`Configure Excluded Paths` recommendation with an `.configureExcludes` action
type when `pathConfiguration` scores below 60.

What is **not** built, versus the original spec:
- ❌ No detection of violations *located in* `.build/`, `Pods/`, `DerivedData/`
- ❌ No checkbox list of common exclusion paths with tooltips
- ❌ No one-click "Add Recommended Exclusions"
- ❌ `.configureExcludes` has no handler — it is produced but never acted on
- ❌ No onboarding integration

**Priority: P1** (v1.1).

### Dry-run mode UI ❌ **NOT IMPLEMENTED**
No `dryRun` symbol in the tree. Arguably superseded by diff preview + version
history, but it was never built as specified.

### "Explain changes" prose ◐ **PARTIAL**
`RuleChangeSummary` gives counts, not explanation.

---

## 📊 Completion Status

| Feature | Status | Completion |
|---------|--------|------------|
| Rule Browser | ✅ Complete | 100% |
| Rule Detail Panel | ✅ Complete | 100% |
| YAML Configuration Engine | ✅ Mostly Complete | 90% |
| Workspace Analyzer | ✅ Complete | 100% |
| Violation Inspector | ✅ Complete | 100% |
| Workspace Management | ✅ Complete | 100% |
| Rule Config Persistence | ✅ Complete | 100% |
| Onboarding Flow | ✅ Complete | 100% |
| Impact Simulation | ✅ Complete | 100% |
| Zero-Violation Detection | ✅ Complete | 100% |
| Xcode Integration | ✅ Complete | 100% |
| Config tooling (map/compare/import/history/migration) | ✅ Complete | 100% |
| Export (HTML/JSON/CSV) | ✅ Complete | 100% |
| Two-edition capability model | ✅ Complete | 100% |
| Exclusion Path Recommendations | ◐ Partial | 25% |
| Dashboard | ❌ Missing | 0% |

**Overall v1.0 completion: ~97%.** Every P0 feature is implemented. What stands
between here and a clean v1.0 is the 3-test regression, not missing features.

*(The previous revision's "~85%" reflected a January snapshot.)*

---

## 📈 Test Coverage Summary

| Target | Framework | Declared `@Test` / `func test` | Files |
|---|---|---|---|
| `SwiftLintRuleStudioCore` | Swift Testing | 598 | 94 |
| `SwiftLintRuleStudioTests` | Swift Testing | 652 | 119 |
| `SwiftLintRuleStudioUITests` | XCTest | 8 | 3 |

Executed counts differ from declarations because of parameterized tests and
XCTest's inherited launch tests. Latest run: **593 core** (all passing),
**650 app unit** (3 failing), **9 UI** (all passing, ~128s).

*(The previous revision's "176 tests in 16 test suites" is off by roughly 7×.)*

Includes **47 property-law tests in 9 suites** (`swift test --filter PropertyLaw`),
every one mutation-verified.

**Test infrastructure:** `TestIsolationHelpers`, `WorkspaceTestHelpers`,
`CacheManager.createForTesting()`, `FileTracker.createForTesting()`,
`DependencyContainer.createForTesting()`, plus per-service helpers in
`SwiftLintRuleStudioCoreTestSupport`.

---

## 🚀 Next Steps

1. **Fix the `$TMPDIR` leak** — ~15 leaked `TemporaryDirectory.*` per run
   eventually break `mktemp` and make the app unit target flaky. Find the
   unbalanced atomic write and clean up after it.
2. **App Store submission prep** — `docs/SUBMISSION_CHECKLIST.md`. The sandbox
   question is architecturally resolved by the Explorer edition; the checklist
   is now signing, App Store Connect, assets, and metadata.
3. **Decide `apply(ConfigDiff, YAMLConfig)`** — build it or close it won't-do.
   Last open item in `docs/pbt-candidates.md`.
4. **Rule-conflict + autocorrect-safety detection** — `docs/proposal-rule-conflict-and-autocorrect-safety.md`,
   confirmed unimplemented (no `RuleConflicts` / `AutocorrectSafety` symbols).
5. **Finish exclusion path recommendations** — wire up `.configureExcludes`.
6. **Dashboard** — v1.1.

---

## Audit note (2026-07-29)

This document had not been touched since 2026-01-24 and actively misled. What
was corrected:

- **11 items marked "MISSING" were built.** The entire Rule Detail gap list, the
  entire Violation Inspector gap list, and Xcode Integration (listed at "0%")
  all shipped.
- **15 shipped features were absent entirely**, including the whole config
  tooling suite and the two-edition capability model.
- **Test counts were off by ~7×** (176 claimed vs ~1,250 declared).
- **Structural defects fixed**: two sections numbered §9, §7 placed after §10,
  §10 filed under "Missing Features" alongside completed work, a duplicated
  `---`, and a "Technical Gaps" section that contradicted §8 by claiming
  "SwiftLint not found → no helpful error" when onboarding has had install
  guidance since December 2025.
- **A stale file reference**: `SafeRulesDiscoveryView` was renamed `RuleAuditView`.
- **One genuinely-still-missing item confirmed**: Dashboard.

**Lesson for future edits:** re-verify against the tree rather than editing the
prior revision in place. Most of the drift came from appending "Recent Updates"
entries without revisiting the status claims above them.

---

## Recent Updates

**July 29, 2026:**
- 🔍 Full re-audit of this document against commit `b1da9a9` (see *Audit note*)
- ✅ **Fixed the disable-routing regression** from `93edd2e` — removed the
  kind-blind `disabled_rules` fold from the Core serializer, made bulk disable
  kind-aware, and unified `generateDiff` with `applyRuleChanges` so preview and
  save share one path. All three targets green.
- 🔬 Probed SwiftLint 0.65.0 directly to settle the design rather than guessing:
  a disabled rule carrying a config mapping *warns*; an opt-in or analyzer rule
  in `disabled_rules` is silently inert
- ⚠️ Identified the cause of the long-standing app-unit flakiness: a ~15/run
  `$TMPDIR` leak that eventually breaks `mktemp`

**July 21–26, 2026:**
- ✅ App Store submission checklist added (`docs/SUBMISSION_CHECKLIST.md`)
- ✅ `93edd2e`: disabled rules serialized into `disabled_rules` — **introduced
  the open regression above**
- ✅ Untracked per-user Xcode scheme state

**June–July 2026 (property-based testing campaign):**
- ✅ 8 of 8 PBT candidates closed; 47 property-law tests across 9 suites
- ✅ Found and fixed a real merge bug — a rule listed in both `disabled_rules`
  and `opt_in_rules` landed in both resolved sets (`c6f70d0`)
- ✅ Extracted a pure `parse(String) -> YAMLConfig` from `load()` (`127351f`)
- ✅ Deleted dead `YAMLConfig.warningThreshold` / `.strict` (`27a6d5b`)
- ✅ Replaced a wall-clock parallelism assertion with a structural one (`9e5b3ca`)

**January 23, 2026:**
- ✅ Refactored large files into focused extensions for SwiftLint `file_length`,
  `function_body_length`, `type_body_length`
- ✅ Consolidated async UI wait helpers (polling over fixed sleeps)
- ✅ SwiftLint config now only disables `todo`

**December 26, 2025:**
- ✅ Swift 6 migration with strict concurrency
- ✅ `ViolationStorage` converted from class to actor
- ✅ Migrated tests from XCTest to Swift Testing
- ✅ Created test isolation helpers
- ✅ Fixed `YAMLConfigurationEngine` file system races via atomic writes

**December 25, 2025:**
- ✅ Fixed SQLite string binding (`strdup` + `free` destructor)
- ✅ Fixed violation accumulation (delete-before-insert)

**December 24, 2025:**
- ✅ Impact simulation and zero-violation rule detection
- ✅ Basic onboarding flow
- ✅ Rule configuration persistence
- ✅ Workspace selection/opening

---

## 💡 Potential Future Enhancements

- Dashboard with adoption trends and quality metrics (v1.1)
- Complete exclusion path recommendation flow
- "Explain changes" prose generation
- Rule-conflict and autocorrect-safety advisories
  (`docs/proposal-rule-conflict-and-autocorrect-safety.md`)
- Best-practices wizard for new projects
