# SwiftLint YAML Configuration Features

This document provides comprehensive details on SwiftLint Rule Studio's YAML configuration capabilities, including existing implementations and recommended new features.

---

## Table of Contents

1. [Current Capabilities](#current-capabilities)
2. [Recommended New Features](#recommended-new-features)
   - [Configuration Templates & Presets](#1-configuration-templates--presets)
   - [Configuration Comparison & Analysis](#2-configuration-comparison--analysis)
   - [Import/Export & Sharing](#3-importexport--sharing)
   - [Advanced Editing](#4-advanced-editing)
   - [History & Versioning](#5-history--versioning)
   - [Validation & Migration](#6-validation--migration)
   - [Integration Features](#7-integration-features)
3. [Implementation Priority](#implementation-priority)
4. [Code References](#code-references)

---

## Current Capabilities

The following YAML configuration features are already implemented in SwiftLint Rule Studio.

### YAML Loading/Parsing

| Aspect | Details |
|--------|---------|
| **Description** | Load and parse `.swiftlint.yml` files using the Yams library |
| **Implementation** | `YAMLConfigurationEngine.load()` reads file content, parses via `Yams.compose()`, and converts Node to internal `YAMLConfig` model |
| **Supported Fields** | `rules`, `included`, `excluded`, `reporter`, `disabled_rules`, `opt_in_rules`, `analyzer_rules`, `only_rules`, `warning_threshold`, `strict` |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:77-122` |

### Configuration Editing

| Aspect | Details |
|--------|---------|
| **Description** | Modify rules, severities, and parameters through the UI without manual YAML editing |
| **Implementation** | `YAMLConfig` struct holds mutable configuration state; `RuleConfiguration` tracks enabled state, severity, and custom parameters per rule |
| **Capabilities** | Enable/disable rules, change severity (warning/error), modify rule parameters |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:19-47`, `UI/ViewModels/RuleDetailViewModel.swift` |

### Diff Preview

| Aspect | Details |
|--------|---------|
| **Description** | Visual diff showing added, removed, and modified rules before saving changes |
| **Implementation** | `ConfigDiff` struct computes set differences between current and proposed configurations; `ConfigDiffPreviewView` displays summary and full YAML diff |
| **Views** | Summary view with color-coded rule lists (green=added, red=removed, orange=modified); Full diff view with before/after YAML |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:49-60`, `UI/Views/Configuration/ConfigDiffPreviewView.swift` |

### Atomic File Writes

| Aspect | Details |
|--------|---------|
| **Description** | Safe saves using temporary files to prevent corruption from interrupted writes |
| **Implementation** | Writes to UUID-named temp file first (`{filename}.{UUID}.tmp`), then atomically moves to final location |
| **Benefits** | Prevents partial writes, handles parallel operations safely, no data loss on crash |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:214-227` |

### Timestamped Backups

| Aspect | Details |
|--------|---------|
| **Description** | Automatic backup creation before any configuration modification |
| **Implementation** | Creates backup with timestamp: `{filename}.{unix_timestamp}.backup` before modifying original |
| **Location** | Same directory as original config file |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:193-208` |

### Comment Preservation

| Aspect | Details |
|--------|---------|
| **Description** | Preserves YAML comments when editing configuration |
| **Implementation** | `extractComments()` parses original content for comments; `reinsertComments()` adds them back during serialization |
| **Limitation** | Comments are currently appended at end of output rather than inline with original positions |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine+Comments.swift` |

### Validation

| Aspect | Details |
|--------|---------|
| **Description** | Validates configuration before saving to catch errors early |
| **Implementation** | `validate()` method checks severity values (must be "warning" or "error") and validates file paths are non-empty |
| **Error Types** | `invalidSeverity`, `invalidPath`, `parseError`, `serializationError` |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:159-185` |

### Impact Simulation

| Aspect | Details |
|--------|---------|
| **Description** | Simulate enabling rules without making permanent configuration changes |
| **Implementation** | `ImpactSimulator` creates temporary configs, runs SwiftLint, and returns violation counts without modifying actual config |
| **Output** | `RuleImpactResult` with violation count, affected files, and simulation duration |
| **Code Reference** | `Core/Services/ImpactSimulator.swift:66-112` |

### Safe Rules Discovery

| Aspect | Details |
|--------|---------|
| **Description** | Find disabled rules that would produce zero violations if enabled |
| **Implementation** | `findSafeRules()` batch simulates all disabled rules and filters to those with zero violations |
| **Use Case** | Identify rules that can be safely enabled to improve code quality without breaking builds |
| **Code Reference** | `Core/Services/ImpactSimulator.swift:175-194` |

### Default Template

| Aspect | Details |
|--------|---------|
| **Description** | Create sensible default configuration for new workspaces |
| **Implementation** | `YAMLConfig()` initializer provides empty but valid structure; can be populated with recommended defaults |
| **Included Defaults** | Empty rules dictionary, nil for optional fields |
| **Code Reference** | `Core/Services/YAMLConfigurationEngine.swift:35-46` |

---

## Recommended New Features

### 1. Configuration Templates & Presets

#### Template Library

| Aspect | Details |
|--------|---------|
| **Description** | Built-in templates for common project types and coding styles |
| **Templates** | iOS App, macOS App, Swift Package, tvOS App, watchOS App |
| **Styles** | Strict (maximum rules), Balanced (recommended rules), Lenient (minimal rules) |
| **Complexity** | Medium |
| **Implementation Notes** | Create `ConfigurationTemplateManager` service with bundled JSON/YAML templates; UI picker in workspace setup flow |
| **Suggested Location** | `Core/Services/ConfigurationTemplateManager.swift` |

#### Save As Template

| Aspect | Details |
|--------|---------|
| **Description** | Save current workspace configuration as a reusable custom template |
| **Features** | Name template, add description, optional tags, store in user library |
| **Complexity** | Medium |
| **Implementation Notes** | Persist templates to `~/Library/Application Support/SwiftLintRuleStudio/Templates/`; include metadata JSON alongside YAML |
| **UI Integration** | "Save as Template" button in configuration view toolbar |

#### Rule Presets

| Aspect | Details |
|--------|---------|
| **Description** | Named groups of rules for batch enable/disable operations |
| **Preset Examples** | Performance (rules affecting runtime), SwiftUI (SwiftUI-specific rules), Concurrency Safety (async/await rules), Code Style (formatting rules) |
| **Complexity** | Low |
| **Implementation Notes** | Define presets as static data in `RulePresets.swift`; integrate with rule browser for "Enable Preset" action |
| **Data Structure** | `struct RulePreset { let name: String; let description: String; let ruleIds: [String] }` |

---

### 2. Configuration Comparison & Analysis

#### Cross-Project Comparison

| Aspect | Details |
|--------|---------|
| **Description** | Side-by-side diff of configurations from two different workspaces |
| **Features** | Select two workspaces, view differences in enabled rules, severities, and parameters |
| **Complexity** | Medium |
| **Implementation Notes** | Extend `ConfigDiff` to support two arbitrary configs; new `ConfigComparisonView` with dual-pane layout |
| **Use Case** | Standardize configurations across team projects |

#### Git Branch Diff

| Aspect | Details |
|--------|---------|
| **Description** | Compare current configuration against different git branches or commits |
| **Features** | Select branch/commit, show config changes, optionally cherry-pick settings |
| **Complexity** | Medium-High |
| **Implementation Notes** | Use `git show {branch}:.swiftlint.yml` to fetch config from other branches; parse and diff |
| **Dependencies** | Requires git CLI access via `Bash` |

#### Config Health Score

| Aspect | Details |
|--------|---------|
| **Description** | Analyze configuration quality and provide improvement recommendations |
| **Scoring Factors** | Number of enabled rules, coverage of rule categories, use of deprecated rules, missing recommended rules |
| **Output** | Score (0-100), list of recommendations, comparison to community standards |
| **Complexity** | Low |
| **Implementation Notes** | Pure computation on current config; no external dependencies |
| **Suggested Location** | `Core/Services/ConfigurationHealthAnalyzer.swift` |

---

### 3. Import/Export & Sharing

#### Export Package

| Aspect | Details |
|--------|---------|
| **Description** | Export configuration with metadata as a shareable bundle |
| **Package Contents** | `.swiftlint.yml`, `manifest.json` (version, author, description), optional `README.md` |
| **Format** | `.swiftlintconfig` directory or ZIP archive |
| **Complexity** | Low |
| **Implementation Notes** | Create temporary directory, copy files, compress; use `NSFileCoordinator` for safety |

#### Import from URL

| Aspect | Details |
|--------|---------|
| **Description** | Import configurations from GitHub repositories, gists, or internal URLs |
| **Supported Sources** | GitHub raw URLs, GitHub Gists, any HTTPS URL returning YAML |
| **Features** | Preview before import, validate syntax, merge vs replace options |
| **Complexity** | Medium |
| **Implementation Notes** | Fetch via `URLSession`, validate YAML structure, present diff before applying |
| **Security** | Validate URL schemes, limit to known hosts optionally |

#### PR Comment Generator

| Aspect | Details |
|--------|---------|
| **Description** | Generate Markdown summary of configuration changes suitable for pull requests |
| **Output Format** | Markdown with added/removed/modified rules, severity changes, parameter changes |
| **Features** | Copy to clipboard, optionally include violation impact estimates |
| **Complexity** | Low |
| **Implementation Notes** | Transform `ConfigDiff` to Markdown string; add "Copy for PR" button to diff preview |

---

### 4. Advanced Editing

#### Visual Parameter Editor

| Aspect | Details |
|--------|---------|
| **Description** | GUI for editing rule parameters with appropriate controls |
| **Control Types** | Sliders for numeric values, toggles for booleans, text fields for strings, lists for arrays |
| **Features** | Live validation, default value indicators, documentation tooltips |
| **Complexity** | Medium-High |
| **Implementation Notes** | Extend `RuleDetailView` with parameter-specific editors; requires parameter schema from rule metadata |
| **Suggested Location** | `UI/Components/RuleParameterEditor.swift` |

#### Bulk Rule Operations

| Aspect | Details |
|--------|---------|
| **Description** | Multi-select rules for batch enable/disable/severity changes |
| **Operations** | Enable selected, disable selected, set severity to warning, set severity to error |
| **Features** | Selection mode in rule browser, operation toolbar, preview changes before apply |
| **Complexity** | Medium |
| **Implementation Notes** | Add selection state to `RuleBrowserViewModel`; batch update through `YAMLConfigurationEngine` |

#### Path Pattern Builder

| Aspect | Details |
|--------|---------|
| **Description** | Visual editor for include/exclude path patterns with live preview |
| **Features** | Pattern builder with wildcards, live file match preview, test against workspace files |
| **Pattern Support** | Glob patterns (`**/*.swift`, `Sources/*`), directory exclusions |
| **Complexity** | Medium |
| **Implementation Notes** | Use `Glob` for pattern matching preview; show matched/excluded file counts |
| **Suggested Location** | `UI/Components/PathPatternEditor.swift` |

---

### 5. History & Versioning

#### Version History

| Aspect | Details |
|--------|---------|
| **Description** | Browse and restore previous configuration versions from automatic backups |
| **Features** | Timeline view of backups, diff between versions, restore with confirmation |
| **Data Source** | Existing timestamped backup files (`.swiftlint.yml.{timestamp}.backup`) |
| **Complexity** | Medium |
| **Implementation Notes** | Scan backup directory, parse timestamps, present sorted list; restore creates new backup first |
| **Suggested Location** | `UI/Views/Configuration/ConfigVersionHistoryView.swift` |

#### Change Annotations

| Aspect | Details |
|--------|---------|
| **Description** | Optional commit-message-style notes for configuration changes |
| **Features** | Add note when saving, store in backup metadata, view notes in history |
| **Storage** | Companion `.meta.json` file for each backup, or SQLite database |
| **Complexity** | Low |
| **Implementation Notes** | Prompt for optional note in save flow; store as JSON alongside backup |

#### Rollback with Impact Preview

| Aspect | Details |
|--------|---------|
| **Description** | Show violation impact before restoring an old configuration |
| **Features** | Select backup version, simulate diff in violations, preview before restore |
| **Output** | "Restoring this config will add X violations, remove Y violations" |
| **Complexity** | Medium |
| **Implementation Notes** | Combine version history with impact simulation; run simulation on backup config |

---

### 6. Validation & Migration

#### Version Compatibility Check

| Aspect | Details |
|--------|---------|
| **Description** | Warn about deprecated or renamed rules for the installed SwiftLint version |
| **Features** | Detect deprecated rules, suggest replacements, warn about removed rules |
| **Data Source** | SwiftLint version detection via CLI, rule deprecation database |
| **Complexity** | Medium |
| **Implementation Notes** | Run `swiftlint version`, maintain mapping of deprecated rules per version |
| **Suggested Location** | `Core/Services/VersionCompatibilityChecker.swift` |

#### Migration Assistant

| Aspect | Details |
|--------|---------|
| **Description** | Automatically update configurations when upgrading SwiftLint versions |
| **Features** | Detect version change, list required migrations, apply with preview |
| **Migrations** | Rename deprecated rules, update parameter names, remove deleted rules |
| **Complexity** | High |
| **Implementation Notes** | Maintain migration scripts per version transition; run on workspace open if version changed |

#### Real-time Validation

| Aspect | Details |
|--------|---------|
| **Description** | Live validation with inline error markers during configuration editing |
| **Features** | Immediate feedback on invalid values, syntax errors highlighted, suggestions |
| **Triggers** | On every configuration change before save |
| **Complexity** | Low |
| **Implementation Notes** | Extend existing `validate()` with more granular error reporting; show errors inline in UI |
| **UI Integration** | Red highlights on invalid fields, error messages below inputs |

---

### 7. Integration Features

#### Remote Config Support

| Aspect | Details |
|--------|---------|
| **Description** | Support SwiftLint's `parent_config` and `child_config` hierarchy with UI |
| **Features** | Visualize config inheritance, edit child configs, show effective merged config |
| **SwiftLint Fields** | `parent_config: URL`, `child_config: path` |
| **Complexity** | Medium |
| **Implementation Notes** | Fetch and parse parent configs, compute merged effective config, show inheritance chain |

#### CI/CD Snippets

| Aspect | Details |
|--------|---------|
| **Description** | Generate CI/CD configuration snippets for common platforms |
| **Platforms** | GitHub Actions, GitLab CI, Bitrise, Xcode Cloud, CircleCI, Jenkins |
| **Output** | Copy-paste YAML/script for each platform |
| **Complexity** | Low |
| **Implementation Notes** | Template strings with workspace path placeholders; copy to clipboard button |
| **Suggested Location** | `Core/Utilities/CISnippetGenerator.swift` |

#### Xcode Build Phase Export

| Aspect | Details |
|--------|---------|
| **Description** | Generate ready-to-use Xcode build phase script |
| **Output** | Shell script for "Run Script" build phase with SwiftLint invocation |
| **Features** | Customizable options (lint vs autocorrect, strict mode), installation check |
| **Complexity** | Low |
| **Implementation Notes** | Template script with configuration options; include Homebrew/Mint detection |

#### Git Sync Status

| Aspect | Details |
|--------|---------|
| **Description** | Show if local configuration differs from the committed version |
| **Indicators** | "Modified" badge, "Uncommitted changes" warning, diff from HEAD |
| **Features** | Quick view of git status, option to revert to committed version |
| **Complexity** | Low |
| **Implementation Notes** | Run `git diff --name-only .swiftlint.yml` to detect changes; show status badge in UI |

---

## Implementation Priority

### Phase 1: Quick Wins (Low Complexity, High Value)

| Feature | Category | Rationale |
|---------|----------|-----------|
| Template Library | Templates & Presets | Immediate value for new users |
| Rule Presets | Templates & Presets | Low effort, high usability gain |
| Config Health Score | Comparison & Analysis | Pure computation, no dependencies |
| PR Comment Generator | Import/Export | Simple transformation of existing diff |
| Real-time Validation | Validation & Migration | Extends existing validation infrastructure |

### Phase 2: High Impact (Medium Complexity)

| Feature | Category | Rationale |
|---------|----------|-----------|
| Visual Parameter Editor | Advanced Editing | Significant UX improvement |
| Version History | History & Versioning | Leverages existing backup system |
| Cross-Project Comparison | Comparison & Analysis | Team standardization use case |
| Bulk Rule Operations | Advanced Editing | Power user productivity |

### Phase 3: Strategic (Higher Complexity)

| Feature | Category | Rationale |
|---------|----------|-----------|
| Version Compatibility Check | Validation & Migration | Important for SwiftLint upgrades |
| Import from URL | Import/Export | Team sharing scenarios |
| Git Branch Diff | Comparison & Analysis | Advanced version control integration |
| Migration Assistant | Validation & Migration | Complex but valuable for major upgrades |

---

## Code References

### Core Files

| File | Purpose |
|------|---------|
| `Core/Services/YAMLConfigurationEngine.swift` | Main YAML handling: loading, validation, saving |
| `Core/Services/YAMLConfigurationEngine+Parsing.swift` | YAML Node to model conversion |
| `Core/Services/YAMLConfigurationEngine+Serialization.swift` | Model to YAML string conversion |
| `Core/Services/YAMLConfigurationEngine+Comments.swift` | Comment extraction and reinsertion |
| `Core/Services/ImpactSimulator.swift` | Rule impact simulation and safe rules discovery |

### UI Files

| File | Purpose |
|------|---------|
| `UI/Views/Configuration/ConfigDiffPreviewView.swift` | Diff preview with summary and full views |
| `UI/ViewModels/RuleDetailViewModel.swift` | Rule configuration state management |
| `UI/Views/ImpactSimulation/SafeRulesDiscoveryView.swift` | Safe rules discovery UI |

### Integration Points for New Features

| New Feature | Extend/Create |
|-------------|---------------|
| Template Library | Create `Core/Services/ConfigurationTemplateManager.swift` |
| Rule Presets | Create `Core/Data/RulePresets.swift` |
| Config Health Score | Create `Core/Services/ConfigurationHealthAnalyzer.swift` |
| Visual Parameter Editor | Create `UI/Components/RuleParameterEditor.swift` |
| Version History | Create `UI/Views/Configuration/ConfigVersionHistoryView.swift` |
| CI/CD Snippets | Create `Core/Utilities/CISnippetGenerator.swift` |

---

## Appendix: Data Structures

### Existing Structures

```swift
// YAMLConfig - Configuration model
struct YAMLConfig {
    var rules: [String: RuleConfiguration]
    var included: [String]?
    var excluded: [String]?
    var reporter: String?
    var disabledRules: [String]?
    var optInRules: [String]?
    var analyzerRules: [String]?
    var onlyRules: [String]?
    var warningThreshold: Int?
    var strict: Bool?
    var comments: [String: String]
    var keyOrder: [String]
}

// ConfigDiff - Diff between configurations
struct ConfigDiff {
    let addedRules: [String]
    let removedRules: [String]
    let modifiedRules: [String]
    let before: String
    let after: String
    var hasChanges: Bool
}

// RuleImpactResult - Simulation result
struct RuleImpactResult {
    let ruleId: String
    let violationCount: Int
    let violations: [Violation]
    let affectedFiles: Set<String>
    let simulationDuration: TimeInterval
}
```

### Proposed New Structures

```swift
// ConfigurationTemplate - For template library
struct ConfigurationTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let category: TemplateCategory // .iOS, .macOS, .package
    let style: ConfigStyle // .strict, .balanced, .lenient
    let yamlContent: String
    let metadata: TemplateMetadata
}

// RulePreset - For rule presets
struct RulePreset: Identifiable {
    let id: String
    let name: String
    let description: String
    let ruleIds: [String]
    let icon: String
}

// ConfigHealthReport - For health scoring
struct ConfigHealthReport {
    let score: Int // 0-100
    let enabledRuleCount: Int
    let totalRuleCount: Int
    let recommendations: [HealthRecommendation]
    let deprecatedRules: [String]
    let missingRecommendedRules: [String]
}

// ConfigVersion - For version history
struct ConfigVersion: Identifiable {
    let id: UUID
    let timestamp: Date
    let backupPath: URL
    let annotation: String?
    let changeCount: Int
}
```

---

*Last Updated: February 2026*
*Document Version: 1.0*
