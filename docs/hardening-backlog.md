# Hardening Backlog — free (non-sandboxed) SwiftLintRuleStudio

_Generated 2026-07-21 from three sweeps of the free edition:_

1. **Correctness/bug review** — `code-reviewer` agent over `Core/Services`, `Core/Utilities`, and `UI/ViewModels`.
2. **Accessibility audit** — `accessibility-reviewer` agent over `UI/Views` + `UI/Components`.
3. **PBT readiness** — `SwiftProjectLint --format pbt-seeds` over `SwiftLintRuleStudioCore` (83 seeds).

All findings were verified against live source. This doc is planning only — nothing here is committed.

## Priority legend

| | Meaning |
|---|---|
| **P0** | Data-integrity or a core user flow is silently broken. Fix first. |
| **P1** | Important correctness bug, or an accessibility blocker (feature unreachable via VoiceOver). |
| **P2** | Real defect, narrower blast radius or workaround exists. |
| **P3** | Polish, robustness, and the property-based-testing track. |

A ⚙️ marker means **a property-based test would have caught this** (or would guard it against regression) — see [PBT opportunities](#property-based-testing-opportunities).

---

## P0 — Ship-blockers / data integrity

### P0.1 ⚙️ Suppressing or resolving a violation is undone by the next analysis
Every analysis calls `storeViolations`, which does `DELETE FROM violations WHERE workspace_id = ?` then reinserts freshly-parsed rows with **new random UUIDs** and `suppressed:false`, `resolvedAt:nil`. Nothing carries prior identity or suppression state forward. Worse, the suppress/resolve UI actions call `refreshViolations()` immediately afterward, which re-runs analysis — so the suppression is wiped by its *own* action, and every ordinary "Analyze" silently discards all suppression/resolution history.

- `Core/Services/ViolationStorageActor+Mutations.swift:5-37` (delete-then-reinsert)
- `Core/Services/WorkspaceAnalyzer+Helpers.swift:217-225` + `Core/Models/Violation.swift:54-78` (new UUID per parse)
- `UI/ViewModels/ViolationInspectorViewModel+Selection.swift:42-56` (trailing refresh)
- `UI/ViewModels/ViolationInspectorViewModel+Loading.swift:41-56` (refresh re-analyzes)

**Fix:** give a violation a stable identity derived from its content (`workspace + file + rule + line + reason`, not a random UUID), and have `storeViolations` upsert — preserving `suppressed`/`resolvedAt` for rows that still match — instead of delete-and-reinsert. Same root cause blocks the currently-unreachable incremental-analysis path (`WorkspaceAnalyzer.analyzeFiles/analyzeChangedFiles`, `WorkspaceAnalyzer.swift:125-180`), which would wipe every file it didn't just re-lint — fix before wiring any incremental-analysis UI.

### P0.2 ⚙️ "Disable Rule" is a silent no-op for ordinary rules
`disableSelectedRules` sets `ruleConfig.enabled = false` but never adds the rule to `config.disabledRules` (contrast `enableSelectedRules`, which maintains `disabledRules`). And the serializer never writes `enabled` at all: `topLevelRuleValue` returns `nil` (omitting the rule) when it has no custom severity/parameters. Net: disabling a plain default rule writes an unchanged `.swiftlint.yml` while the diff preview and save both report success.

- `UI/ViewModels/RuleBrowserViewModel.swift:286-303` (disable path)
- `Core/Services/YAMLConfigurationEngine+Serialization.swift:145-160` (`enabled` never serialized)
- `UI/ViewModels/RuleBrowserViewModel.swift:318-329` (single-toggle funnels through same path)

**Fix:** add the rule to `disabledRules` on disable (mirror the enable path), and ensure the serializer emits a disabling form. Covers both the context-menu single toggle and bulk "Disable Selected."

---

## P1 — Important correctness + accessibility blockers

### P1.1 Sort-direction toggle ignored for Severity, Date, and Line
`.severity`/`.date`/`.line` cases `return` directly from inside the `switch`, bypassing the trailing line that consults `sortOrder`. Only `.file`/`.rule` honor ascending/descending.
- `UI/ViewModels/ViolationInspectorViewModel+Filtering.swift:80-94`
- **Fix:** compute a `ComparisonResult` in each case and fall through to the single `sortOrder`-aware return.

### P1.2 Reopening an already-recent workspace never persists the new order
The "already in recentWorkspaces" branch reorders in memory and bumps `lastAnalyzed` but never calls `saveRecentWorkspaces()`; only the brand-new-workspace branch persists. Recency ordering is silently lost on every reopen.
- `Core/Services/WorkspaceManager.swift:147-160`
- **Fix:** call `saveRecentWorkspaces()` (or route through `addToRecentWorkspaces`) in the existing-recent branch too.

### P1.3 [a11y] "Remove from recent workspaces" unreachable by VoiceOver
An interactive `Button` sits inside another `Button`'s label in the Recent Workspaces row; SwiftUI/AppKit doesn't reliably expose two focusable controls here, so VoiceOver users likely can't reach "Remove."
- `UI/Views/WorkspaceSelection/WorkspaceSelectionView.swift:181-227`
- **Fix:** drop the outer `Button`; use an `HStack` with `.contentShape` + `.onTapGesture` + `.accessibilityAddTraits(.isButton)` + `.accessibilityAction` for "open," leaving the `xmark.circle.fill` as the only real `Button` (or move "remove" to a `.contextMenu`). _Needs live VoiceOver confirmation._

### P1.4 [a11y] Rule parameter controls have no accessible name
`Slider`, `Stepper("")`, and `Toggle("").labelsHidden()` sit next to a sibling `Text(param.name)` but aren't linked — VoiceOver announces bare "Slider/Stepper/Switch" with no indication of which rule parameter they edit.
- `UI/Components/RuleParameterEditor.swift:32-39, 49, 87`
- **Fix:** add `.accessibilityLabel(param.name)` to each; add `.accessibilityValue("\(value)")` to the Slider/Stepper (their value shows in an adjacent `TextField`, not the control).

### P1.5 [a11y] Color-only status dots with no text fallback
`RuleListItem`'s status `Circle` (green/orange/gray) has no text in the gray "disabled" state — color is the only signal, and it isn't hidden. `ConfigHealthPopover`'s recommendation rows convey priority (high/med/low) by dot color alone.
- `UI/Components/RuleListItem.swift:24-26`
- `UI/Views/Configuration/ConfigHealthScoreView.swift:197-199`
- (redundant-but-unhidden dots: `UI/Components/ViolationListItem.swift:21-23`, `UI/Components/HealthScoreBadge.swift:72-74, 105-107`)
- **Fix:** pair each meaningful dot with text (or fold status into a row-level `.accessibilityLabel`); `.accessibilityHidden(true)` the purely-redundant ones.

---

## P2 — Medium

### P2.1 ⚙️ ImpactSimulator always reports column 0
Reads `item["column"]`, but SwiftLint's JSON reporter uses `"character"` (as `WorkspaceAnalyzer+Helpers.swift:206` correctly does). Every simulated violation's `column` is silently `0`.
- `Core/Services/ImpactSimulator.swift:255` — **Fix:** read `item["character"]`.

### P2.2 Quick workspace switching can show the wrong workspace's violations
`loadViolations(for:workspace:)` `await`s a slow analyze, then unconditionally assigns `violations = fetched` with no check that `self.workspaceId` still matches the parameter. The view fires an uncancelled `Task` per switch.
- `UI/ViewModels/ViolationInspectorViewModel+Loading.swift:17-39`
- **Fix:** guard the assignment on `self.workspaceId == workspace.id`, or store & cancel the prior task on switch.

### P2.3 Bulk rule ops silently swallow config-load failures
Each begins `guard (try? yamlEngine.load()) != nil else { return }`; `RuleBrowserViewModel` has no error published property, so a malformed `.swiftlint.yml` makes Enable/Disable/Set-Severity do nothing with zero feedback.
- `UI/ViewModels/RuleBrowserViewModel.swift:253, 287, 306`
- **Fix:** surface the load error to the user (add a `saveError`/`error` published property and present it).

### P2.4 [a11y] Impact-audit rows are fragmented and mislabeled
`RuleAuditRow` applies `.isButton` to a 9-element uncombined `HStack`, so VoiceOver gives ~9 stops per row, and the proportional bar is exposed as an unlabeled image.
- `UI/Views/ImpactSimulation/RuleAuditRow.swift:32-39, 47-122, 169-186`; `RuleAuditRow+ExpandedDetail.swift:45-62`
- **Fix:** follow the `ConfigTreeRowView.swift:38-39` model — `.accessibilityElement(children: .ignore)` + a composed `.accessibilityLabel`, `.isButton` only when expandable, `.accessibilityHidden(true)` on the bars (numeric text already conveys the value).

### P2.5 [a11y] Onboarding clips at large Dynamic Type; progress dots not announced
The 700×500 fixed onboarding frame has no `ScrollView`; the "SwiftLint Not Found" branch overflows (including "Check Again") at AX-large sizes. Progress dots have no "step N of M" cue.
- `UI/Views/Onboarding/OnboardingView.swift:43`; `OnboardingView+Steps.swift:6-17, 102-155`
- **Fix:** wrap step content in a `ScrollView` (as `ImpactSimulationView`/`ConfigDiffPreviewView` already do); add a step-count `.accessibilityLabel` to the progress `HStack`.

---

## P3 — Robustness + polish

- **⚙️ `fetchViolations` treats a SQL `.error` step like `.done`** — returns partial/empty instead of throwing (contrast `getViolationCount`). `Core/Services/ViolationStorageActor+Queries.swift`.
- **Suppress/resolve clears live selection, not processed ids** — changing selection mid-flight wipes the new selection. `ViolationInspectorViewModel+Selection.swift:42-56`.
- **`analyze()` reentrancy** — `currentAnalysisTask` is never assigned (dead `cancel()`), and the task body never checks `Task.isCancelled` before `storeViolations`; a superseded run can overwrite a newer one. `Core/Services/WorkspaceAnalyzer.swift:44, 77-121, 183-190`. _Lower confidence — depends on whether the CLI backend honors cancellation._
- **Fire-and-forget `Task {}` with no cancellation** in `GitBranchDiffViewModel`, `ConfigImportViewModel`, `MigrationAssistantViewModel`, `VersionCompatibilityViewModel` — rapid re-invocation lets a stale result overwrite a fresh one.
- **`ConfigImportService.applyImport` `.merge` mode drops** imported `included`/`analyzerRules`/`onlyRules`/`reporter` instead of merging/warning.
- **[a11y] Draggable panel divider has no keyboard/Switch-Control equivalent.** `UI/Views/RuleBrowser/RuleBrowserView.swift:68-89` — add `.accessibilityAdjustableAction`, or `.accessibilityHidden(true)` if intentionally mouse-only.

---

## Property-based testing opportunities

`SwiftProjectLint --format pbt-seeds` surfaced **83 candidates** (61 pure functions + 22 extractable kernels), clustered exactly where refutable laws live. Manifest: `scratchpad/pbt-seeds.json`. Next step is `swift-infer discover --seeds` (report-only) to see proposed laws.

**Densest hotspots:** `RuleParameterParser` (11), YAML `Parsing`+`Serialization` (13 combined), `ConfigurationHealthAnalyzer` (8) — the first two are round-trip-shaped.

| Kernel | Location | Candidate law |
|---|---|---|
| `mergedWith` | `DefaultExclusions.swift:37,43` | idempotence + associativity of exclusion merge |
| `layerChain` | `ResolvedConfigurationEngine.swift:56` | nested-config fold — associativity + identity |
| `generateDiff` / `diffBetween` | `YAMLConfigurationEngine.swift:220`, `ConfigVersionHistoryService.swift:151` | `apply(diff(a,b), a) == b` round-trip |
| `parseParameters` / `parseRuleParameters` | `RuleParameterParser.swift:20`, `YAMLConfigurationEngine+Parsing.swift:261` | parse ↔ serialize round-trip |
| `orderedTopLevelPairs` / `orderedTopLevelKeys` | serialization | idempotence + permutation-stability |
| `findSafeRules` / `filterViolations` | `ImpactSimulator.swift:231`, `WorkspaceAnalyzer+Helpers.swift:150` | filter idempotence, subset invariant |

**Strategic note:** three of the bugs above are property violations the loop is built to catch — **P0.1** (identity/idempotence of `storeViolations`), **P2.1** (`parse` field mismatch), and any regression in the merge/round-trip kernels. Standing up PBT on the config-merge and YAML round-trip kernels both validates the toolchain against this repo *and* pins those defects closed.

**Full toolchain pipeline** (per pbt-book Appendix C): `SwiftProjectLint` (done) → `swift-infer discover` → `SwiftPropertyLaws` (run laws) → `SwiftIdempotency` (harden the actor mutations — P0.1's `storeViolations` upsert is a natural `#assertIdempotent` target).

---

## Suggested sequencing

1. **P0.1 + P0.2** — the two silent-data-loss bugs. Highest user impact, both in the app's primary flows.
2. **P1.1–P1.2** (quick correctness wins) then **P1.3–P1.5** (a11y blockers).
3. **Stand up PBT** on the config-merge + YAML round-trip kernels — locks P0.1/P2.1 shut and road-tests the toolchain on a real repo (the actual reason this thread started).
4. **P2**, then **P3** as robustness passes.

Per repo convention: one logical change per commit, each building green, unrelated changes never bundled.
