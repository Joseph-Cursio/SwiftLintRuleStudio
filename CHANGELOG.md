# Changelog

All notable changes to SwiftLint Rule Studio are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Fixed
- Rule Audit no longer reports a rule as "Safe to enable" when its simulation failed. A failed simulation used to count as 0 violations; it now shows as an error with its reason and is never counted safe or enabled by "Enable all safe rules"
- Analyzer rules, which `swiftlint lint` never runs, are shown as "Can't be measured here" instead of measuring 0; in the sandboxed edition, so are rules that need SourceKit
- Simulations now count what enabling a rule really does in workspaces that use symlinks, `included`/`excluded` (list or single-string form), `**` and brace globs, `parent_config`/`child_config`, folders beside the workspace (`../Shared`), or a repository config pulled in by a package opened on its own (`parent_config: ../../.swiftlint.yml`)
- A rule is simulated as Enable enables it: in the root config and the configs it pulls in. A nested config that disables the rule still disables it beneath it, as it will after Enable
- A rule disabled under a deprecated name (`variable_name`, `if_let_shadowing`, `redundant_optional_initialization`, `operator_whitespace`, `redundant_self_in_closure`) is now enabled and counted
- `custom_rules` now counts the violations of every custom rule; it used to measure 0
- A config's `baseline:` filters simulated violations as it filters real ones, and `write_baseline:` is never written by a simulation, so the user's baseline file is left alone
- An `included`/`excluded` list containing a non-string entry is ignored, as SwiftLint ignores it
- `${PWD}` in `included`/`excluded` now refers to the workspace in both analysis and simulation lints
- On a case-sensitive volume, files whose names differ only in case are no longer merged in the simulation's copy
- Cancelling an audit, closing the workspace or leaving the audit stops the SwiftLint run in progress (SIGTERM, then SIGKILL) and removes its temporary copy; abandoned copies from a crash are cleaned up after a day, and a copy still in use is never removed

