# SwiftLint Rule Studio — Feature Reference

This document describes every control, field, and behavior in SwiftLint Rule Studio. It is organized by feature panel, not by workflow. If you are looking for step-by-step walkthroughs, see [USER_GUIDE.md](USER_GUIDE.md).

---

## Table of Contents

1. [Interface Overview](#1-interface-overview)
2. [Rule Browser](#2-rule-browser)
3. [Rule Detail Panel](#3-rule-detail-panel)
4. [Impact Simulation](#4-impact-simulation)
5. [Violation Inspector](#5-violation-inspector)
6. [Configuration Management](#6-configuration-management)
7. [Workspace Management](#7-workspace-management)
8. [Keyboard Shortcuts](#8-keyboard-shortcuts)
9. [Glossary](#9-glossary)

---

## 1. Interface Overview

### Window Layout

The main window uses a two-column `NavigationSplitView`:

| Column | Contents |
|--------|----------|
| **Sidebar** | Navigation links and workspace name |
| **Detail** | The selected panel fills this area |

### Sidebar Navigation Links

| Link | Panel |
|------|-------|
| Rules | Rule Browser |
| Violations | Violation Inspector |
| Dashboard | Summary statistics |
| Safe Rules | Safe Rules Discovery (batch simulation) |
| Version History | Configuration backup timeline |
| Compare Configs | Side-by-side config comparison |
| Version Check | SwiftLint version compatibility checker |
| Import Config | URL and file config importer |
| Branch Diff | Git branch configuration diff |
| Migration | Migration Assistant |

The workspace name and path are displayed at the top of the sidebar when a workspace is open.

### Split Panel Views

Rule Browser and Violation Inspector are both horizontal split views: a list panel on the left and a detail panel on the right. The left panel has a minimum width of 450 pt and a maximum of 560 pt. The detail panel takes all remaining space.

---

## 2. Rule Browser

### Search

The search field matches against three fields on each rule simultaneously:

| Field | What is matched |
|-------|-----------------|
| Identifier | `force_cast`, `line_length`, etc. |
| Name | Human-readable name (e.g., "Force Cast") |
| Description | Short description text (excluding placeholder "Loading…" text) |

Search is case-insensitive. The field has a clear button (✕) that appears only when text is present.

### Status Filter

The **Status** picker controls which rules are shown based on their configuration state.

| Option | What it shows |
|--------|---------------|
| **All** | Every rule regardless of state |
| **Enabled** | Rules where `isEnabled` is `true` in the loaded config |
| **Disabled** | Rules where `isEnabled` is `false` (includes unconfigured default-off rules) |
| **Opt-In** | Rules that are disabled by default in SwiftLint and must be explicitly added to `opt_in_rules` |

`Opt-In` is a subset of the SwiftLint rule set, not the same as `Disabled`. An opt-in rule can be either enabled (if added to `opt_in_rules`) or disabled (if it has not been).

### Category Filter

The **Category** picker filters to a single rule category. Categories include: Style, Idiomatic, Lint, Performance, Metrics, SwiftUI, and others. Each category entry shows a count of how many rules match the current status and search filters (i.e., counts respond to active filters).

### Sort Options

The **Sort** picker orders the filtered rule list.

| Option | Sort key |
|--------|----------|
| **Name** | Human-readable name, ascending, locale-sensitive |
| **Identifier** | Rule identifier string, ascending |
| **Category** | Category alphabetically, then by name within each category |

### Clear Filters

The **Clear Filters** toolbar button resets all three filters (search text, category, and status) simultaneously. The button is disabled when no filters are active.

### Multi-Select Mode

Multi-select mode is toggled with the **Multi-Select** toolbar button (checklist icon). When active, the button label reads **Exit Multi-Select**.

In multi-select mode:
- The rule list switches to multi-item selection. Clicking a row toggles it in/out of the selection set.
- Standard macOS list selection (click, Shift-click, Command-click) applies.
- The **Bulk Operation Toolbar** appears between the filter bar and the rule list.
- Rule detail is not shown — clicking a row selects it rather than navigating to its detail.

Exiting multi-select clears the selection and hides the Bulk Operation Toolbar.

### Bulk Operation Toolbar

The Bulk Operation Toolbar is visible only when multi-select mode is active. It shows the count of selected rules and provides four actions:

| Action | Effect |
|--------|--------|
| **Enable All** | Marks all selected rules as enabled in a proposed config; opt-in rules are added to `opt_in_rules` and removed from `disabled_rules` |
| **Disable All** | Marks all selected rules as disabled; rules are removed from `opt_in_rules` |
| **Set Severity** | Sets a uniform severity (Warning / Error) for all selected rules |
| **Preview** | Opens the YAML Diff Preview sheet showing the combined change for all selected rules |
| **Clear Selection** | Deselects all rules without exiting multi-select mode |

All bulk actions generate a diff and show the YAML Diff Preview sheet before writing anything to disk. Changes are saved as a single atomic write.

### Rule Preset Picker

A **Presets** toolbar menu applies curated rule sets as a filter overlay. Selecting a preset replaces the visible rule list with the preset's rules sorted alphabetically. Presets do not modify the config; they only change which rules are visible in the list.

---

## 3. Rule Detail Panel

### Header

The header shows the rule's human-readable name, its identifier beneath it, and a category badge in the top-right corner. Below the name, status badges are shown when applicable:

| Badge | Condition | Color |
|-------|-----------|-------|
| **Enabled** | Rule is active in the loaded config | Green |
| **Opt-In Rule** | `isOptIn == true` | Orange |
| **Auto-correctable** | `supportsAutocorrection == true` | Blue |
| **Swift X.X+** | A minimum Swift version is set | Secondary (gray) |

Badges are omitted if their condition is false.

### Description Section

Shows the SwiftLint rule description and, when available, the full markdown documentation rendered as styled text. If the short description text already appears in the markdown, the short description is suppressed to avoid duplication. A "Source: SwiftLint documentation" link appears below the rendered content and opens the official SwiftLint docs page for that rule.

### Why This Matters Section

Displays a rationale paragraph extracted from the markdown documentation. Shows "No rationale available" if the markdown does not contain a recognizable rationale section.

### Configuration Section

| Control | Description |
|---------|-------------|
| **Enable this rule** toggle | Enables or disables the rule in the pending config changes. Toggle state reflects the current saved configuration. |
| **Severity** picker | Visible when the rule is enabled. Segmented control with Warning / Error / Hint options. |
| **Parameters** | Visible when the rule is enabled and exposes configurable parameters. Each parameter is shown as a labeled field with its type and default value. |
| **"You have unsaved changes"** warning | Appears whenever `pendingChanges` is non-nil — i.e., any toggle, severity, or parameter change that has not yet been saved. |
| **Simulate Impact** button | Available when a workspace is open. Runs a background SwiftLint simulation and opens the Impact Simulation sheet. |

The **Preview Changes** and **Save** toolbar buttons appear only when pending changes exist:

| Button | Action |
|--------|--------|
| **Preview Changes** (eye icon) | Opens the YAML Diff Preview sheet. |
| **Save** (checkmark icon) | Writes the pending configuration to `.swiftlint.yml` and triggers re-analysis. Shows a spinner during the write. |

After a successful save, a "Configuration Saved" alert confirms the write. The alert states that the changes were written to the workspace's `.swiftlint.yml` file. A timestamped backup of the previous config is automatically created before the write.

### Current Violations Count

Shows how many violations the rule currently has in the workspace, loaded from `ViolationStorage`. Displays a spinner while counting. A count of zero is shown in green; any positive count is shown in orange.

### Related Rules

Lists up to five rules from the same category. Shows "+ N more" if more than five exist.

### Swift Evolution Section

Lists any Swift Evolution proposal URLs linked in the rule's markdown documentation.

---

## 4. Impact Simulation

### Single-Rule Simulation

The Impact Simulation sheet is opened from the Rule Detail panel's **Simulate Impact** button. It shows results for one rule at a time.

| Field | Description |
|-------|-------------|
| **Rule name and identifier** | Header identifying which rule was simulated |
| **Safe / Has violations** indicator | Green checkmark circle if `violationCount == 0`; orange warning triangle otherwise |
| **Violations** | Total count of violations that would be introduced |
| **Affected Files** | Count of unique files that contain at least one violation |
| **Simulation Time** | Wall-clock duration of the SwiftLint run, in seconds (two decimal places) |

When violations exist, up to 20 are listed with file path, line number, message, and severity icon. If there are more than 20, a "… and X more violations" note is shown.

When `isSafe` is true (zero violations), an **Enable Rule** button appears in the toolbar. Clicking it enables the rule immediately and closes the sheet.

### Safe Rules Discovery

Safe Rules Discovery (the **Safe Rules** sidebar link) simulates every disabled rule in sequence and collects those with zero violations.

| State | Description |
|-------|-------------|
| **Empty / not started** | Empty state with a "Start Discovery" prompt |
| **Discovering** | Progress view showing current rule index, total rules, and the rule ID being tested |
| **Results list** | Each discovered safe rule is shown as a row with a toggle checkbox and a "Zero violations • Safe to enable" label |

The **Enable Selected** button in the toolbar is enabled only when at least one rule is checked. It opens the standard YAML Diff Preview and save flow for all selected rules.

---

## 5. Violation Inspector

### Statistics Bar

Three count badges are always visible above the violation list:

| Badge | Value |
|-------|-------|
| **Total** | Count of violations matching current filters |
| **Errors** | Count of `.error` severity violations in the filtered set |
| **Warnings** | Count of `.warning` severity violations in the filtered set |

### Search

The search field matches violations against:
- File path (substring, case-insensitive)
- Rule identifier (substring, case-insensitive)
- Violation message (substring, case-insensitive)

### Filter Controls

All filter controls are in a horizontal scrollable bar. Multiple filters compose with AND logic (a violation must satisfy all active filters).

| Control | Description |
|---------|-------------|
| **Rule** menu | Multi-select dropdown. Only rule IDs present in the current violation set are listed. Multiple IDs can be active simultaneously. |
| **Severity** menu | Multi-select dropdown. Options: Error, Warning. |
| **Group** menu | Sets the grouping mode (see Grouping below). |
| **Sort** menu | Sets the sort key (see Sorting below). |
| **Clear** button | Appears when any filter is active. Resets search text, selected rule IDs, and selected severities simultaneously. |

Note: `selectedFiles` and `showSuppressedOnly` are available as ViewModel properties for programmatic use, but are not exposed as controls in the current filter bar UI.

### Grouping Options

| Option | Behavior |
|--------|----------|
| **None** | Flat list, no section headers |
| **File** | Grouped by `filePath`, sections sorted alphabetically |
| **Rule** | Grouped by `ruleID`, sections sorted alphabetically |
| **Severity** | Grouped by severity; Error sections appear before Warning |

### Sort Options

| Option | Sort key |
|--------|----------|
| **File** | `filePath` |
| **Rule** | `ruleID` |
| **Severity** | Severity level |
| **Date** | `detectedAt` timestamp |
| **Line** | Line number |

Sort direction can be **Ascending** or **Descending**.

### Violation Detail Panel

Selecting a violation opens its detail in the right panel.

| Section | Fields |
|---------|--------|
| **Header** | Severity badge; "Suppressed" label (if `suppressed == true`); "Resolved" label with green checkmark (if `resolvedAt != nil`) |
| **Rule** | `ruleID` as a title |
| **Location** | File path, line number, column (optional) |
| **Message** | Full violation message text |
| **Code Context** | Placeholder — code snippet loading is not yet implemented |
| **Actions** | Suppress button (if not already suppressed); Mark as Resolved button (if not already resolved) |

### Suppress Action

Clicking **Suppress** opens a dialog with an optional "Suppression Reason" text field (3–6 lines). If no reason is entered, the default reason "Suppressed via Violation Inspector" is used.

The suppression generates a `// swiftlint:disable:next <ruleID>` comment at the violation's location. Suppressed violations remain in the list with a "Suppressed" badge, but are excluded from violation counts.

To suppress multiple violations at once, select them in the list and use **Actions → Suppress Selected** (⌘⇧S).

To mark violations as resolved, use **Actions → Mark as Resolved** (⌘⇧R) from the toolbar when violations are selected.

### Open in Xcode

The **Open in Xcode** button in the violation detail panel opens the file at the exact line and column. The integration tries the following methods in order:

1. `/usr/bin/xed --line <N> <path>` — preferred, most reliable
2. `xcode://file?path=<path>&line=<N>&column=<N>` URL scheme — fallback
3. Opening the file in the default registered application — last resort

If none succeed, an "Error Opening File" alert is shown. Error cases include: file not found, invalid path, Xcode not installed, and general failure.

### Export

The **Export** toolbar menu provides four options:

| Option | Scope | Format |
|--------|-------|--------|
| Export Filtered as JSON | All violations in the current filtered view | JSON |
| Export Filtered as CSV | All violations in the current filtered view | CSV |
| Export Selected as JSON | Only the selected violations | JSON |
| Export Selected as CSV | Only the selected violations | CSV |

"Export Selected" options are disabled when no violations are selected.

**JSON format:** Pretty-printed with sorted keys. Dates are ISO 8601. The output is a JSON array of violation objects.

**CSV format:** 10 columns: Rule ID, File Path, Line, Column, Severity, Message, Detected At (ISO 8601), Resolved At (ISO 8601 or empty), Suppressed (true/false), Suppression Reason. String fields containing commas or quotes are RFC 4180 quoted.

**File naming:** `violations_{scope}_{YYYYMMDD_HHmmss}.{json|csv}`

---

## 6. Configuration Management

### YAML Diff Preview

The YAML Diff Preview sheet appears before any config write. It shows:

| Section | Content |
|---------|---------|
| Rule name / label | Identifies what is being changed (a rule name, "Version Comparison", or "N rules" for bulk ops) |
| Added rules | Rule IDs added to the config |
| Removed rules | Rule IDs removed from the config |
| Modified rules | Rule IDs whose configuration changed |
| Before / After YAML | Side-by-side or sequential raw YAML text of the old and new config |

The sheet has a **Save** (confirm) button and a **Cancel** button. Cancelling leaves the config unchanged.

### Version History

**Backup file format:**

Backups are stored in the same directory as `.swiftlint.yml`. The filename pattern is:

```
{configFileName}.{unixTimestamp}.backup
```

Example: `.swiftlint.yml.1703467200.backup`

The timestamp is a Unix epoch integer (seconds since 1970-01-01 UTC). Backups are listed newest-first.

**Backup list columns:**

| Column | Description |
|--------|-------------|
| Date / Time | Formatted date and time of the backup |
| File size | Human-readable byte count |

**Compare two backups:**

Click one backup to mark it as version **①** (highlighted in blue). Click a second to mark it as **②** (green). The diff panel on the right shows what changed between the two versions. Click **Clear** to deselect.

**Restore:**

Right-click any backup row → **Restore This Version**. Before restoring, the service automatically creates a safety backup of the current config (with the current Unix timestamp). The restore is a full content replacement.

**Prune toolbar menu:**

| Option | Keeps |
|--------|-------|
| Keep Last 5 | 5 most recent backups |
| Keep Last 10 | 10 most recent backups |
| Keep Last 20 | 20 most recent backups |

Older backups are deleted from disk. The Refresh button (↺) reloads the list from disk.

### Configuration Health Score

The Health Score is an integer 0–100 with a letter grade. It is calculated as a weighted sum of five sub-scores:

| Sub-score | Weight | What it measures |
|-----------|--------|-----------------|
| **Rules Coverage** | 40% | Proportion of rules enabled relative to the total rule set. Optimal target is ~50% of all rules enabled — below or above this moves the score down. |
| **Category Balance** | 20% | Fraction of rule categories that have at least one enabled rule. Higher coverage across categories is better. |
| **Opt-In Adoption** | 15% | Fraction of a curated set of recommended opt-in rules that are enabled. Curated list includes: `explicit_init`, `first_where`, `joined_default_parameter`, `redundant_nil_coalescing`, `sorted_first_last`, `contains_over_first_not_nil`, `empty_count`, `empty_string`, `flatmap_over_map_reduce`, `last_where`, `modifier_order`, `reduce_into`. |
| **No Deprecated Rules** | 10% | Penalizes use of rules on the deprecated list. 100 if no deprecated rules are in use. |
| **Path Configuration** | 15% | Rewards having `excluded` paths configured (base 50 → +25), especially common patterns like `Pods`, `Carthage`, `vendor`, `build`, `.build` (+15); and having `included` paths (+10). Maximum 100. |

**Grade thresholds:**

| Score | Grade | Display Name | Color |
|-------|-------|--------------|-------|
| 90–100 | A | Excellent | Green |
| 75–89 | B | Good | Blue |
| 60–74 | C | Fair | Yellow |
| 40–59 | D | Needs Work | Orange |
| 0–39 | F | Poor | Red |

**Recommendations** are generated with High / Medium / Low priority and may include an "Apply Preset" button when a preset ID is associated with the recommendation.

### Import Configuration

The Import Config panel accepts a URL to a remote `.swiftlint.yml` file.

**Import modes:**

| Mode | Behavior |
|------|----------|
| **Replace** | The imported config completely replaces the current `.swiftlint.yml`. A backup is created before writing. |
| **Merge** | Rules from the imported config are merged into the existing config. Imported rules override conflicts on a per-rule basis. `disabled_rules`, `opt_in_rules`, and `excluded` paths are unioned (combined). |

A preview is shown before applying, including validation errors (e.g., if the fetched YAML is empty or contains no rule definitions) and a diff against the current config when one exists.

### Git Branch Diff

The Git Branch Diff panel compares the current workspace's `.swiftlint.yml` against the same file on any local branch or tag.

**Prerequisites:** The workspace must be inside a git repository. If it is not, an error "The workspace is not a git repository" is shown.

**Available refs:** The panel lists all local branches and all tags. The current branch is identified separately.

**Comparison:** Fetches the `.swiftlint.yml` content from the selected ref using `git show <ref>:<path>` and generates a diff against the current file. If the config file does not exist on the selected ref, an error is shown.

The result is displayed in the standard YAML Diff Preview view.

### Template Library

The Template Library provides curated `.swiftlint.yml` starting points.

**Filter dimensions:**

| Dimension | Options |
|-----------|---------|
| **Project Type** | iOS App, macOS App, Swift Package, Framework, Other |
| **Coding Style** | Strict, Balanced, Lenient |

**Coding styles:**

| Style | Character |
|-------|-----------|
| **Strict** | Maximum rules enabled; enforces strong conventions |
| **Balanced** | Moderate rule set; suits most teams |
| **Lenient** | Minimal rules; suitable for legacy codebases or gradual adoption |

Templates are divided into **Built-in** (shipped with the app) and **Your Templates** (user-defined). Each template has a YAML preview that can be toggled. Applying a template opens the standard diff-then-save flow.

### Migration Assistant

The Migration Assistant detects configuration changes needed when upgrading between SwiftLint versions.

**Step types:**

| Step | Auto-apply | Description |
|------|-----------|-------------|
| Rename Rule | Yes | A rule was renamed; updates all config lists and the rules dict |
| Remove Deprecated Rule | Yes | A rule was removed; deletes it from all config lists |
| Update Parameter | Yes | A parameter was renamed on a specific rule |
| Manual Action | No | Informational only (e.g., new rules available to consider) |

Auto-applicable steps can be applied in bulk. Manual steps are flagged for human review.

### Compare Configs

The Compare Configs panel provides a side-by-side diff of two arbitrary config files (not limited to version history). Each config can be loaded from any path accessible to the app.

---

## 7. Workspace Management

### Valid Workspace Criteria

A directory is accepted as a workspace if it satisfies at least one of the following:

| Criterion | Indicator |
|-----------|-----------|
| Contains `.swift` source files | Any `.swift` file anywhere in the directory tree |
| Contains an Xcode project | A `.xcodeproj` bundle in the directory |
| Contains an Xcode workspace | A `.xcworkspace` bundle in the directory |
| Contains a Swift package | A `Package.swift` file in the directory |

If none of these are present, a `notASwiftProject` error is shown with a descriptive message.

### Recent Workspaces

- The app stores up to **10** recent workspaces in `UserDefaults`.
- Re-opening a workspace that is already in the recent list moves it to the top and updates its `lastAnalyzed` timestamp.
- Recent workspaces are listed in the Workspace Selection screen after onboarding.

### Re-Analysis Triggers

SwiftLint re-runs in the background after:

- Saving a rule configuration change (single rule or bulk)
- Restoring a config version from Version History
- Importing a config via the Import panel
- Applying a template
- The workspace changing

Results are stored in `ViolationStorage` (a SQLite-backed actor) and the Violation Inspector refreshes automatically via Combine bindings.

### Missing Config File

If the current workspace has no `.swiftlint.yml`, a `ConfigRecommendationView` banner is shown at the top of the detail area. It offers to create a default config file.

---

## 8. Keyboard Shortcuts

| Shortcut | Context | Action |
|----------|---------|--------|
| ⌘O | Global | Open Workspace (File → Open Workspace…) |
| ⌘A | Violation Inspector | Select all violations in the current filtered view |
| ⌘⇧A | Violation Inspector | Clear selection |
| ⌘→ | Violation Inspector | Select next violation |
| ⌘← | Violation Inspector | Select previous violation |
| ⌘⇧S | Violation Inspector (selection active) | Suppress selected violations |
| ⌘⇧R | Violation Inspector (selection active) | Mark selected violations as resolved |

---

## 9. Glossary

| Term | Definition |
|------|------------|
| **Auto-correctable** | A rule for which SwiftLint can automatically fix violations using `swiftlint --fix`. Marked with a wand badge in the Rule Detail header. |
| **Config** | Short for `.swiftlint.yml`, the YAML configuration file that controls which rules are active and how they are parameterized. |
| **Disabled Rule** | A rule that is not currently producing violations. This includes rules explicitly listed under `disabled_rules` and opt-in rules that have not been added to `opt_in_rules`. |
| **Enabled Rule** | A rule that is currently active and will be checked during a SwiftLint run. Default-on rules are enabled unless explicitly disabled; opt-in rules are enabled only when listed under `opt_in_rules`. |
| **Health Score** | A 0–100 integer measuring the quality of the workspace `.swiftlint.yml` on five dimensions (coverage, balance, opt-in adoption, deprecation, path config). See [Configuration Health Score](#configuration-health-score). |
| **Opt-In Rule** | A SwiftLint rule that is **off by default** across all projects. It must be explicitly enabled by adding its identifier to `opt_in_rules` in the config. Opt-in rules are visually distinguished with an orange "Opt-In Rule" badge. |
| **Severity** | The level at which a violation is reported. Options: `warning` (non-blocking, shown in orange), `error` (blocking, shown in red), `hint` (informational). The default severity for most rules is `warning`. |
| **Simulation** | A dry-run of SwiftLint using a temporary config that includes a rule not currently in the workspace config. The result shows how many violations the rule would produce without actually modifying the config. |
| **Suppressed Violation** | A violation that has been intentionally acknowledged via a `// swiftlint:disable:next <ruleID>` inline comment. Suppressed violations remain in the database but are excluded from counts. |
| **Violation** | A specific location in source code where a SwiftLint rule was triggered. Identified by rule ID, file path, line, column, severity, and message. |
| **Workspace** | A directory containing a Swift project (identified by the presence of `.swift` files, `.xcodeproj`, `.xcworkspace`, or `Package.swift`). The app operates on one workspace at a time. |
