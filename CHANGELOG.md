# Changelog

All notable changes to SwiftLint Rule Studio are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Changed
- Configuration backups are kept in the app's own folder (`~/Library/Application Support/SwiftLintRuleStudio/Config Backups/`, inside the container for the sandboxed Explorer edition) instead of beside `.swiftlint.yml`, where each save left an untracked `.swiftlint.yml.<timestamp>.backup` in the project. Each configuration keeps 50 backups in all: the oldest plus the 49 newest. Version History still lists backups an earlier version left in the project folder, and offers to move them out (the originals go to the Trash, and the moved copies are never pruned automatically); nothing moves them automatically.
- No backup is taken when the file hasn't changed since the newest backup, two backups in the same second no longer overwrite each other, and a backup holds the configuration's bytes even when `.swiftlint.yml` is a symlink.
- Simulation copies of a workspace are now kept in `~/Library/Caches` (the app's caches folder) rather than the temp folder, except for workspaces under `/tmp` or `/var`, which are copied into the temp folder. A workspace on a volume that treats letter case differently is copied onto that volume
- Workspace analysis lints now run through the same cancellable runner as simulations, with `PWD` set to the workspace
- When a workspace can't be simulated faithfully, each affected rule shows why instead of a count. Examples: an absolute or remote `parent_config`; an `included` path more than eight folders above the workspace; a symlink loop SwiftLint would crash on; a config SwiftLint can't read; a workspace opened through a symlink; more than 20,000 files reached outside the workspace
- The sandboxed Explorer edition's workspace analysis now applies the nested `.swiftlint.yml` files beneath a workspace's own, as Studio's analysis does and as `swiftlint lint` does on the command line and in CI. Files beneath a nested config are now reported by its rules; before, the Explorer applied the workspace's root config alone to them

### Fixed
- Saving no longer writes a `.swiftlint.yml` SwiftLint rejects (#83). With `only_rules` in use, enabling a rule added it to `opt_in_rules` (and an analyzer rule to both `only_rules` and `analyzer_rules`); SwiftLint refuses `opt_in_rules` or `disabled_rules` beside `only_rules` and falls back to its defaults, ignoring `included` and `excluded`. Rules now go to the list SwiftLint reads in each mode, and a save that would produce a rejected file is refused.
- A configuration SwiftLint already rejects for this reason is flagged in a banner, with a fix to review before it's saved; the rule browser, Rule Audit and imports no longer edit such a file.
- A rule list, `included` or `excluded` written as a single string (`only_rules: force_cast`, `excluded: Pods`) is read as a one-entry list, as SwiftLint reads it, instead of being dropped on the next save. A list with no entries (`opt_in_rules:` or `~`) is read as no list. The deprecated `enabled_rules` is read when `opt_in_rules` is absent, and written back as `opt_in_rules`.
- A rule option holding a list of mappings, such as `number_separator`'s `exclude_ranges`, is saved as valid YAML. Saving any change used to misalign the second key of each entry, so SwiftLint could no longer parse the file and fell back to its default configuration.
- The version compatibility report and the Migration Assistant no longer rename live rules. Their rename table listed rules that still exist under their own names, such as `generic_type_name` and `multiple_closures_with_trailing_closure`, so "Fix" rewrote a valid config to run a different rule. The table now holds only renames SwiftLint itself resolves through an alias. Every rename, deprecation, removal and rule-addition version is dated from the SwiftLint release that first ships it, and a test pins the table against the linked SwiftLint.
- A rule written as a severity shorthand (`redundant_self_in_closure: error`) is now reported and renamed, and the Migration Assistant offers Apply for a change that touches only such rules or a rule list, instead of saying "No changes needed".
- Renaming a rule whose new name is already configured merges the two configurations instead of dropping the old one's settings.
- A pre-release SwiftLint (`0.50.0-rc.1`) is treated as older than its release, so it isn't told to rename to, or enable, a rule that only exists from the release on. A leading `v` is ignored.
- `enabled_rules` and `indentation` are no longer reported as rules.
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
- The sandboxed Explorer edition no longer quits on a nested `.swiftlint.yml` SwiftLint can't use in three places its check used to miss: above a config the workspace's own pulls in with `child_config`, beside an `included` folder that is a link, and above a workspace opened in `/tmp` or `/var`. The analysis or Rule Audit fails with the reason instead, as for other nested configs. A config beside a link's target, which SwiftLint never reads, no longer fails them
- The sandboxed Explorer edition now applies a `.swiftlint.yml` above a workspace opened in `/tmp` or `/var` whose own config names no `parent_config` or `child_config` and has no `excluded`, as Studio and `swiftlint lint` do (#102). It used to stop at the workspace's own config, so the two editions reported different violations for the same workspace. A config there that the sandbox lets the Explorer see but not read now fails the analysis with the reason, as it already did for such a workspace with no config or with a `child_config`
- In the Explorer, an `excluded` entry naming a folder symlink in a workspace opened in `/tmp` or `/var` no longer skips it, as in `swiftlint lint`: SwiftLint keeps `/private` on the patterns but not on the link's path. Excluded folders that aren't symlinks are skipped as before. A symlink there to a folder outside the workspace is now linted. A symlink that loops back into a folder holding it is refused (`swiftlint lint` crashes on it), and the refusal now says to exclude the folder that holds the link, or remove it, instead of telling you to add it to `excluded`
- Rule Audit no longer refuses a workspace in `/tmp` or `/var` whose symlink loop lies inside an excluded folder that `swiftlint lint` never walks into. There SwiftLint does skip an excluded folder, but never a symlink, the folder a symlink leads into, or the folder an `included` walk starts from, so a loop behind one of those is still refused. The reason no longer says to add the symlink to `excluded`, which SwiftLint ignores there; it names the folder to exclude when that would keep SwiftLint out, and otherwise says to remove the link
- Rule Audit no longer leaves out of its copy a symlink that `swiftlint lint` follows on the way to what it lints, when the same symlink comes back round only on a route SwiftLint never takes. The files behind it went uncounted. It now also refuses an `included` entry that runs through a symlink back into a folder holding it, and a loop beneath a walk an `included` entry starts, which SwiftLint crashes on and the audit used to measure
- Rule Audit applies an `excluded` entry written as an absolute path, from `~/`, or climbing above the folder holding the workspace in its copy of the workspace as `swiftlint lint` applies it in the workspace. The copy used to keep such an entry as written, still naming the original folders, so it counted the files the entry excludes. An entry whose folders start above the workspace's folder with a pattern, which the copy can't place, is refused
- Rule Audit counts a `.swift` file an `included` entry names through a symlink that leads back into a folder holding it, which `swiftlint lint` lints through the link once; the copy used to leave the link out and count nothing there. With nothing excluded, it no longer refuses an `included` entry through such a link either
- With `excluded` set, Rule Audit reads an `included` folder beside the workspace spelled through a symlink as `swiftlint lint` does, by its real path: it no longer counts its files twice when another link reaches them, ignores an exclusion naming their real place, or applies one written through the link
- Rule Audit no longer trusts a parent config's `excluded` entry that SwiftLint drops because a child config includes the same path, which let it measure a workspace `swiftlint lint` crashes on
- Rule Audit refuses a workspace whose path above it holds a `[` when the configuration has `included` or `excluded` entries: SwiftLint reads the `[` as a pattern, so those entries name nothing there, and the audit used to count as if they did
- Outside `/tmp` and `/var`, Rule Audit no longer refuses a workspace whose symlink loop SwiftLint never reaches because an excluded folder or symlink lies on the way to it: `swiftlint lint` matches every folder and symlink it meets by its real path and skips an excluded one, as it does the looping symlink itself. When it does refuse a loop, the reason names the symlink by its real path, which is what an `excluded` entry has to name, written so SwiftLint doesn't read it as a glob. Outside `/tmp` and `/var` it no longer counts on an exclusion matching a path that holds an accented letter or an emoji, which SwiftLint may match short and walk on
- Rule Audit matches `excluded` globs as SwiftLint does, and counts on an exclusion only where SwiftLint surely applies it: a `*` followed by more of the pattern no longer reaches past where SwiftLint's matcher stops (so `*/**/Gen/*/Mocks` doesn't take `A/Gen/B/Gen/Mocks`), a `[` inside brackets stands for itself, a range running backwards matches nothing, `&`, `~` or `|` inside brackets match nothing, and a path must match both minding and ignoring case, as SwiftLint ignores it. It used to think some symlinks excluded that SwiftLint follows round until it crashes

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
