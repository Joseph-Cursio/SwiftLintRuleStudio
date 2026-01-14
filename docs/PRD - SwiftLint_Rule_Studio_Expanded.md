I asked Claude to expand on Copilots initial PRD.

# SwiftLint Rule Studio - Product Requirements Document

**Version:** 2.0  
**Last Updated:** January 2026  
**Status:** Draft  
**Owner:** Product Team

---

## Executive Summary

SwiftLint Rule Studio is a macOS desktop application and optional Xcode companion that transforms SwiftLint configuration from static YAML editing into an observable, teachable system for iOS/macOS development teams. It solves the problem of teams wasting hours debating linting rules, developers cargo-culting configurations without understanding impact, and lack of visibility into which rules actually improve code quality.

**Target Market:** iOS/macOS development teams (5-50 developers) using SwiftLint who struggle with configuration management, onboarding, and maintaining consistent code quality standards.

**Key Differentiator:** While other tools provide basic YAML editing or IDE integration, SwiftLint Rule Studio is the only solution purpose-built for team governance, learning, and data-driven rule adoption.

---

## Current Implementation Status

**Last Updated:** January 2026  
**Overall v1.0 Completion:** ~95%

> **Note:** This PRD is a requirements document describing what *should* be built. For detailed implementation status, see [`V1_REQUIREMENTS_STATUS.md`](../V1_REQUIREMENTS_STATUS.md).

### v1.0 MVP Status

