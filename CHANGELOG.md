# Changelog

All notable changes to SwiftLint Rule Studio are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

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
