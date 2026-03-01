# SwiftLint Rule Studio — User Guide

SwiftLint Rule Studio is a native macOS app that gives you a visual interface for managing SwiftLint rules in your Swift projects. Instead of hand-editing `.swiftlint.yml` and memorizing hundreds of rule identifiers, you can browse rules with full documentation, simulate the impact of enabling a rule before touching your config, and inspect violations with one-click Xcode navigation. The app wraps the SwiftLint CLI — it does not replace it.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Browsing & Searching Rules](#2-browsing--searching-rules)
3. [Understanding a Rule](#3-understanding-a-rule)
4. [Simulating Impact Before Enabling](#4-simulating-impact-before-enabling)
5. [Enabling or Disabling a Rule](#5-enabling-or-disabling-a-rule)
6. [Inspecting Violations](#6-inspecting-violations)
7. [Opening a Violation in Xcode](#7-opening-a-violation-in-xcode)
8. [Bulk Rule Operations](#8-bulk-rule-operations)
9. [Discovering Safe Rules](#9-discovering-safe-rules)
10. [Configuration Version History](#10-configuration-version-history)
11. [Suppressing Violations](#11-suppressing-violations)
12. [Tips](#12-tips)

---

## 1. Getting Started

### Prerequisites

- **macOS 13.0 (Ventura)** or later
- **SwiftLint installed and on your `$PATH`** — the app calls `swiftlint rules` and `swiftlint lint` under the hood. If you don't have SwiftLint yet, the onboarding wizard will show you installation options.

### First Launch — Onboarding Wizard

The first time you open SwiftLint Rule Studio, a four-step wizard walks you through setup.

**Step 1 — Welcome**

You'll see an overview of the app's three main features: Browse Rules, Inspect Violations, and Configure Rules. Click **Next** to continue.

**Step 2 — SwiftLint Installation**

The app checks your `$PATH` for a SwiftLint installation and displays the detected version and path. If SwiftLint is not found, you'll see three installation options:

| Method | Command |
|--------|---------|
| Homebrew (recommended) | `brew install swiftlint` |
| Mint | `mint install realm/SwiftLint` |
| Direct download | GitHub Releases page |

After installing, click **Check Again** to re-detect. Once SwiftLint is found, click **Next**.

**Step 3 — Select Your Workspace**

Click **Select a Workspace** and choose a directory that contains your Swift project. A valid workspace must contain `.swift` files, an `.xcodeproj`, or a `Package.swift`. The button stays disabled until you choose a valid directory.

**Step 4 — You're All Set!**

Onboarding is complete. Click **Get Started** to open the main interface.

### Opening a Workspace Later

- **Menu bar:** File → Open Workspace… (⌘O)
- **Home screen:** Pick from the Recent Workspaces list (the app remembers up to 10 recent workspaces)

---

## 2. Browsing & Searching Rules

Use the Rule Browser to find rules, filter by status or category, and navigate to their detail pages.

The Rule Browser is a split view: the left panel shows the rule list and the right panel shows details for the selected rule.

**Searching**

Type in the **Search rules…** field to filter by rule name, identifier, or any keyword in the description. Click the **✕** in the search bar to clear.

**Filtering by Status**

Use the **Status** picker to show only:
- **All** — every rule
- **Enabled** — rules currently active in your config
- **Disabled** — rules not yet active
- **Opt-In** — rules that are off by default in SwiftLint and must be explicitly enabled

Each status shows a count badge.

**Filtering by Category**

Use the **Category** picker to narrow the list to a specific rule category (e.g., Style, Performance, SwiftUI). Each category shows a rule count.

**Sorting**

Use the **Sort** picker to order rules by Name, Identifier, or Category.

**Clearing Filters**

Click **Clear Filters** in the toolbar to reset all active filters at once. The button is disabled when no filters are applied.

---

## 3. Understanding a Rule

Clicking a rule in the list opens its detail panel on the right. This is the primary reference for learning what a rule does before you decide to enable it.

**Header**

Shows the rule name, identifier, category badge, and status labels:
- **Enabled** (green checkmark) — the rule is active in your config
- **Opt-In Rule** — must be explicitly enabled; not active by default
- **Auto-correctable** — SwiftLint can fix violations for this rule with `--fix`
- **Swift X.X+** — the minimum Swift version required (when applicable)

**Description & Documentation**

The main body renders the full SwiftLint documentation for the rule, including rationale text explaining *why* the rule exists.

**Triggering & Non-Triggering Examples**

Code samples that would be flagged (triggering) and compliant alternatives (non-triggering) are shown directly in the panel.

**Current Violations**

A count badge shows how many violations this rule has found in your current workspace, updated after each analysis run.

**Related Rules & Swift Evolution Links**

Where available, the panel links to related rules and any Swift Evolution proposals the rule is based on.

---

## 4. Simulating Impact Before Enabling

Before enabling a rule — especially an opt-in rule in a large codebase — use Simulate Impact to see exactly what would break, without touching your config.

1. Select a **disabled** rule in the Rule Browser.
2. In the Rule Detail panel, click **Simulate Impact**.
3. The app creates a temporary config with the rule enabled and runs SwiftLint in the background.
4. The simulation results sheet shows:
   - **Violations** — total count (green if zero, orange if any)
   - **Affected Files** — number of files that would be flagged
   - **Simulation Time** — how long the run took (in seconds)
   - A list of the first 20 violations (file path, line, message, severity)
   - A note like "… and X more violations" if there are more than 20
5. If the rule is safe (zero violations), an **Enable Rule** button appears — click it to enable the rule immediately without leaving the simulation sheet.
6. To dismiss without making any changes, close the sheet. Your config is untouched.

---

## 5. Enabling or Disabling a Rule

Making a configuration change follows a preview-then-save flow to keep you in control.

1. Select a rule in the Rule Browser.
2. In the Rule Detail panel, toggle the **Enable this rule** switch.
3. When enabled, you can also:
   - Change the **Severity** (Warning / Error / Hint) using the segmented control
   - Adjust **Parameters** if the rule exposes configurable options
4. An "You have unsaved changes" warning appears in the panel.
5. Click **Preview Changes** (eye icon in the toolbar) to see a YAML diff showing the exact lines that will be added, removed, or modified in `.swiftlint.yml`.
6. Review the diff, then click **Save** (checkmark icon).
   - The app writes a timestamped backup of your current `.swiftlint.yml` before overwriting it.
   - SwiftLint re-runs automatically in the background.
   - The Violation Inspector refreshes with updated results.

A "Configuration Saved" confirmation appears when the write succeeds. If an error occurs, an alert describes the problem.

---

## 6. Inspecting Violations

The Violation Inspector shows every SwiftLint violation found in your workspace after each analysis run.

**Searching**

Use the search bar to filter violations by file path, rule identifier, or message text.

**Filtering**

Narrow the violation list by rule ID, severity (warning or error), file path, or show only suppressed violations.

**Grouping & Sorting**

Group violations by File, Rule, Severity, or Date. Sort by File, Rule, Severity, Line Number, or Date.

**Selecting Violations**

- Use **⌘A** (Select All) to select everything in the current filtered view.
- Use **⌘⇧A** (Clear Selection) to deselect.
- Use **Next** (⌘→) and **Previous** (⌘←) to step through violations one at a time.

**Violation Detail**

Click a violation to open its detail in the right panel:
- Severity badge (Error or Warning)
- Suppressed / Resolved status labels
- Rule identifier
- Full file path, line number, and column
- Complete violation message
- Code context snippet

**Exporting Violations**

Use the **Export** toolbar menu to save violations as JSON or CSV:
- **Export Filtered** — exports everything matching your current search/filter
- **Export Selected** — exports only the violations you have selected

---

## 7. Opening a Violation in Xcode

Jump directly from any violation to the exact file and line in Xcode — no manual searching needed.

1. Select a violation in the Violation Inspector to open its detail panel.
2. Click **Open in Xcode** (the arrow-in-circle button next to the file path).
3. Xcode comes to the foreground and scrolls to the exact location.

If Xcode cannot open the file, an "Error Opening File" alert will describe the issue.

---

## 8. Bulk Rule Operations

When you want to enable or disable many rules at once, multi-select mode lets you preview all changes in a single YAML diff before committing anything.

1. In the Rule Browser toolbar, click **Multi-Select** (the checklist icon). The button label changes to **Exit Multi-Select** while active.
2. Check each rule you want to modify.
3. The **Bulk Operation Toolbar** appears at the bottom of the rule list with these actions:
   - **Enable All** — enable every selected rule
   - **Disable All** — disable every selected rule
   - **Set Severity** — set a uniform severity across all selected rules
   - **Clear Selection** — deselect everything
4. Click **Preview** to see the combined YAML diff for all selected rules.
5. Click **Save** — all changes are written in a single atomic operation with one backup created.

---

## 9. Discovering Safe Rules

Use Batch Simulation (also called Safe Rules Discovery) to quickly find every disabled rule that would introduce zero violations in your workspace — the easiest wins for improving your config.

1. Navigate to the **Safe Rules Discovery** section in the sidebar.
2. Click **Start Discovery**. The app simulates every disabled rule in sequence, running SwiftLint for each.
3. A progress indicator tracks completion. Rules with zero violations are collected into a results list as they finish.
4. Multi-select any rules from the results list that you want to enable.
5. Click **Enable Selected** to enable them all at once (a YAML diff preview and save flow follows, same as section 5).

---

## 10. Configuration Version History

Every time you save a rule change, the app automatically creates a timestamped backup of your `.swiftlint.yml`. Version History lets you browse these backups and compare any two versions side by side.

**Viewing Backups**

Open **Version History** from the sidebar or configuration panel. The backup list shows each version's date, time, and file size.

**Comparing Two Versions**

1. Click a backup to mark it as version **①** (highlighted in blue).
2. Click a second backup to mark it as version **②** (highlighted in green).
3. The diff panel on the right shows exactly what changed between the two versions.

**Restoring a Version**

Right-click any backup row and choose **Restore This Version**. A confirmation alert reminds you that a safety backup of your current config will be created first before the restore happens.

**Pruning Old Backups**

Click the **Prune** toolbar menu to keep only the most recent backups:
- Keep Last 5
- Keep Last 10
- Keep Last 20

Use **Refresh** (↺) to reload the backup list if you made changes outside the app.

---

## 11. Suppressing Violations

When a violation is intentional or acceptable in a specific location, you can suppress it with an inline comment.

1. Select a violation in the Violation Inspector.
2. In the detail panel, click **Suppress**.
3. Enter an optional reason in the suppression dialog.
4. The app generates the appropriate `// swiftlint:disable:next` comment at the violation's location.
5. Suppressed violations remain in the list (with a distinct "Suppressed" badge) but are excluded from violation counts.

To bulk-suppress multiple violations at once, select them in the list and use **Actions → Suppress Selected** (⌘⇧S).

---

## 12. Tips

| Tip | Detail |
|-----|--------|
| **Always simulate before enabling** | Use Simulate Impact for any rule before enabling — especially opt-in rules in large codebases. The simulation leaves your config untouched. |
| **Backups are automatic** | Every config save creates a timestamped backup. You can browse and restore any backup in Version History. |
| **Violations refresh automatically** | After any config change, SwiftLint re-runs in the background. You don't need to manually trigger a refresh. |
| **Use multi-select for large changes** | Batch operations let you preview all changes in a single YAML diff before writing anything. |
| **Your comments are preserved** | The YAML engine preserves existing comments and key ordering in your `.swiftlint.yml`. |
| **Missing config** | If your workspace has no `.swiftlint.yml`, the app will offer to create a default one for you. |
| **Export for reporting** | Use the Export menu in the Violation Inspector to share JSON or CSV violation reports with your team. |