| Feature | Status | Completion | Notes |
|---------|--------|------------|-------|
| Rule Browser | ✅ Complete | 100% | Fully implemented with search, filters, and caching. Background loading for rules beyond initial batch. Improved UI alignment with toolbar. |
| Rule Detail Panel | ✅ Complete | 100% | All features implemented: rationale extraction ("Why this matters"), violation count, related rules, Swift Evolution links. Improved markdown rendering, description parsing, and UI layout. |
| YAML Configuration Engine | ⚠️ Mostly Complete | 80% | Core engine complete; missing dry-run UI and Git integration |
| Workspace Analyzer | ✅ Complete | 100% | Fully implemented with incremental analysis and file tracking |
| Violation Inspector | ✅ Complete | 100% | All features implemented: grouping (by file, rule, severity), bulk operations, CSV/JSON export, keyboard shortcuts (⌘→, ⌘←). Xcode integration complete. |
| Workspace Management | ✅ Complete | 100% | Fully implemented with persistence and validation |
| Rule Config Persistence | ✅ Complete | 100% | Full end-to-end workflow with diff preview |
| Onboarding Flow | ✅ Complete | 100% | Complete with SwiftLint detection and workspace selection |
| Impact Simulation | ✅ Complete | 100% | Full implementation with zero-violation rule discovery |
| Xcode Integration | ✅ Complete | 100% | Full service layer implementation with path resolution, project detection, multiple opening methods (xed command, xcode:// URL), error handling, and context menu support. |

### Test Coverage

- **Total Tests:** 500+ tests (100% passing)
- **Test Framework:** Swift Testing (migrated from XCTest)
- **Concurrency:** Swift 6 compliant with strict concurrency checking (region-based isolation checker)
- **Test Isolation:** Complete isolation for UserDefaults, workspaces, and file systems
- **New Feature Tests:** Comprehensive tests for Rule Detail Panel enhancements (rationale extraction, Swift Evolution links, violation count, related rules) and Violation Inspector enhancements (grouping, export functionality)

### Recent UI/UX Improvements (January 2026)

**Layout Refinements:**
- ✅ Simplified Rule Detail Panel from three-panel to two-panel layout
- ✅ Moved rule description from separate panel to bottom of detail panel
- ✅ Improved content alignment with toolbar toggle using negative padding offsets
- ✅ Applied consistent alignment to both Rules and Violations panels
- ✅ Restored natural margins and padding within content components
- ✅ Matched heading text sizes (Description, Rationale, Examples) for visual consistency
- ✅ Added blank line before "Rationale" section for better readability

**Performance & Data Loading:**
- ✅ Implemented background loading for rules beyond initial batch (20 rules)
- ✅ Parallel rule detail fetching with timeout handling
- ✅ Improved rule description extraction from markdown documentation
- ✅ Enhanced description parsing to collect multiple lines (first paragraph/sentences)
- ✅ Limited description length to ~250 characters for list view with sentence boundary detection

**Code Quality:**
- ✅ Resolved Swift 6 concurrency errors (region-based isolation checker)
- ✅ Fixed data race issues in background rule loading
- ✅ Improved actor isolation and Sendable conformance
- ✅ Enhanced error handling for rule detail fetching with timeouts

**New Features (January 2026):**
- ✅ Rule Detail Panel: Added "Why This Matters" section with rationale extraction from markdown
- ✅ Rule Detail Panel: Added current violations count display with workspace integration
- ✅ Rule Detail Panel: Added "Related Rules" section showing rules in same category
- ✅ Rule Detail Panel: Added Swift Evolution proposal links extraction and display
- ✅ Violation Inspector: Added grouping functionality (by file, rule, severity)
- ✅ Violation Inspector: Enhanced bulk operations UI for suppress/resolve actions
- ✅ Violation Inspector: Added CSV/JSON export functionality with proper formatting
- ✅ Violation Inspector: Added keyboard shortcuts (⌘→ next, ⌘← previous) for navigation
- ✅ Xcode Integration: Complete service layer with path resolution, project detection, multiple opening methods
- ✅ Test Coverage: Added comprehensive tests for all new features (30+ new test cases)

### What's Left for v1.0

**Critical Path (Blocking v1.0):**
- ✅ All critical features complete

**Nice to Have (Can Ship Without):**
1. Dashboard and analytics (moved to v1.1)
2. Team Mode features (moved to v1.1)
3. Additional UI polish and refinements

### Roadmap Checkmarks

**Important:** The checkmarks (✅) in the Release Roadmap section below represent *planned features* for each version, not implementation status. Actual implementation status is tracked in `V1_REQUIREMENTS_STATUS.md`.

---

## Problem Statement

### Pain Points

1. **Configuration Chaos**
   - Teams waste 2-5 hours per sprint debating which rules to enable
   - YAML merge conflicts block deployments and frustrate developers
   - No one understands why rules were chosen or what they actually prevent
   - Copying configs from other projects without understanding context

2. **Lack of Visibility**
   - No way to know rule impact before enabling
   - Cannot trace rule changes to code quality improvements or regressions
   - Difficult to measure ROI of linting investment
   - No visibility into which violations actually get fixed vs. suppressed

3. **Onboarding Friction**
   - New team members don't understand team's linting philosophy
   - Juniors receive cryptic linting errors without learning resources
   - No progressive path from beginner to advanced rule adoption

4. **Team Coordination**
   - No approval workflow for configuration changes
   - Senior developers have to manually review every YAML edit
   - No audit trail of who changed what and why
   - Remote teams struggle with asynchronous rule discussions

### Current Workarounds and Why They Fail

- **Direct YAML editing**: Error-prone, no validation, no learning
- **VSCode/Xcode extensions**: Individual-focused, no team features, no analytics
- **Wiki documentation**: Gets outdated, disconnected from actual config
- **Slack/PR discussions**: Context lost, decisions not tracked, repeated debates

---

## Vision and Goals

### Product Vision

SwiftLint Rule Studio makes linting a competitive advantage by turning it from a compliance checkbox into a team learning and quality improvement system.

### Goals

1. **Accelerate rule adoption** - Reduce time from discovering a rule to enabling it from days to minutes
2. **Democratize configuration** - Enable any team member to propose and understand rule changes
3. **Measure impact** - Provide data-driven insights into rule effectiveness and code quality trends
4. **Eliminate YAML pain** - Make configuration changes safe, reversible, and conflict-free
5. **Scale team coordination** - Support distributed teams with async proposal and approval workflows

### Non-Goals (v1.0)

- **Not replacing SwiftLint** - We integrate with, not replace, the SwiftLint CLI and rule engine
- **Not a full IDE** - Not building autocomplete, debugging, or compilation features
- **Not multi-linter** - Focusing solely on SwiftLint, not ESLint, Rubocop, etc.
- **Not cloud SaaS** - v1.0 is local/network-shared; cloud sync comes in v2.0
- **Not supporting all languages** - Swift/Objective-C only via SwiftLint

---

## User Personas

### 1. Alex - Individual Developer (Primary Persona)

**Background:**
- 2-4 years iOS development experience
- Works on small team (3-8 developers)
- Uses SwiftLint but doesn't fully understand all rules
- Wants to write better Swift code but lacks mentorship

**Goals:**
- Learn Swift best practices through examples
- Understand which rules prevent bugs vs. just style preferences
- Explore new rules without breaking the build
- Fix violations efficiently

**Pain Points:**
- SwiftLint errors are cryptic without context
- Afraid to enable new rules without knowing impact
- Wastes time searching online for rule explanations
- Doesn't know which rules the community considers essential

**Key Features:**
- Rule browser with examples and explanations
- Live preview to experiment safely
- Violation previews before enabling rules
- Learning resources linked from rule details

### 2. Jordan - Tech Lead (Secondary Persona)

**Background:**
- 5-8 years experience, manages team of 5-15 developers
- Responsible for code quality and team standards
- Reviews PRs and makes architecture decisions
- Limited time for manual config reviews

**Goals:**
- Maintain consistent code quality across team
- Empower team members while maintaining control
- Track code quality trends over time
- Reduce time spent on linting debates

**Pain Points:**
- Every config change requires manual review
- Can't delegate linting decisions safely
- No data to justify or evaluate rule decisions
- YAML conflicts derail deployments

**Key Features:**
- Proposal and approval workflow
- Dashboard showing quality trends
- Audit log of all configuration changes
- Role-based permissions

### 3. Sam - Engineering Manager/Architect (Tertiary Persona)

**Background:**
- 8+ years experience, oversees multiple teams/projects
- Responsible for engineering standards across organization
- Needs visibility into technical debt and quality metrics
- Reports to leadership on engineering health

**Goals:**
- Establish consistent standards across multiple codebases
- Measure and report on code quality improvements
- Identify patterns and optimize for maximum impact
- Justify quality investments to leadership

**Pain Points:**
- No cross-project visibility
- Can't compare team configs or maturity
- No way to quantify quality improvements
- Lacks data for strategic planning

**Key Features:**
- Multi-workspace support
- Comparative analytics across projects
- Configuration templates and sharing
- Export metrics for leadership reports

---

## Competitive Landscape

### Direct Competitors

**1. Manual YAML Editing**
- **Strengths:** Zero cost, maximum control, works everywhere
- **Weaknesses:** No validation, no learning, error-prone, no team features
- **Our Advantage:** GUI reduces errors, provides learning, enables team coordination

**2. Xcode SwiftLint Extensions (e.g., SwiftLint for Xcode)**
- **Strengths:** Integrated into IDE, shows inline violations
- **Weaknesses:** Individual-focused, no config management, no analytics, no team mode
- **Our Advantage:** Team features, analytics, safe config editing, learning resources

**3. VSCode SwiftLint Extensions**
- **Strengths:** Free, real-time feedback
- **Weaknesses:** Limited to VSCode users, no team coordination, basic config editing
- **Our Advantage:** Native macOS app, team workflows, comprehensive rule management

### Indirect Competitors

**4. SwiftFormat GUI**
- **Strengths:** Exists in market, some users familiar with GUI for Swift tools
- **Weaknesses:** Different tool (formatting vs. linting), no team features
- **Our Advantage:** Focus on linting, team coordination features

**5. SonarQube/SonarCloud**
- **Strengths:** Enterprise-grade, multi-language, extensive analytics
- **Weaknesses:** Expensive, complex setup, not SwiftLint-native, poor UX
- **Our Advantage:** SwiftLint-native, better UX, lower cost, faster setup

### Why Alternatives Fail

- **IDE extensions** are designed for individuals, not teams
- **SonarQube** requires server infrastructure and is overkill for most teams
- **Manual editing** provides no learning or safety nets
- **No existing solution** bridges the gap between individual productivity and team governance

### Positioning Statement

"For iOS development teams who struggle with SwiftLint configuration management, SwiftLint Rule Studio is a native macOS application that makes linting a team learning and quality system, unlike IDE extensions or manual YAML editing which are individual-focused and error-prone."

---

## Key Features

### 1. Rule Browser (P0 - v1.0)

**Description:** A searchable, filterable catalog of all SwiftLint rules with rich metadata.

**User Stories:**
- As a developer, I want to browse all available rules so I can discover ones relevant to my codebase
- As a tech lead, I want to filter by category so I can enable all security rules at once
- As a junior developer, I want to see which rules are opt-in so I know which ones need explicit enabling

**Features:**
- Display rule name, identifier, category, and description
- Show enabled/disabled toggle with visual state
- Severity selector (warning, error)
- Indicate opt-in vs. default rules
- Category badges (Style, Lint, Metrics, Performance, etc.)
- Custom rule indicator

**Filters:**
- Status: All / Enabled / Disabled / Opt-in only
- Category: Style, Lint, Metrics, Performance, Idiomatic, etc.
- Has violations in current workspace
- Severity level
- Recently changed

**Search:**
- By rule name (e.g., "force_cast")
- By identifier
- By description keywords
- Fuzzy matching

**UI Components:**
- Master-detail split view (two-panel layout)
- List view with sortable columns
- Quick action buttons for common operations
- Keyboard shortcuts for power users
- Content alignment with toolbar toggle

**Technical Requirements:**
- ✅ Load rules from `swiftlint rules --format json`
- ✅ Cache rule metadata for performance
- ✅ Background loading for rules beyond initial batch (20 rules)
- ✅ Parallel rule detail fetching with timeout handling (30 seconds)
- ✅ Improved description extraction from markdown
- Update when SwiftLint version changes
- Support custom rules from workspace

### 2. Rule Detail Panel (P0 - v1.0)

**Description:** Comprehensive information panel for understanding and configuring individual rules.

**User Stories:**
- As a developer, I want to see before/after examples so I understand what the rule enforces
- As a junior developer, I want to know WHY a rule matters so I can learn best practices
- As a tech lead, I want to preview violations before enabling so I can estimate work

**Content Sections:**

**Overview:**
- Full description in plain English (improved parsing from markdown documentation)
- Short description extracted from first paragraph for list view
- Markdown documentation rendering with HTML formatting
- "Why this matters" section explaining rationale (planned)
- Links to Swift Evolution proposals, style guides, or documentation (planned)
- Rule adoption statistics ("Used by 85% of popular open-source Swift projects") (planned)

**Examples:**
- "Triggering Examples" showing code that violates the rule
- "Non-Triggering Examples" showing compliant code
- Syntax-highlighted code blocks
- Annotations explaining key differences

**Configuration:**
- Enabled/disabled toggle
- Severity selector (warning/error)
- Parameter editors for configurable rules (e.g., line_length max: 120)
- Parameter validation with helpful error messages
- "Restore defaults" button

**Current Violations:**
- Count of violations in current workspace (planned)
- List of affected files with line numbers (planned)
- Code snippet preview for each violation (planned)
- "Open in Xcode" button for each violation (planned)
- Filter by severity or file path (planned)

**Impact Simulation:**
- ✅ "Simulate" button to estimate impact without enabling (implemented)
- ✅ Projected violation count (implemented)
- ✅ Affected files list (implemented)
- Estimated fix time (trivial/moderate/complex) (planned)
- Affected files heat map (planned)
- "Enable anyway" or "Fix first" CTAs (planned)

**Related Rules:**
- Rules in same category (planned)
- Rules that commonly conflict or complement (planned)
- Suggested rule combinations (planned)

**UI Layout:**
- ✅ Two-panel layout (rules list + detail panel)
- ✅ Description section at bottom of detail panel with markdown rendering
- ✅ Consistent heading sizes and spacing
- ✅ Content aligned with toolbar toggle
- ✅ Natural margins and padding within content

**Technical Requirements:**
- ✅ Parse SwiftLint's built-in examples
- ✅ Parse markdown documentation from `swiftlint generate-docs`
- ✅ Background loading for rule details beyond initial batch
- ✅ Parallel fetching with timeout handling
- ✅ Improved description extraction (multiple lines, sentence boundaries)
- Run background analysis to find current violations (planned)
- Cache violation results for performance (planned)
- ✅ Support real-time config preview without saving

### 3. YAML Configuration Engine (P0 - v1.0)

**Description:** Safe, reversible YAML editing that preserves formatting and provides validation.

**User Stories:**
- As a developer, I want to see exactly what will change before saving so I can review safely
- As a tech lead, I want comments preserved so our documentation doesn't disappear
- As any user, I want to undo changes if something goes wrong

**Core Capabilities:**

**Round-Trip Preservation:**
- Preserve existing comments where possible
- Maintain key ordering from original file
- Keep custom formatting and blank lines
- Detect and warn when preservation isn't possible

**Diff Engine:**
- Show before/after comparison with syntax highlighting
- Line-by-line diff view with additions/deletions/modifications
- Ability to review changes before writing
- "Explain changes" text describing what changed and why

**Validation:**
- Schema validation before writing
- Detect syntax errors and malformed YAML
- Check for conflicting rules or invalid parameters
- Warn about deprecated rules or configurations
- Suggest fixes for common errors

**Safe Writing:**
- Dry-run mode that validates without writing
- Automatic backup before every write
- Git commit integration (optional)
- Rollback to previous configurations
- "Undo last change" feature

**Multi-Config Support:**
- Parent/child config inheritance
- Per-folder configuration override support
- Detect and navigate between related configs
- Merge strategy for nested configurations

**Technical Requirements:**
- Use Yams library for YAML parsing
- Custom serializer for comment preservation
- Implement diff algorithm (e.g., Myers diff)
- File system watching for external changes
- Atomic write operations to prevent corruption
- Support for .swiftlint.yml and custom paths

**Edge Cases to Handle:**
- Malformed YAML recovery
- Concurrent edits from external editors
- Missing or inaccessible config files
- Very large config files (1000+ rules)
- Unsupported SwiftLint version

### 4. Workspace Analyzer (P0 - v1.0)

**Description:** Background analysis engine that runs SwiftLint and tracks violations over time.

**User Stories:**
- As a developer, I want to see which rules have violations so I know what needs fixing
- As a tech lead, I want to track violation trends so I can measure quality improvements
- As any user, I want fast analysis so the app doesn't slow me down

**Features:**

**Real-Time Analysis:**
- Run SwiftLint on workspace in background
- Incremental analysis on file changes
- Debounced analysis (don't run on every keystroke)
- Cancelable analysis operations
- Progress indicators for long-running analysis

**Violation Storage:**
- Store violations in local database (SQLite/Core Data)
- Track violation history over time
- Associate violations with specific rule versions
- Tag violations with timestamps and Git commits

**Performance Optimization:**
- Analyze only changed files when possible
- Configurable analysis scope (file/folder/workspace)
- Background queue with priority management
- Memory-efficient for large codebases (100k+ files)
- Cache analysis results
- Parallel analysis for multi-core systems

**Analysis Settings:**
- Manual vs. automatic analysis
- Analysis trigger: on save, on demand, on Git operations
- Excluded paths (node_modules, Pods, etc.)
- Maximum analysis duration
- CPU usage throttling

**Technical Requirements:**
- Execute SwiftLint CLI as subprocess
- Parse SwiftLint JSON output
- File system watching using FSEvents (macOS)
- Smart diffing to detect changed files
- Handle SwiftLint crashes gracefully
- Support custom SwiftLint binary paths

**Performance Targets:**
- Initial analysis of 10k files: < 30 seconds
- Incremental analysis of single file: < 2 seconds
- Memory usage: < 500MB for typical workspace
- CPU usage: < 25% average on background thread

### 5. Violation Inspector (P0 - v1.0)

**Description:** Detailed view of violations with context, navigation, and quick fixes.

**User Stories:**
- As a developer, I want to see violations with surrounding code so I understand context
- As any user, I want to navigate to the exact violation in Xcode so I can fix it quickly
- As a junior developer, I want suggestions for how to fix violations

**Features:**

**Violation List:**
- Grouped by file, rule, or severity
- Sortable by any column
- Filter by rule, file, severity, or date
- Search within violations
- Bulk selection for batch operations

**Violation Details:**
- File path and line number
- Code snippet with violation highlighted
- Rule explanation and link to Rule Detail
- Suggested fix (when available from SwiftLint)
- Related violations (same rule in same file)

**Navigation:**
- "Open in Xcode" button
- Jump to specific line in external editor
- "Next/Previous violation" navigation
- Keyboard shortcuts for rapid triage

**Bulk Operations:**
- Suppress multiple violations
- Mark as "Won't fix" with reason
- Generate "Fix-it Sprint" task list
- Export violations to CSV/JSON

**Suppression Management:**
- Inline suppression comment generation
- Track suppressed violations in database
- Audit log of suppressions
- "Review suppressions" workflow
- Expire suppressions after time period

**Technical Requirements:**
- Parse SwiftLint output format
- Generate file:line URLs that open in Xcode
- Store suppression metadata
- Support custom editor configurations
- Handle violations in files that no longer exist

### 6. Configuration Profiles (P1 - v1.1)

**Description:** Save, share, and switch between different rule configurations.

**User Stories:**
- As a tech lead, I want to create a "strict" profile for new code and "lenient" for legacy
- As a developer, I want to try aggressive rules without affecting my team
- As an architect, I want to share our configuration with other teams

**Features:**

**Profile Management:**
- Create named profiles (e.g., "Strict", "Legacy", "Experimental")
- Switch between profiles instantly
- Compare two profiles side-by-side
- Clone and modify existing profiles
- Delete or archive unused profiles

**Profile Sharing:**
- Export profile as YAML file
- Import profiles from file or URL
- Built-in templates: "Starter", "Google Style", "Airbnb Style", "Strict", "Team of 5", "Enterprise"
- Community gallery (future: share with other users)

**Profile Metadata:**
- Name, description, author
- Created/modified dates
- Tags (e.g., "legacy-safe", "aggressive", "safety-focused")
- Compatible SwiftLint version range
- Violation count when applied to current workspace

**Profile Workflows:**
- Quick-switch menu in toolbar
- Temporary profile override
- "Test drive" mode that doesn't save changes
- Merge profiles (combine rules from two profiles)

**Technical Requirements:**
- Store profiles in app database
- Serialize to/from YAML
- Validate profile compatibility
- Handle profile conflicts gracefully

### 7. Dashboard & Analytics (P1 - v1.1)

**Description:** Visual insights into code quality trends, rule effectiveness, and team performance.

**User Stories:**
- As a tech lead, I want to see quality trends so I can report progress
- As an engineering manager, I want to identify problem areas so I can allocate resources
- As a developer, I want to celebrate improvements so I stay motivated

**Widgets:**

**Violation Heatmap:**
- 2D grid: rules (rows) vs. files (columns)
- Color intensity shows violation density
- Click to drill into specific rule+file combinations
- Filter by date range to see trends

**Rule Adoption Timeline:**
- Gantt-style chart showing when rules were enabled/disabled
- Annotations for why changes were made
- Correlation with violation counts
- Milestone markers (e.g., "Migrated to SwiftUI")

**Quality Score:**
- "Idiomatic Maturity Score" (0-100)
- Weighted by rule categories (security rules count more)
- Trend line showing improvement over time
- Comparison against previous sprint/quarter
- Breakdown by category contribution

**Violation Trends:**
- Line chart of total violations over time
- Segmented by severity (error vs. warning)
- Annotations for rule changes or major refactors
- Projected trend line
- "Days until zero violations" estimate

**Top Offenders:**
- Most violated rules
- Files with most violations
- Rules with worst trends (increasing violations)
- "Quick win" rules (low violation count, high impact)

**Team Performance:**
- Violations introduced per developer (requires Git integration)
- Violations fixed per sprint
- Average time to fix violations
- Leaderboard (optional, can be sensitive)

**Technical Requirements:**
- Store historical violation data
- Aggregate and query efficiently
- Generate charts using macOS native frameworks or libraries
- Export charts as images or PDFs
- Real-time updates when analysis completes

**Performance Targets:**
- Dashboard load time: < 2 seconds
- Support 12 months of historical data
- Handle 100k+ violation records efficiently

### 8. Live Preview Mode (P1 - v1.1)

**Description:** Interactive playground to paste code and experiment with rules in real-time.

**User Stories:**
- As a developer learning Swift, I want to paste code and see which rules apply
- As any user, I want to test rule configurations without affecting my workspace
- As a tech lead, I want to demonstrate rules to the team during code reviews

**Features:**

**Code Editor:**
- Multi-line text editor with syntax highlighting
- Paste code from clipboard
- Load code from file
- Basic editing (no full IDE features)
- Support for Swift and Objective-C

**Real-Time Rule Checking:**
- As-you-type violation detection (debounced)
- Inline violation markers in editor
- Sidebar showing triggered rules
- Toggle rules on/off and see immediate effect
- Severity indicators

**Rule Toggler:**
- List of all rules with checkboxes
- Check/uncheck to enable/disable for this session
- "Apply to workspace" button to persist changes
- "Reset to workspace config" to undo experiments

**Violation Details:**
- Click violation to see rule explanation
- Suggested fixes (if available)
- Link to Rule Detail panel for more info

**Code Snippets:**
- Save interesting examples
- Built-in examples for learning
- Share snippets as URLs or files

**Comparison Mode:**
- Split view comparing two code versions
- Side-by-side rule evaluation
- Useful for before/after refactoring

**Technical Requirements:**
- Run SwiftLint on code snippet (not full file)
- Fast analysis (< 1 second for typical snippet)
- Isolated from workspace config (unless user chooses to apply)
- Memory-safe for large code pastes

**Use Cases:**
- Learning: Paste example code and explore which rules trigger
- Testing: Try new rules without affecting build
- Teaching: Demonstrate rules during code review or onboarding
- Debugging: Understand why a rule fires on specific code

### 9. Team Mode (P1 - v1.1)

**Description:** Collaborative workflows for distributed teams with proposals, approvals, and governance.

**User Stories:**
- As a junior developer, I want to propose a rule change without breaking the build
- As a tech lead, I want to review and approve rule changes before they take effect
- As an engineering manager, I want an audit trail of who changed what and why

**Architecture:**

**Storage Strategy (v1.1):**
- Git-based collaboration
- Proposals are Git branches
- Approvals are merge commits
- Config stored in repository (not separate server)
- App reads/writes via Git commands

**Alternative (v2.0 consideration):**
- Optional cloud sync service
- Real-time collaboration
- Slack/Teams integration
- Would require server infrastructure

**Core Features:**

**Roles & Permissions:**
- Viewer: Can browse rules and see violations
- Editor: Can propose rule changes
- Approver: Can approve/reject proposals
- Admin: Can manage roles and settings
- Configurable via JSON file in repository

**Proposal Workflow:**

1. **Create Proposal:**
   - Developer makes rule changes in app
   - Clicks "Create Proposal" instead of "Save"
   - Enters title, description, and rationale
   - App creates feature branch with changes
   - Notifies approvers (via commit message or external tool)

2. **Review Proposal:**
   - Approver sees proposal in "Approval Queue"
   - Views diff of config changes
   - Sees impact analysis (violation count delta)
   - Reads rationale and comments
   - Can ask questions or request changes (via Git comments)

3. **Approve/Reject:**
   - Approver clicks "Approve" → app merges branch
   - Or "Reject with reason" → app records rejection
   - Or "Request changes" → returns to proposer

4. **Notifications:**
   - macOS notifications for new proposals
   - Badge count on app icon
   - Optional: Slack/Email integration (v1.2)

**Proposal Details:**
- Title and description
- Author and reviewers
- Config diff
- Impact analysis results
- Comments/discussion thread
- Status: Pending, Approved, Rejected, Changes Requested
- Timestamps for each status change

**Approval Queue:**
- List of pending proposals
- Sort by date, author, or impact
- Filter by status
- Quick approve/reject actions
- Batch operations for multiple proposals

**Audit Log:**
- Chronological list of all config changes
- Who made each change and when
- Before/after state
- Rationale and approval trail
- Filter by date, author, or rule
- Export to CSV or PDF

**Team Settings:**
- Define roles and permissions
- Set approval requirements (1 approver, 2 approvers, etc.)
- Configure notification preferences
- Require rationale for changes
- Set proposal expiration time

**Technical Requirements:**
- Git integration via libgit2 or command-line Git
- Parse and create Git branches
- Detect merge conflicts and guide resolution
- Store proposal metadata in Git commits or separate file
- Handle offline/online state gracefully
- Sync with remote repository

**Edge Cases:**
- What if someone commits YAML changes outside the app?
  → App detects change, asks user to sync or shows conflict
- What if approval takes days and codebase diverges?
  → Re-run impact analysis when approving, show if results changed
- What if two people propose conflicting changes?
  → App detects conflict, requires sequential approval
- What if approver is offline?
  → Proposal stays in queue, others can approve if permissions allow

**v1.1 Scope:**
- Basic proposal/approval workflow
- Git-based storage
- Audit log
- Role-based permissions

**v2.0 Additions:**
- Real-time collaboration
- Slack/Teams integration
- Cloud sync for non-Git teams
- Advanced analytics on team dynamics

### 10. Migration Assistant (P2 - v1.2)

**Description:** Guided workflow to progressively adopt rules without overwhelming the team.

**User Stories:**
- As a tech lead adopting SwiftLint, I want a phased plan so we don't get 10,000 violations at once
- As a developer on legacy codebase, I want to know which violations to fix first
- As an engineering manager, I want to track migration progress

**Features:**

**Onboarding Wizard:**
- Detects existing .swiftlint.yml or starts fresh
- Analyzes codebase to understand current state
- Recommends starting configuration based on codebase
- Sets realistic goals (e.g., "Zero new violations in 30 days")

**Phase Planning:**
- Suggests 3-5 phases of rule adoption
- Phase 1: Rules that already pass (quick win)
- Phase 2: Easy fixes (automated or trivial)
- Phase 3: Medium effort rules
- Phase 4-5: Complex or opinionated rules
- Customizable phase definitions

**Progress Tracking:**
- Current phase indicator
- Completion percentage per phase
- Estimated time remaining
- Celebration milestones (50% done, etc.)

**Fix Sprints:**
- Suggests "Fix-it Friday" sessions
- Generates task list for 30-60 minute sprint
- Groups related violations for efficiency
- Tracks completed sprints

**Documentation Generation:**
- Auto-generates onboarding guide for new team members
- Explains team's rule philosophy
- Links to examples and resources
- Updates as configuration evolves

**Migration Reports:**
- Before/after violation counts
- Time saved in code review
- Quality score improvement
- Export for leadership or retrospectives

**Technical Requirements:**
- Analysis of codebase complexity
- Heuristics for rule difficulty estimation
- Progress tracking in database
- Document generation in Markdown or PDF

### 11. CI/CD Integration (P2 - v1.2)

**Description:** Connect SwiftLint Rule Studio with continuous integration systems.

**User Stories:**
- As a tech lead, I want CI to fail on new violations so quality doesn't regress
- As a developer, I want to see violations in PRs so I can fix before merge
- As an engineering manager, I want alerts when quality drops

**Features:**

**CI Configuration Generator:**
- Generates config for GitHub Actions, GitLab CI, Bitrise, Jenkins, CircleCI
- Includes SwiftLint execution and reporting
- Configurable failure thresholds
- Ratcheting mode: allow existing violations, fail on new ones

**Build Annotations:**
- Parse CI logs and extract violations
- Display in-app with links to CI build
- Show which rules are failing in CI vs. local
- Diff between local and CI results

**PR Integration:**
- Inline comments on PRs with violation details
- Status checks (pass/fail) on PRs
- Violation summary in PR description
- Comparison: violations in PR vs. base branch

**Regression Alerts:**
- Detect when quality score drops significantly
- Notify via macOS notification or external service
- Configurable thresholds (e.g., "Alert if score drops > 5 points")
- Weekly quality reports via email

**Notifications:**
- Slack webhook integration
- Microsoft Teams integration
- Email notifications
- Discord webhooks
- Customizable message templates

**Technical Requirements:**
- Export configuration in CI-specific formats
- Parse various CI log formats
- API integration with GitHub, GitLab, Bitrise
- Webhook handling for real-time updates
- OAuth for secure API access

### 12. Xcode Integration (P2 - v1.3)

**Description:** Companion features that work within Xcode for seamless workflow.

**Options to Explore:**

**Source Editor Extension:**
- Right-click menu in Xcode: "Toggle SwiftLint Rule"
- Inline rule information on hover
- Quick-fix suggestions
- "Open in Rule Studio" action

**Build Phase Integration:**
- Auto-configure SwiftLint build phase
- Show Rule Studio dashboard after build
- Deep link to violations from Xcode issues navigator

**Xcode Plugin (if feasible with Apple's restrictions):**
- Sidebar showing rule status
- Inline violation previews
- Real-time linting as you type

**Technical Challenges:**
- Xcode extension APIs are limited
- May need separate process communication
- Requires code signing and distribution strategy

---

## User Flows

### Flow 1: Enable a Rule (Happy Path)

**Persona:** Alex (Individual Developer)

1. Alex opens SwiftLint Rule Studio
2. Clicks on Rule Browser in sidebar
3. Types "force cast" in search bar
4. Clicks on "force_cast" rule in results
5. Rule Detail Panel opens showing description and examples
6. Alex reads "Why this matters" section, sees it prevents crashes
7. Scrolls to "Current Violations" section, sees "3 violations in 2 files"
8. Clicks "Show Details" to preview violations
9. Reviews code snippets, decides violations are easy to fix
10. Clicks "Enable" toggle in Configuration section
11. Sets severity to "Error"
12. App shows YAML diff preview in modal
13. Alex reviews changes, sees: `force_cast: error` will be added
14. Clicks "Apply Changes"
15. App writes to .swiftlint.yml
16. Success notification: "force_cast rule enabled"
17. Workspace Analyzer automatically re-runs in background
18. Violations update in real-time

**Alternative Flow - High Violation Count:**
- At step 8, Alex sees "83 violations in 24 files"
- Decides not to enable yet
- Clicks "Export Violation Report"
- Schedules "Fix Sprint" with team

### Flow 2: Investigate Violations (Happy Path)

**Persona:** Alex (Individual Developer)

1. Alex opens app, sees dashboard
2. Notices "trailing_whitespace" has 47 violations (up from 12 last week)
3. Clicks on the rule name in violation trends chart
4. Violation Inspector opens filtered to trailing_whitespace
5. Violations grouped by file
6. Alex clicks on "ProfileViewController.swift (12 violations)"
7. Code snippets show trailing spaces in various lines
8. Alex clicks "Open in Xcode" button
9. Xcode opens ProfileViewController.swift
10. Alex runs "Delete Trailing Whitespace" command in Xcode
11. Saves file
12. Returns to Rule Studio
13. Sees violation count automatically updated to 35 (12 fixed)
14. Repeats for other files or uses bulk "Fix with SwiftFormat" (future feature)

**Alternative Flow - Suppress Violations:**
- At step 6, Alex sees violations are in legacy code
- Selects all 12 violations
- Clicks "Suppress" → "Add reason: Legacy code, will refactor in Q2"
- Violations hidden from main list
- Added to "Suppressed Violations" audit log

### Flow 3: Team Rule Change Proposal (Happy Path)

**Persona:** Alex (Individual Developer) + Jordan (Tech Lead)

**Part A - Alex Proposes:**
1. Alex discovers "explicit_type_interface" rule
2. Reads Rule Detail, thinks it will improve code clarity
3. Enables the rule
4. Sees "127 violations in 34 files"
5. Realizes this is a big change, needs team buy-in
6. Instead of "Apply Changes", clicks "Create Proposal"
7. Modal opens: "Proposal Title", "Description", "Rationale"
8. Alex fills in:
   - Title: "Enable explicit_type_interface for clearer code"
   - Description: "This rule requires explicit types on public declarations"
   - Rationale: "Will help onboarding and make API boundaries clearer. I can fix violations in 2 sprints."
9. Clicks "Submit Proposal"
10. App creates Git branch: "swiftlint-proposal/explicit-type-interface"
11. Commits config changes to branch
12. Notifies Jordan via macOS notification

**Part B - Jordan Reviews:**
1. Jordan sees notification: "New SwiftLint proposal from Alex"
2. Opens Rule Studio, clicks "Approval Queue" (badge shows "1")
3. Sees Alex's proposal in list
4. Clicks to open proposal detail
5. Reads title, description, rationale
6. Reviews YAML diff
7. Sees impact analysis: "127 new violations, estimated 8 hours of work"
8. Thinks this is reasonable but wants to discuss timing
9. Clicks "Request Changes"
10. Adds comment: "Great idea! Let's enable after our current sprint ends. Can you reduce violations to <50 first?"
11. Alex gets notification
12. Alex fixes some violations in next few days
13. Updates proposal with new impact: "48 violations"
14. Jordan sees update, clicks "Approve"
15. App merges Git branch
16. Config updated in repository
17. All team members get latest config on next Git pull
18. Audit log updated

**Alternative Flow - Rejection:**
- At step 9 (Part B), Jordan clicks "Reject"
- Adds reason: "This rule is too opinionated for our team's style"
- Alex sees rejection with reason
- Git branch remains for reference but not merged

### Flow 4: First-Time Onboarding (New User)

**Persona:** Casey (New Developer joining team with existing SwiftLint config)

1. Casey installs SwiftLint Rule Studio
2. Opens app for first time
3. Onboarding wizard appears: "Welcome to SwiftLint Rule Studio"
4. Wizard asks: "Do you have an existing workspace?"
5. Casey clicks "Yes" and selects Xcode workspace folder
6. App detects .swiftlint.yml
7. Wizard shows: "Found existing configuration with 42 rules enabled"
8. Offers: "Would you like a tour of your team's rules?"
9. Casey clicks "Yes"
10. Guided tour starts:
    - Step 1: Rule Browser - "Here's where all rules live"
    - Step 2: Rule Detail - "Click any rule to learn about it"
    - Step 3: Violations - "See what needs fixing"
    - Step 4: Dashboard - "Track your team's quality progress"
11. Tour ends with: "Here are 5 rules your team considers most important" (based on config)
12. Casey can click each to learn why the team enabled them
13. Wizard offers: "Generate onboarding document for your team?"
14. Casey clicks "Yes"
15. App generates Markdown doc explaining team's linting philosophy
16. Casey saves for reference

**Alternative Flow - No Existing Config:**
- At step 6, no config detected
- Wizard offers: "Start with a template" (Starter, Strict, etc.)
- Casey selects "Starter" template
- App creates .swiftlint.yml with sensible defaults
- Runs initial analysis
- Shows results and suggests next steps

### Flow 5: Experiment with Live Preview

**Persona:** Alex (Individual Developer learning Swift best practices)

1. Alex is working on a code review
2. Sees unfamiliar syntax in a PR
3. Opens Rule Studio and clicks "Live Preview" in toolbar
4. Pastes the code snippet from GitHub
5. App immediately highlights violations
6. Sidebar shows 2 rules triggered:
   - "redundant_optional_initialization"
   - "implicit_return"
7. Alex clicks on first rule
8. Rule Detail opens in split view
9. Reads explanation and examples
10. Understands the issue now
11. Switches back to Live Preview
12. Edits code to fix violation
13. Violation disappears in real-time
14. Alex understands the pattern now
15. Clicks "Save Snippet" to remember this example
16. Returns to code review with newfound knowledge

---

## Technical Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Frontend                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ │
│  │  Rule    │ │ Violation│ │Dashboard │ │ Live       │ │
│  │  Browser │ │ Inspector│ │          │ │ Preview    │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────────┘ │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                  Core Application Layer                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Rule         │  │ Workspace    │  │ YAML Config  │  │
│  │ Registry     │  │ Analyzer     │  │ Engine       │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Violation    │  │ Team         │  │ Git          │  │
│  │ Manager      │  │ Coordinator  │  │ Integration  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                   Data & Storage Layer                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ SQLite DB    │  │ File System  │  │ Git Repo     │  │
│  │ (Violations, │  │ (.swiftlint  │  │ (Proposals,  │  │
│  │  Metrics)    │  │  .yml)       │  │  Audit Log)  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                   External Integrations                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ SwiftLint    │  │ Xcode        │  │ CI/CD        │  │
│  │ CLI          │  │ (via URLs)   │  │ Systems      │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. Rule Registry

**Purpose:** Central source of truth for all SwiftLint rules and their metadata.

**Responsibilities:**
- Fetch rules from SwiftLint CLI
- Parse JSON output
- Cache rule metadata
- Detect SwiftLint version changes
- Support custom rules

**Data Model:**
```swift
struct Rule {
    let identifier: String
    let name: String
    let description: String
    let category: RuleCategory
    let isOptIn: Bool
    let severity: Severity
    let parameters: [RuleParameter]?
    let triggeringExamples: [String]
    let nonTriggeringExamples: [String]
    let documentation: URL?
}

enum RuleCategory {
    case style, lint, metrics, performance, idiomatic
}

enum Severity {
    case warning, error
}

struct RuleParameter {
    let name: String
    let type: ParameterType
    let defaultValue: Any
    let validation: ValidationRule?
}
```

**Implementation:**
- Singleton or dependency-injected service
- SwiftLint CLI invocation: `swiftlint rules --format json`
- Parse JSON using Codable
- Store in memory for fast access
- Persist cache to disk (app support directory)
- Refresh cache when SwiftLint version changes

**Error Handling:**
- Handle missing SwiftLint binary
- Handle unsupported SwiftLint version
- Fallback to cached rules if CLI fails
- Log errors for debugging

#### 2. YAML Configuration Engine

**Purpose:** Safe, reversible editing of .swiftlint.yml with comment preservation.

**Responsibilities:**
- Parse YAML to internal model
- Serialize model back to YAML
- Preserve comments and formatting
- Generate diffs
- Validate before writing
- Support nested configs

**Libraries:**
- Yams for YAML parsing/serialization
- Custom wrapper for comment preservation

**Algorithm for Comment Preservation:**
1. Parse YAML with Yams (loses comments)
2. Parse raw YAML text with custom parser to extract comments
3. Store comment positions relative to keys
4. When serializing, reinsert comments at correct positions
5. If structure changes drastically, warn user comments may be lost

**Diff Generation:**
- Myers diff algorithm
- Line-by-line comparison
- Syntax highlighting for added/removed/modified lines

**Validation:**
- Schema validation against known rule identifiers
- Parameter type checking
- Detect conflicting rules
- Warn about deprecated rules

**Data Model:**
```swift
struct YAMLConfig {
    var rules: [String: RuleConfig]
    var included: [String]?
    var excluded: [String]?
    var reporter: String?
    var comments: [String: String] // Key -> comment text
}

struct RuleConfig {
    let enabled: Bool
    let severity: Severity
    let parameters: [String: Any]?
}
```

**Implementation:**
- Read file using FileManager
- Parse with Yams
- Mutate in-memory model
- Generate diff before writing
- Atomic write (write to temp file, then move)
- Git commit integration (optional)

#### 3. Workspace Analyzer

**Purpose:** Run SwiftLint on workspace and track violations over time.

**Responsibilities:**
- Execute SwiftLint CLI
- Parse violation output
- Store violations in database
- Incremental analysis
- Performance optimization

**Execution Strategy:**
- Background thread to avoid blocking UI
- Operation queue with priority
- Cancelable operations
- Progress reporting

**Incremental Analysis:**
- File system watching with FSEvents
- Track file modification timestamps
- Only re-analyze changed files
- Merge new results with cached results

**Database Schema:**
```sql
CREATE TABLE violations (
    id INTEGER PRIMARY KEY,
    rule_id TEXT NOT NULL,
    file_path TEXT NOT NULL,
    line INTEGER NOT NULL,
    column INTEGER,
    severity TEXT NOT NULL,
    message TEXT NOT NULL,
    detected_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP,
    suppressed BOOL DEFAULT 0,
    suppression_reason TEXT
);

CREATE TABLE analysis_runs (
    id INTEGER PRIMARY KEY,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    files_analyzed INTEGER,
    violations_found INTEGER,
    config_hash TEXT
);

CREATE INDEX idx_violations_rule ON violations(rule_id);
CREATE INDEX idx_violations_file ON violations(file_path);
CREATE INDEX idx_violations_detected ON violations(detected_at);
```

**Performance Optimizations:**
- Run SwiftLint with `--reporter json` for structured output
- Use `--path` to limit scope when possible
- Parallel execution for large workspaces (split into chunks)
- Memory-mapped file I/O for large outputs
- Connection pooling for database

**Implementation:**
```swift
class WorkspaceAnalyzer {
    func analyze(workspace: Workspace, config: YAMLConfig) async throws -> AnalysisResult {
        let process = Process()
        process.executableURL = swiftlintBinary
        process.arguments = ["lint", "--reporter", "json", "--config", config.path]
        
        let output = try await process.run()
        let violations = try parseViolations(from: output)
        
        try await store(violations: violations)
        
        return AnalysisResult(violations: violations)
    }
}
```

#### 4. Violation Manager

**Purpose:** Store, query, and manage violations in database.

**Responsibilities:**
- CRUD operations on violations
- Querying with filters
- Tracking suppressions
- Historical analysis

**APIs:**
```swift
protocol ViolationManager {
    func store(violations: [Violation]) async throws
    func fetchViolations(filter: ViolationFilter) async throws -> [Violation]
    func suppress(violations: [Violation], reason: String) async throws
    func resolve(violations: [Violation]) async throws
    func fetchTrends(since: Date, groupBy: GroupBy) async throws -> [TrendData]
}

struct ViolationFilter {
    var ruleIDs: [String]?
    var filePaths: [String]?
    var severities: [Severity]?
    var suppressedOnly: Bool?
    var dateRange: ClosedRange<Date>?
}

enum GroupBy {
    case rule, file, date, severity
}
```

**Implementation:**
- Use Core Data or SQLite
- Async/await for database operations
- Background context for heavy operations
- Batch inserts for performance

#### 5. Team Coordinator

**Purpose:** Manage team workflows, proposals, and approvals.

**Responsibilities:**
- Create and track proposals
- Approval workflow
- Audit logging
- Role management

**Git Integration:**
```swift
class TeamCoordinator {
    func createProposal(title: String, description: String, configChanges: YAMLConfig) async throws -> Proposal {
        let branchName = "swiftlint-proposal/\(title.slugified)"
        
        try await git.createBranch(branchName)
        try await git.checkout(branchName)
        try await yamlEngine.write(config: configChanges)
        try await git.commit(message: "Proposal: \(title)\n\n\(description)")
        try await git.push()
        
        let proposal = Proposal(title: title, description: description, branch: branchName)
        try await store(proposal: proposal)
        
        return proposal
    }
    
    func approveProposal(_ proposal: Proposal) async throws {
        try await git.checkout("main")
        try await git.merge(branch: proposal.branch)
        try await git.push()
        
        proposal.status = .approved
        try await update(proposal: proposal)
        
        try await auditLog.record(action: .approved, proposal: proposal)
    }
}
```

**Data Model:**
```swift
struct Proposal {
    let id: UUID
    let title: String
    let description: String
    let author: User
    let branch: String
    let configDiff: String
    var status: ProposalStatus
    let createdAt: Date
    var reviewedAt: Date?
    var reviewer: User?
}

enum ProposalStatus {
    case pending, approved, rejected, changesRequested
}
```

#### 6. Git Integration

**Purpose:** Interact with Git repository for version control and collaboration.

**Responsibilities:**
- Branch management
- Commit and push
- Detect external changes
- Merge operations

**Implementation:**
- Use SwiftGit2 or libgit2 bindings
- Or shell out to git CLI for simplicity

**APIs:**
```swift
protocol GitRepository {
    func currentBranch() async throws -> String
    func createBranch(_ name: String) async throws
    func checkout(_ branch: String) async throws
    func commit(message: String, files: [String]) async throws
    func push() async throws
    func merge(branch: String) async throws
    func status() async throws -> [FileStatus]
}
```

### Data Flow Examples

#### Example 1: Enabling a Rule

1. User toggles rule in UI
2. UI updates Rule Detail Panel state
3. User clicks "Apply Changes"
4. UI calls `YAMLConfigEngine.updateRule()`
5. Engine generates new config model
6. Engine serializes to YAML
7. Engine generates diff
8. UI shows diff preview modal
9. User confirms
10. Engine writes to file system
11. Git Integration commits change (optional)
12. File system watcher detects change
13. Workspace Analyzer triggers re-analysis
14. Analyzer runs SwiftLint CLI
15. Analyzer parses violations
16. Violation Manager stores new violations
17. UI updates Violation Inspector
18. UI updates Dashboard charts

#### Example 2: Team Proposal Flow

1. User makes config changes
2. User clicks "Create Proposal"
3. UI calls `TeamCoordinator.createProposal()`
4. Coordinator creates Git branch
5. Coordinator commits changes
6. Coordinator stores proposal in database
7. Coordinator sends notification
8. Approver opens app
9. UI fetches pending proposals
10. Approver reviews proposal
11. Approver clicks "Approve"
12. UI calls `TeamCoordinator.approveProposal()`
13. Coordinator merges Git branch
14. Coordinator updates proposal status
15. Coordinator records in audit log
16. UI notifies original author
17. File system watcher detects merge
18. Workspace Analyzer re-runs
19. UI updates for all team members

### Technology Stack

**Frontend:**
- SwiftUI (native macOS)
- Combine for reactive bindings
- Swift Charts for data visualization (macOS 13+)

**Backend/Core:**
- Swift (100%)
- Async/await for concurrency
- Actor model for thread safety

**Data Storage:**
- SQLite or Core Data for violations and metrics
- File system for YAML configs
- Git repository for audit trail and collaboration

**External Dependencies:**
- Yams (YAML parsing)
- SwiftGit2 or libgit2 (Git operations)
- Possibly Sourcery for code generation

**Development Tools:**
- Xcode 15+
- Swift 5.9+
- macOS 13+ target (for latest APIs)

**Testing:**
- XCTest for unit tests
- UI tests for critical flows
- Mock SwiftLint CLI for deterministic tests

**Performance Targets:**
- App launch: < 2 seconds (cold start)
- Rule Browser render: < 500ms for 200 rules
- YAML diff generation: < 1 second for typical config
- Workspace analysis: < 30 seconds for 10k files
- Database query: < 100ms for typical filter
- Memory usage: < 500MB for typical workspace

### Deployment

**Distribution:**
- Mac App Store (primary)
- Direct download from website (alternative for enterprise)
- Possibly Homebrew cask

**Code Signing:**
- Apple Developer ID certificate
- Notarization required for Gatekeeper

**Auto-Update:**
- Sparkle framework for non-App Store version
- App Store handles updates for App Store version

**System Requirements:**
- macOS 13.0 (Ventura) or later
- SwiftLint 0.50.0 or later installed
- Xcode 14+ (for Xcode integration features)

---

## Success Metrics

### Product Metrics

**Adoption:**
- Number of downloads/installs
- Daily Active Users (DAU)
- Weekly Active Users (WAU)
- DAU/MAU ratio (stickiness)

**Engagement:**
- Average session duration
- Number of sessions per user per week
- Rule Detail views per session
- Configuration changes per week

**Feature Usage:**
- Percentage of users using Rule Browser
- Percentage of users using Dashboard
- Percentage of users using Live Preview
- Percentage of users using Team Mode
- Most viewed rules
- Most enabled/disabled rules

**Team Adoption:**
- Number of teams using Team Mode
- Average team size
- Proposals created per team per month
- Proposal approval rate
- Average approval time

### Quality Metrics

**Code Quality:**
- Average violations per 1000 LOC (trend over time)
- Percentage reduction in violations month-over-month
- Number of rules enabled per workspace (trend)
- Idiomatic Maturity Score (average across all users)

**Configuration Quality:**
- Percentage of users with zero YAML syntax errors
- Number of YAML merge conflicts (should decrease)
- Percentage of rules configured via GUI vs. manual YAML

**Developer Experience:**
- Time from onboarding to first rule enabled
- Time from creating proposal to approval
- Number of rule changes rolled back (should be low)

### Business Metrics

**Revenue (if applicable):**
- Monthly Recurring Revenue (MRR)
- Customer Lifetime Value (LTV)
- Churn rate
- Conversion rate from free to paid (if freemium)

**Growth:**
- Month-over-month user growth
- Week-over-week active team growth
- Viral coefficient (invites sent per user)

**Support:**
- Number of support tickets per 100 users
- Average resolution time
- Net Promoter Score (NPS)
- App Store rating

### Success Criteria (v1.0)

By end of v1.0 launch + 3 months:

- 1,000+ downloads
- 100+ Daily Active Users
- 4.5+ star rating on App Store
- 70%+ of users configure at least one rule via GUI
- 50%+ reduction in YAML syntax errors (based on telemetry)
- 30%+ of users return weekly
- 10+ teams actively using app (5+ members each)

### Tracking Implementation

**Analytics:**
- Use Apple's built-in analytics (privacy-focused)
- Or self-hosted analytics (if more detail needed)
- Respect user privacy: make telemetry opt-in
- Never collect source code or violation content
- Anonymize all data

**What to Track:**
- App launches and session duration
- Feature usage (which buttons clicked, which panels opened)
- Performance metrics (analysis time, app responsiveness)
- Errors and crashes
- Configuration changes (anonymized)

**What NOT to Track:**
- Source code content
- Violation messages
- File paths or names
- Team member identities
- Private repository information

---

## Monetization Strategy

### Business Model Options

#### Option 1: Freemium (Recommended)

**Free Tier:**
- Full Rule Browser and Rule Detail
- YAML Configuration Engine
- Workspace Analyzer (up to 10k files)
- Violation Inspector
- Live Preview Mode
- Single user

**Pro Tier ($19/month or $149/year per user):**
- Everything in Free
- Dashboard with analytics and trends
- Unlimited workspace size
- Team Mode (proposals, approvals, audit log)
- CI/CD integration
- Priority support
- Early access to new features

**Enterprise Tier (Custom pricing):**
- Everything in Pro
- Multi-workspace support
- SSO and advanced permissions
- Dedicated support
- On-premise deployment option (future)
- Custom integrations

**Why Freemium?**
- Lowers barrier to entry
- Lets individuals try before convincing team
- Team features are natural upsell
- Aligns with developer tool market

#### Option 2: One-Time Purchase

**Price:** $49-$99 per user

**Pros:**
- Simple, no recurring billing
- Appeals to indie developers
- Easy to understand

**Cons:**
- Hard to fund ongoing development
- Updates require separate purchases
- Less revenue predictability

#### Option 3: Open Source + Paid Support

**Free:** All features open source

**Paid:** Support contracts, custom development, training

**Pros:**
- Builds community and trust
- Can still generate revenue
- Aligns with developer values

**Cons:**
- Harder to monetize
- Competitors can fork
- Support-heavy business model

### Recommendation: Freemium (Option 1)

**Rationale:**
- Best aligns with team collaboration focus (differentiator)
- Recurring revenue supports ongoing development
- Individual developers can use free tier forever
- Teams who get value will pay for collaboration features
- Can add enterprise features later without changing model

**Pricing Strategy:**
- Free tier is generous (not a trial)
- Pro tier priced for small teams (5-10 users = $95-190/month)
- Annual discount encourages commitment (20% off)
- Enterprise tier for large organizations (50+ users)

**Launch Strategy:**
- v1.0 launches as free for everyone (build audience)
- v1.1 introduces Team Mode as paid feature
- Early adopters get lifetime discount (50% off)
- Grandfathered free users keep Dashboard access

---

## Go-to-Market Strategy

### Target Audience

**Primary:** iOS/macOS development teams at startups and mid-size companies (5-50 developers)

**Secondary:** Individual developers learning Swift and wanting to improve code quality

**Tertiary:** Large enterprises with multiple iOS teams needing standardization

### Positioning

**Core Message:** "Turn SwiftLint configuration from a chore into a team learning and quality improvement system."

**Value Propositions:**
- For Individuals: "Learn Swift best practices while linting"
- For Teams: "Coordinate linting decisions without endless debates"
- For Managers: "Measure and improve code quality with data"

### Launch Plan

#### Phase 1: Private Beta (3 months before launch)

**Goal:** Validate core features, fix critical bugs, get testimonials

**Activities:**
- Invite 20-30 beta testers (individuals and teams)
- Weekly feedback surveys
- One-on-one user interviews
- Iterate based on feedback
- Collect video testimonials

**Success Criteria:**
- 4.5+ average satisfaction score
- 80%+ would recommend to colleague
- 10+ testimonials collected

#### Phase 2: Public Launch (v1.0)

**Goal:** Generate awareness and initial user base

**Channels:**
- Product Hunt launch (aim for top 5)
- Hacker News "Show HN" post
- Reddit (/r/iOSProgramming, /r/swift)
- iOS Dev Weekly sponsorship
- SwiftLee and other iOS blogs
- Twitter/X announcement
- App Store featuring (apply for editorial)

**Content:**
- Launch blog post with demo video
- "Why we built this" story post
- Documentation site
- Tutorial videos (YouTube)

**Goals:**
- 1,000+ downloads in first week
- 50+ Daily Active Users in first month
- Featured on 3+ iOS blogs

#### Phase 3: Growth (Post-Launch)

**Channels:**
- Content marketing (weekly blog posts)
- SEO (target "swiftlint tutorial", "swiftlint configuration", etc.)
- Conference sponsorships (try! Swift, NSSpain)
- Podcast sponsorships (Swift by Sundell, iOS Dev Happy Hour)
- YouTube tutorials and reviews
- GitHub README mentions
- Word of mouth / referrals

**Content Ideas:**
- "10 SwiftLint Rules Every iOS Developer Should Enable"
- "How to Onboard Your Team to SwiftLint in One Sprint"
- "SwiftLint Rules That Prevent Real Bugs"
- Case studies from beta users

**Community Building:**
- Discord or Slack community
- Twitter engagement
- GitHub issues and discussions
- Feature request voting board

#### Phase 4: Enterprise Sales (v1.1+)

**Goal:** Land enterprise customers for recurring revenue

**Tactics:**
- Outbound sales to known iOS teams
- LinkedIn advertising
- Enterprise landing page
- Free trials for teams
- Dedicated sales engineer
- Case studies and ROI calculators

### Partnerships

**Potential Partners:**
- SwiftLint maintainers (get official endorsement)
- Xcode plugin developers (integrate or cross-promote)
- iOS bootcamps and training programs
- iOS consultancies

### Success Metrics (GTM)

**Awareness:**
- 10k+ website visits in first month
- 1k+ Product Hunt upvotes
- 500+ social media mentions

**Acquisition:**
- 1,000+ downloads in first month
- 200+ signups for Team Mode (free trials)

**Activation:**
- 70%+ of users enable at least one rule in first session
- 50%+ of users return within 7 days

**Retention:**
- 30%+ monthly retention after 3 months
- 60%+ weekly retention for active users

---

## Risks and Mitigations

### Risk 1: SwiftLint API Changes

**Description:** SwiftLint CLI output format or behavior changes, breaking our app.

**Impact:** High - Core functionality depends on SwiftLint

**Mitigation:**
- Support multiple SwiftLint versions
- Version detection and compatibility checking
- Graceful degradation if unsupported version
- Monitor SwiftLint releases and update quickly
- Maintain good relationship with SwiftLint maintainers

### Risk 2: Low Adoption

**Description:** Developers continue editing YAML manually, don't see value in GUI.

**Impact:** High - No users = no business

**Mitigation:**
- Extensive user research before building
- Private beta to validate product-market fit
- Focus on unique value (team features, learning)
- Freemium model to lower barrier to entry
- Strong onboarding to show value immediately

### Risk 3: Apple Restrictions

**Description:** Apple rejects app from App Store or limits capabilities.

**Impact:** Medium - Can still distribute directly, but limits reach

**Mitigation:**
- Review App Store guidelines early
- Don't rely on private APIs
- Sandboxing and security best practices
- Have direct download option ready
- Consider "Xcode extension" vs "standalone app" trade-offs

### Risk 4: Performance Issues

**Description:** App is slow on large codebases, users abandon it.

**Impact:** High - Poor UX = poor retention

**Mitigation:**
- Performance targets defined upfront
- Test on large real-world codebases during development
- Incremental analysis strategy
- Profiling and optimization passes
- User controls for analysis scope

### Risk 5: YAML Corruption

**Description:** Bug in YAML engine corrupts user's configuration file.

**Impact:** Critical - Destroys user trust

**Mitigation:**
- Automatic backups before every write
- Extensive testing on edge cases
- "Dry run" validation before writing
- Git integration so changes are recoverable
- Clear error messages and recovery flows
- Insurance: open-source YAML engine for community review

### Risk 6: Competitor Launches First

**Description:** Another team builds similar tool and captures market.

**Impact:** Medium - First-mover advantage is real

**Mitigation:**
- Focus on differentiation (team mode, learning)
- Ship v1.0 quickly (6 months or less)
- Build community early
- Unique positioning and messaging
- Better UX and design

### Risk 7: SwiftLint Becomes Obsolete

**Description:** Apple builds linting into Xcode, or new tool replaces SwiftLint.

**Impact:** High - Our tool becomes irrelevant

**Mitigation:**
- Monitor Apple announcements closely
- Design architecture to support multiple linters (future-proofing)
- If Apple builds linting, pivot to "team coordination for Xcode linting"
- Build strong enough team features that tool has value even if linting changes

### Risk 8: Security Vulnerabilities

**Description:** App has security flaw, exposed to malicious code execution.

**Impact:** Critical - Could harm users

**Mitigation:**
- Security review before launch
- Code signing and notarization
- Sandboxing where possible
- Regular dependency updates
- Security incident response plan
- Bug bounty program (future)

---

## Open Questions

### Product Questions

1. **Multi-Workspace Support:** Should v1.0 support multiple workspaces, or focus on single-workspace experience?
   - **Recommendation:** Single workspace for v1.0, add multi-workspace in v1.2 based on demand

2. **Custom Rules:** How deeply should we support custom SwiftLint rules?
   - **Recommendation:** Load and display them, but no special UI in v1.0. Add "custom rule builder" in v2.0 if requested.

3. **SwiftFormat Integration:** Should we integrate SwiftFormat for auto-fixing?
   - **Recommendation:** Not in v1.0, explore in v1.4 after core features are solid

4. **Localization:** Should v1.0 be English-only or support multiple languages?
   - **Recommendation:** English-only for v1.0, add i18n architecture but don't translate yet

5. **Accessibility:** What level of accessibility support?
   - **Recommendation:** Basic VoiceOver support in v1.0, full accessibility in v1.3

### Technical Questions

6. **Database Choice:** SQLite vs. Core Data?
   - **Recommendation:** Core Data for easier SwiftUI integration, unless performance testing shows issues

7. **Git Library:** SwiftGit2 vs. shell out to CLI?
   - **Recommendation:** Shell out to CLI for v1.0 (simpler), evaluate SwiftGit2 if performance is an issue

8. **Caching Strategy:** How aggressively to cache rule metadata and violation data?
   - **Recommendation:** Cache rules until SwiftLint version changes, cache violations for 24 hours with manual refresh

9. **Offline Support:** Should app work offline?
   - **Recommendation:** Yes for core features (Rule Browser, Violations), but Team Mode requires network

10. **Telemetry:** How much usage data to collect?
    - **Recommendation:** Opt-in telemetry, minimal data collection (feature usage counts, no code content)

### Business Questions

11. **Pricing:** What exact price points for Pro and Enterprise tiers?
    - **Recommendation:** A/B test during beta: $15 vs. $19 vs. $25/month

12. **Payment Processing:** Stripe vs. Apple IAP vs. both?
    - **Recommendation:** Apple IAP for App Store version, Stripe for direct download (gives more control)

13. **Free Tier Limits:** How to limit free tier without annoying users?
    - **Recommendation:** No file limit in free tier, just remove advanced features (Dashboard, Team Mode)

14. **Support Model:** Email support vs. forum vs. chat?
    - **Recommendation:** Email for v1.0, add community forum in v1.2

### Design Questions

15. **Dark Mode:** Full dark mode support in v1.0?
    - **Recommendation:** Yes, essential for developer tools

16. **Themes:** Should users be able to customize colors?
    - **Recommendation:** No custom themes in v1.0, use system accent color

17. **Dashboard Export:** What formats for exporting dashboards/reports?
    - **Recommendation:** PDF and PNG in v1.1, CSV for raw data

18. **Keyboard Shortcuts:** How extensive should keyboard navigation be?
    - **Recommendation:** Cover most common actions in v1.0, comprehensive shortcuts in v1.2

---

## Release Roadmap

> **Note:** The checkmarks (✅) in this section indicate *planned features* for each version, not implementation status. For actual implementation status, see the [Current Implementation Status](#current-implementation-status) section above or [`V1_REQUIREMENTS_STATUS.md`](../V1_REQUIREMENTS_STATUS.md).

### v1.0 - Core Experience (MVP) - Target: 6 months

**Goal:** Ship a solid, useful product that individual developers and small teams love.

**Planned Features:**
- ✅ Rule Browser with search and filters
- ✅ Rule Detail Panel with examples and configuration
- ✅ YAML Configuration Engine with diffs and validation
- ✅ Workspace Analyzer with violation tracking
- ✅ Violation Inspector with navigation to Xcode
- ✅ Basic onboarding flow

**Out of Scope:**
- Dashboard and analytics (moved to v1.1)
- Team Mode (moved to v1.1)
- Live Preview (moved to v1.1)
- CI/CD integration

**Success Criteria:**
- 1,000+ downloads in first month
- 4.5+ star rating
- 10+ positive testimonials

### v1.1 - Team Collaboration & Analytics - Target: +3 months

**Goal:** Add team features and analytics to drive Pro tier adoption.

**Planned Features:**
- ✅ Dashboard with violation trends and quality score
- ✅ Configuration Profiles (save and share configurations)
- ✅ Team Mode: proposal and approval workflow
- ✅ Audit log
- ✅ Role-based permissions
- ✅ Live Preview Mode

**Success Criteria:**
- 20+ teams using Team Mode
- 50+ Pro tier subscribers
- 40%+ monthly retention

### v1.2 - Migration & CI Integration - Target: +3 months

**Goal:** Help teams adopt SwiftLint progressively and integrate with CI/CD.

**Planned Features:**
- ✅ Migration Assistant with phased rollout planning
- ✅ Fix Sprints and progress tracking
- ✅ CI/CD integration (GitHub Actions, GitLab CI, etc.)
- ✅ PR integration with inline comments
- ✅ Regression alerts and notifications
- ✅ Slack/Teams webhook integration

**Success Criteria:**
- 10+ enterprise customers
- 100+ Pro tier subscribers
- Featured on major iOS blog or conference

### v1.3 - AI & Advanced Features - Target: +4 months

**Goal:** Use AI to provide smarter recommendations and improve UX.

**Planned Features:**
- ✅ AI-powered rule recommendations based on codebase
- ✅ Automatic threshold suggestions (e.g., optimal line_length)
- ✅ Xcode Source Editor Extension
- ✅ Full accessibility support
- ✅ Advanced dashboard export options
- ✅ Custom rule builder (GUI for creating simple custom rules)

**Success Criteria:**
- 50+ enterprise customers
- 500+ Pro tier subscribers
- 10,000+ total users

### v2.0 - Platform & Scale - Target: +6 months

**Goal:** Expand platform and scale to larger teams.

**Planned Features:**
- ✅ Cloud sync service for team configurations
- ✅ Real-time collaboration features
- ✅ Multi-workspace support
- ✅ Web dashboard (view-only, for managers)
- ✅ Plugin API for custom integrations
- ✅ SwiftFormat integration
- ✅ Support for other Swift linters (Periphery, etc.)

**Success Criteria:**
- 100+ enterprise customers
- $50k+ MRR
- 20,000+ total users

---

## Appendix

### Glossary

- **Rule:** A SwiftLint rule that checks for a specific code pattern
- **Violation:** An instance where code fails a rule's check
- **Opt-in Rule:** A rule that must be explicitly enabled (not on by default)
- **Severity:** Warning or Error level for a violation
- **Configuration:** The .swiftlint.yml file and its contents
- **Workspace:** An Xcode workspace or project directory
- **Profile:** A saved set of rule configurations
- **Proposal:** A suggested change to the team's configuration
- **Audit Log:** Historical record of configuration changes
- **Idiomatic Maturity Score:** A calculated metric of code quality based on rules

### References

- [SwiftLint GitHub](https://github.com/realm/SwiftLint)
- [SwiftLint Documentation](https://realm.github.io/SwiftLint/)
- [Swift.org Style Guide](https://swift.org/documentation/api-design-guidelines/)
- [Google Swift Style Guide](https://google.github.io/swift/)
- [Airbnb Swift Style Guide](https://github.com/airbnb/swift)

### Competitive Analysis (Detailed)

**Tool: SwiftLint CLI (Direct)**
- Strengths: Powerful, flexible, free, widely adopted
- Weaknesses: YAML editing is error-prone, no team features, poor learning experience
- Market Share: ~80% of Swift projects
- Our Advantage: GUI, team coordination, learning resources

**Tool: SwiftLint Xcode Extensions**
- Strengths: Integrated into IDE
- Weaknesses: Limited config management, no analytics
- Market Share: ~10% of SwiftLint users
- Our Advantage: Comprehensive config management, team features

**Tool: SonarQube/SonarCloud**
- Strengths: Enterprise-grade, multi-language
- Weaknesses: Expensive, complex, not SwiftLint-native
- Market Share: ~5% of iOS teams (enterprise only)
- Our Advantage: Lower cost, better UX, SwiftLint-native

### User Research Findings (To Be Conducted)

**Research Questions:**
1. How do teams currently make linting decisions?
2. What pain points do developers experience with YAML editing?
3. Would teams pay for collaboration features?
4. What analytics would be most valuable?
5. How do teams onboard new developers to their linting setup?

**Methods:**
- User interviews (20-30 developers and tech leads)
- Survey (100+ responses)
- Observational studies (watch developers configure SwiftLint)
- Competitive analysis
- Beta testing feedback

### Design Mockups

(To be created in design phase)

**Key Screens:**
1. Rule Browser (master-detail split view)
2. Rule Detail Panel (with examples and configuration)
3. YAML Diff Modal (before/after comparison)
4. Violation Inspector (list and detail views)
5. Dashboard (charts and metrics)
6. Live Preview (code editor with inline violations)
7. Proposal Review (diff and approval interface)
8. Onboarding Wizard (step-by-step setup)

### Marketing Assets

**To Create:**
- Product demo video (2-3 minutes)
- Screenshot set for App Store
- Social media graphics
- Blog post templates
- Email templates
- Press kit

---

## Changelog

**v2.2 (This Document) - January 2026**
- ✅ Completed Rule Detail Panel enhancements: rationale extraction, violation count, related rules, Swift Evolution links
- ✅ Completed Violation Inspector enhancements: grouping, bulk operations, CSV/JSON export, keyboard shortcuts
- ✅ Completed Xcode Integration: full service layer with path resolution, project detection, error handling
- ✅ Added comprehensive test coverage for all new features (500+ tests total)
- ✅ Updated completion status: v1.0 now ~95% complete

**v2.1 (This Document) - January 2026**
- Updated implementation status with recent UI/UX improvements
- Documented layout refinements (two-panel layout, alignment fixes)
- Documented performance improvements (background rule loading)
- Documented code quality improvements (Swift 6 concurrency fixes)
- Updated Rule Detail Panel section with current implementation status
- Updated Rule Browser section with background loading details

**v2.0 (This Document) - December 21, 2025**
- Expanded from original 1-page PRD
- Added detailed competitive analysis
- Expanded all feature descriptions
- Added comprehensive technical architecture
- Added monetization and GTM strategies
- Added risks, mitigations, and open questions
- Refined release roadmap
- Added appendices

**v1.0 (Original) - December 2025**
- Initial PRD draft
- High-level features and goals
- Basic user personas
- Simple release plan

---

## Document Maintenance

**Owner:** Product Team  
**Reviewers:** Engineering Lead, Design Lead, CEO  
**Review Cadence:** Monthly or after major milestones  
**Status:** Living document - update as product evolves

---

## Recommended Next Steps (January 2026)

Based on the current implementation status (~95% complete), all critical v1.0 features are now complete. Here are the recommended priorities for final polish and v1.1:

### Immediate Priority (v1.0 Final Polish)

**1. Final Testing & Bug Fixes** (Estimated: 1-2 days)
- **Why:** Ensure all new features work correctly in production scenarios.
- **Tasks:**
  - End-to-end testing of all new features
  - Test export functionality with large violation sets
  - Verify grouping works correctly with various data sets
  - Test rationale extraction with various markdown formats
  - Verify Swift Evolution link detection across different rule documentation

**2. Documentation & User Guide** (Estimated: 1 day)
- **Why:** Help users discover and use all the new features.
- **Tasks:**
  - Document new Rule Detail Panel sections
  - Document Violation Inspector grouping and export features
  - Create quick start guide highlighting new capabilities
  - Add tooltips/help text for new UI elements

### Short-term Enhancements (v1.1 Candidates)

**3. Dashboard (Basic Version)** (Estimated: 3-5 days)
- **Why:** Provide visibility into code quality trends.
- **Tasks:**
  - Basic violation trends chart
  - Quality score calculation
  - Rule adoption timeline
  - Export functionality

**4. Exclusion Path Recommendations** (Estimated: 1-2 days)
- **Why:** Help users avoid analyzing third-party code unnecessarily.
- **Tasks:**
  - Detect violations in common build/dependency directories
  - Add "Recommended Exclusions" UI in configuration
  - One-click "Add Recommended Exclusions" button
  - Integrate into onboarding flow

### Medium-term Features (v1.1 Candidates)

**5. Exclusion Path Recommendations** (Estimated: 1-2 days)
- **Why:** Help users avoid analyzing third-party code unnecessarily.
- **Tasks:**
  - Detect violations in common build/dependency directories
  - Add "Recommended Exclusions" UI in configuration
  - One-click "Add Recommended Exclusions" button
  - Integrate into onboarding flow

**6. Dashboard (Basic Version)** (Estimated: 3-5 days)
- **Why:** Provide visibility into code quality trends (moved from v1.0 to v1.1, but could be valuable earlier).
- **Tasks:**
  - Basic violation trends chart
  - Quality score calculation
  - Rule adoption timeline
  - Export functionality

### Success Criteria for v1.0 Launch

Before declaring v1.0 complete, ensure:
- ✅ All P0 features implemented and tested
- ✅ Xcode integration is reliable and tested
- ✅ UI is polished and consistent
- ✅ All 176 tests passing
- ✅ Performance targets met (see Technical Architecture section)
- ✅ User documentation complete
- ✅ App Store submission materials ready

**Current Status:** ~85% complete, with Xcode integration as the primary remaining blocker.

---

*End of Product Requirements Document*