### Changed
- Simulation copies of a workspace are now kept in `~/Library/Caches` (the app's caches folder) rather than the temp folder, except for workspaces under `/tmp` or `/var`, which are copied into the temp folder. A workspace on a volume that treats letter case differently is copied onto that volume
- Workspace analysis lints now run through the same cancellable runner as simulations, with `PWD` set to the workspace
- When a workspace can't be simulated faithfully, each affected rule shows why instead of a count. Examples: an absolute or remote `parent_config`; an `included` path more than eight folders above the workspace; a symlink loop SwiftLint would crash on; a config SwiftLint can't read; a workspace opened through a symlink; more than 20,000 files reached outside the workspace

---

## [1.1.1] — 2026-05-01

### Changed
- `LintStudioUI` is now consumed as a remote SwiftPM dependency from `https://github.com/Joseph-Cursio/LintStudioUI.git` (pinned `from: "1.0.0"`) instead of a local path, decoupling the build from sibling-checkout layout

---

## [1.0.1] — 2026-03-06

### Fixed
- `ViolationStorage.database` changed from `nonisolated(unsafe) var` to `let`, preventing accidental mutation from outside the actor and eliminating a potential use-after-close race in `deinit`
- `WorkspaceAnalyzer.analyze()` is now properly cancellable: external calls to `cancelAnalysis()` and caller-side task cancellation both correctly cancel the in-flight analysis

---

## [1.0.0] — 2026-02-27

### Added
- Static analyzer warnings fully resolved across all production and test targets

### Fixed
- Xcode static analyzer warnings eliminated (retain cycles, redundant casts, unused results)
- SwiftLint violations brought to zero on all targets

---

## [1.0.0-beta.5] — 2026-02-26

### Added
- macOS-native UX: right-click context menus on rules and violations
- Dock badge showing active violation count
- macOS notification when workspace analysis completes
- Native menu bar items (Workspace, Analysis, Rules menus)
- Native toolbar with contextual actions in RuleBrowser and ViolationInspector
- `USER_GUIDE.md` — end-user walkthrough covering all 11 core workflows
- `COMPANION_GUIDE.md` and `REFERENCE.md` — in-depth documentation for advanced users
- UI tests covering all 11 USER_GUIDE workflows

### Changed
- Yams dependency upgraded from 5.4.0 → 6.2.1
- `ContentView` navigation refactored; resolved `SwiftUI.Section` name collision
- `HSplitView` (native AppKit-backed split view) replaces custom `HStack + DraggableDivider`
- Resizable panels in RuleBrowser and ViolationInspector with persisted divider positions
- `DraggableDivider` extracted as a reusable standalone component before HSplitView adoption

### Fixed
- Rule browser no longer appears empty on first load
- Newlines in rule detail descriptions are preserved
- Crash when selecting rules (HTML rendering replaced with pure SwiftUI `Text`)
- Excessive left margins caused by nested `NavigationSplitView`

---

## [1.0.0-beta.4] — 2026-02-14

### Added
- YAML configuration visual editor with field-level controls
- Bulk configuration operations (enable/disable rule sets by category)
- Configuration history with diff viewer and one-click revert
- Configuration comparison between two `.swiftlint.yml` files
- Phase 3 configuration features: import from external project, git-diff preview, migration assistant, SwiftLint version compatibility check
- `Simulate Impact` button now available for already-enabled rules (previously disabled-only)
- SwiftLint documentation attribution appended to each rule's description panel
- README with MIT license and open-source acknowledgements
- `CLAUDE.md` — guidance file for Claude Code AI assistant

### Changed
- `DefaultExclusions` unified across `WorkspaceAnalyzer` and `ImpactSimulator` — directory exclusion lists are no longer duplicated
- All deprecated `foregroundColor` calls replaced with `foregroundStyle`
- All deprecated `cornerRadius` calls replaced with `clipShape`
- All deprecated two-parameter `onChange` closures modernised to the new form
- `RuleBrowserView` now requires explicit dependency injection; fragile no-arg initialiser removed
- Swift 6.2 strict concurrency fully adopted in the test target (MainActor.run wrappers reduced from 1 013 → 925)

### Fixed
- `ImpactSimulator` no longer scans `.build/` and other excluded directories
- `WorkspaceManager` tests no longer flake due to stale `UserDefaults`
- `ConfigurationTemplateManagerTests` correctly handles uncovered project types
- Swift Concurrency gaps identified in audit (actor isolation, Sendable conformance)
- Rule detail panel text hidden behind the list column

---

## [1.0.0-beta.3] — 2026-01-31

### Added
- Xcode integration: open any violation directly in Xcode at the exact file and line via URL scheme
- Violation Inspector multi-select and scoped export (selected violations, current filter, or all)
- Rule Detail Panel improvements: conditional short-description display, enriched documentation parser
- Accessibility labels and traits on all interactive controls
- UI tests for Xcode integration and SwiftUI view stability
- Expanded CLI and UI test coverage

### Changed
- SwiftLint enabled on the test target with trailing-whitespace and trailing-newline rules
- SwiftLint complexity hotspots refactored to stay under cyclomatic complexity limits
- `waitForText` test helper moved to `@MainActor` for correct actor isolation
- Inline `// swiftlint:disable` suppressions replaced with proper structural fixes

### Fixed
- UI alerts suppressed during automated test runs
- Actor isolation gaps in test helpers resolved
- Line-length warnings cleared across production and test files
- UI test app termination stabilised (no zombie processes between test runs)

---

## [1.0.0-beta.2] — 2026-01-04

### Added
- Rules organised into collapsible categories in the Rule Browser sidebar
- Minimum width constraints on `NavigationSplitView` columns (window is now freely resizable)
- Rule text panel inside the Rule Browser detail area
- On-demand documentation fetching with local caching (avoids network hits on every launch)
- Exclusion path recommendation engine — suggests common `.build`, `Pods`, `Carthage` paths based on detected project type

### Changed
- `RuleBrowserView` layout enhanced with full detail pane
- Documentation for categories feature added to PRD

### Fixed
- Build errors from file-system synchronised group references in `project.pbxproj`
- Parallel test execution isolation (each test suite gets its own `UserDefaults` domain)

---

## [1.0.0-beta.1] — 2025-12-26

### Added
- **Rule Browser** — searchable, filterable list of all SwiftLint rules with master-detail split view
- **Rule Detail View** — full documentation, code examples, severity picker, parameter editor, YAML diff preview
- **Violation Inspector** — browse, filter, group, and suppress violations with SQLite persistence
- **Impact Simulator** — simulate violations for disabled rules; detect zero-violation rules automatically
- **YAML Configuration Engine** — safe `.swiftlint.yml` editing with comment preservation, atomic writes, and backup
- **Workspace Analyzer** — background analysis engine with incremental re-analysis on file changes
- **Onboarding Flow** — first-run wizard: SwiftLint detection, workspace selection, initial configuration
- **Workspace Manager** — open, validate, and persist recent workspaces
- Default `.swiftlint.yml` with recommended exclusions bundled with the app
- Swift 6 strict concurrency enabled (`SWIFT_STRICT_CONCURRENCY = complete`)
- Comprehensive UI tests for Rule Browser, Violation Inspector, and Onboarding workflows
- SQLite-backed `ViolationStorage` actor for thread-safe persistence
- `DependencyContainer` for service-level dependency injection throughout the app

### Changed
- Repository flattened from nested git-submodule layout to single-repo structure

### Fixed
- SQLite string binding and violation accumulation bugs
- Onboarding flow validation for edge-case workspace paths
- `generate-docs` script updated to include all rules (not just a subset)
- Source code warnings from Xcode 16 / Swift 6 compiler cleared

---

[Unreleased]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/compare/v1.0.0-beta.5...v1.0.0
[1.0.0-beta.5]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/compare/v1.0.0-beta.4...v1.0.0-beta.5
[1.0.0-beta.4]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/compare/v1.0.0-beta.3...v1.0.0-beta.4
[1.0.0-beta.3]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/compare/v1.0.0-beta.2...v1.0.0-beta.3
[1.0.0-beta.2]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/compare/v1.0.0-beta.1...v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/Joseph-Cursio/SwiftLintRuleStudio/releases/tag/v1.0.0-beta.1
