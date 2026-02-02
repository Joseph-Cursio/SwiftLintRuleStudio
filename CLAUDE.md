# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the project (via Xcode command line tools)
xcodebuild -scheme SwiftLIntRuleStudio -configuration Debug build

# Run all tests
xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS'

# Run tests via CI script
./scripts/ci_test.sh

# Run SwiftLint on the project
swiftlint

# Run SwiftLint with autocorrect
swiftlint --fix

# Open in Xcode
open SwiftLIntRuleStudio.xcodeproj
```

Note: This is an Xcode project (not Swift Package Manager). Build and test through Xcode or xcodebuild.

## Project Overview

SwiftLint Rule Studio is a native macOS desktop application that provides a GUI interface for managing SwiftLint rules, discovering violations, simulating rule impact, and facilitating team coordination around code quality standards.

**Platform:** macOS 13.0+ (Ventura or later)
**Swift Version:** Swift 6.0 with strict concurrency checking
**UI Framework:** SwiftUI

## Project Architecture

### Directory Structure

```
SwiftLintRuleStudio/
├── App/                          # Application entry point
│   └── SwiftLintRuleStudioApp.swift
├── Core/                         # Business logic and services
│   ├── Models/                   # Data models (Rule, Violation, Configuration)
│   ├── Services/                 # Core application services
│   └── Utilities/                # Helper utilities
├── UI/                           # User interface
│   ├── Components/               # Reusable UI components
│   ├── ViewModels/               # MVVM view models
│   └── Views/                    # SwiftUI views
├── Data/                         # Data layer (configurations)
├── Assets.xcassets/              # App icons and assets
├── SwiftLIntRuleStudioTests/     # Unit tests
└── SwiftLIntRuleStudioUITests/   # UI tests
```

### Core Services

Located in `Core/Services/`:

- **RuleRegistry** - Central manager for SwiftLint rules metadata, caches rules from CLI
- **WorkspaceAnalyzer** - Background analysis engine, runs SwiftLint and parses violations
- **ViolationStorage** - Actor-based SQLite database for violations with thread safety
- **YAMLConfigurationEngine** - Safe YAML editing with comment preservation, diffs, validation
- **WorkspaceManager** - Workspace opening, validation, and recent workspace persistence
- **ImpactSimulator** - Simulates violations for disabled rules, discovers zero-violation rules
- **OnboardingManager** - First-run experience and SwiftLint detection
- **XcodeIntegrationService** - Opens violations in Xcode via URL schemes
- **SwiftLintCLI** - Command-line interface wrapper for SwiftLint execution

### Core Models

Located in `Core/Models/`:

- **Rule** - SwiftLint rule with identifier, description, severity, examples, parameters
- **Violation** - Code violation with file path, line, column, severity, suppression tracking
- **Configuration** - Workspace .swiftlint.yml configuration

### UI Views (by feature)

Located in `UI/Views/`:

- **RuleBrowser/** - Searchable, filterable rule list with master-detail split view
- **RuleDetail/** - Rule documentation, examples, configuration UI with diff preview
- **ViolationInspector/** - Violation browsing, filtering, suppression management
- **ImpactSimulation/** - Rule impact analysis, batch simulation, zero-violation discovery
- **Configuration/** - YAML diff preview and recommendations
- **Onboarding/** - First-run setup wizard
- **WorkspaceSelection/** - Workspace picker with recent workspaces

### View Models

Located in `UI/ViewModels/`:

- **RuleBrowserViewModel** - Rule loading, search, filtering, sort order
- **RuleDetailViewModel** - Configuration state, YAML diff generation, save validation
- **ViolationInspectorViewModel** - Violation loading, filtering, grouping, bulk operations

## Architecture Patterns

### MVVM Pattern
- **Views:** SwiftUI components
- **ViewModels:** Observable classes with @Published properties
- **Models:** Plain Swift structs with Codable/Sendable

### Dependency Injection
- `DependencyContainer` manages all service instances
- Passed through SwiftUI environment

### Concurrency
- Swift 6 strict concurrency checking enabled
- Actor-based thread safety for `ViolationStorage`
- Proper `Sendable` conformance throughout

### Protocol-Based Design
Services use protocols for testability:
- `RuleRegistryProtocol`
- `ViolationStorageProtocol`
- `SwiftLintCLIProtocol`

## Coding Conventions

- Use MVVM pattern: Views observe ViewModels, ViewModels call Services
- All services should have protocol definitions for testing
- Use `@MainActor` for UI-bound code
- Use actors for thread-safe mutable state
- Tests are organized to mirror the source structure
- Test files use Swift Testing framework (not XCTest)

## Testing

- **Framework:** Swift Testing (migrated from XCTest)
- **Test Location:** `SwiftLIntRuleStudioTests/` and `SwiftLIntRuleStudioUITests/`
- **Coverage:** 500+ tests, organized by Core/ and UI/
- **Isolation:** Tests use isolated UserDefaults, file system, and workspace instances

## Data Flow Example

**Enable a Rule:**
1. User toggles rule in RuleDetailView
2. RuleDetailViewModel tracks pending changes
3. User clicks "Apply Changes"
4. YAMLConfigurationEngine generates new YAML with diff
5. User confirms changes in diff preview
6. Engine writes to .swiftlint.yml (atomic write with backup)
7. Notification triggers re-analysis
8. WorkspaceAnalyzer runs SwiftLint
9. ViolationStorage updated with new violations
10. UI refreshes via Combine bindings

## External Dependencies

- **Yams** - YAML parsing
- **SwiftLint** - External CLI (linting engine)
