# Plan: Make SwiftLintRuleStudio More macOS-Native

## Context
The app already uses many macOS idioms (NavigationSplitView, HSplitView, NSColor, keyboard shortcuts, SidebarCommands). However, several UI areas still feel iOS-ported or incomplete for a first-class Mac app experience. This plan addresses those gaps in priority order.

---

## Changes by Priority

### 1. Native Search (`.searchable()`) — High Impact
**Problem:** Search is a raw `TextField` placed in the toolbar via `ToolbarItem(placement: .automatic)`. macOS has a native `.searchable()` modifier that integrates properly with the window toolbar (right-aligned, dismissible with Escape, supports search tokens/scopes).

**Files:**
- `UI/Views/ContentView.swift` — remove `ToolbarItem` with `TextField`; add `.searchable(text: $searchText)` to the `NavigationSplitView`
- `UI/Views/RuleBrowser/RuleBrowserView.swift` — remove `RuleBrowserSearchAndFilters`'s custom search bar; wire to `.searchable()` from parent

**How:** Move search to `.searchable(text: $searchText, placement: .toolbar)` on the `NavigationSplitView` in `ContentView`. Pass the binding down to `RuleBrowserViewModel`.

---

### 2. Sidebar Organization — High Impact
**Problem:** All 10 navigation items are dumped in a single "Tools" section. Native Mac apps (Xcode, Mail, Notes) group sidebar items into logical sections.

**File:** `UI/Views/ContentView.swift` — `SidebarView`

**Proposed grouping:**
```
Workspace
  ┣ Rules
  ┗ Violations

Analysis
  ┣ Dashboard
  ┣ Safe Rules
  ┗ Version Check

Configuration
  ┣ Version History
  ┣ Compare Configs
  ┣ Import Config
  ┣ Branch Diff
  ┗ Migration
```

---

### 3. Functional Menu Bar Commands — Medium-High Impact
**Problem:** Two menu commands are stubs:
- `File > Open Workspace…` → comment says "This will be handled by..."
- `Lint > Run Lint` → comment says "Trigger lint run if available"

**File:** `App/SwiftLintRuleStudioApp.swift`

**How:**
- `Open Workspace…`: Use `@FocusedValue` or `@EnvironmentObject` via `AppState` to trigger the `workspaceManager.openWorkspace()` flow. Alternatively, post a `Notification.Name.openWorkspaceRequested` and have `WorkspaceSelectionView`/`ContentView` observe it.
- `Run Lint`: Post `Notification.Name.violationInspectorRefreshRequested` (already exists) to trigger lint.

---

### 4. Settings with `@AppStorage` — Medium Impact
**Problem:** `GeneralSettingsView` and `LintSettingsView` use `.constant()` bindings — settings don't actually persist.

**File:** `App/SwiftLintRuleStudioApp.swift`

**How:** Replace each `.constant()` with `@AppStorage("settingKey")` properties. Add icons to the Settings tab items (SF Symbols in `tabItem`).

```swift
// Before
Toggle("Check for updates automatically", isOn: .constant(true))

// After
@AppStorage("autoUpdate") var autoUpdate = true
Toggle("Check for updates automatically", isOn: $autoUpdate)
```

**Tab items with icons:**
```swift
.tabItem { Label("General", systemImage: "gearshape") }
.tabItem { Label("Linting", systemImage: "chevron.left.forwardslash.chevron.right") }
```

---

### 5. SwiftUI `Table` for Violations — Medium Impact
**Problem:** `ViolationInspectorView` uses a custom `List<ViolationListItem>` with manual layout. Mac apps (like Xcode's issue navigator) use column-based tables with sortable headers.

**Files:**
- `UI/Views/ViolationInspector/ViolationInspectorView.swift`
- `UI/ViewModels/ViolationInspectorViewModel.swift`

**How:** Replace the `List` in the left panel of `HSplitView` with a `Table<Violation>` featuring columns: Severity, File, Line, Rule ID. Add `@State var sortOrder: [KeyPathComparator<Violation>]` to the view model for column sort.

Note: `Table` requires macOS 12+, which the project already targets at 13+.

---

### 6. Enhanced Status Bar — Medium Impact
**Problem:** The bottom status bar (`.safeAreaInset(edge: .bottom)`) only shows the workspace path. Mac apps show context-relevant counts.

**File:** `UI/Views/ContentView.swift`

**Additions:** Show rule count (from `ruleRegistry.rules.count`) and violation count (from `violationStorage`) alongside the path. Add an `ProgressView()` spinner when `ruleRegistry.isLoading` is true.

---

### 7. Window Subtitle — Low-Medium Impact
**Problem:** No window subtitle is shown. Mac apps (like Xcode) show the open document/project name.

**File:** `UI/Views/ContentView.swift` or `App/SwiftLintRuleStudioApp.swift`

**How:** Use `.navigationSubtitle(workspace.name)` on the `NavigationSplitView` (works on macOS 13+), or set the `NSWindow.subtitle` via AppKit when a workspace is opened.

---

### 8. Drag & Drop Workspace Opening — Low Impact (Nice-to-Have)
**Problem:** Users can't drop a folder onto the app window to open it.

**File:** `UI/Views/WorkspaceSelection/WorkspaceSelectionView.swift` and `ContentView.swift`

**How:** Add `.onDrop(of: [.fileURL], ...)` that passes the dropped URL to `workspaceManager.openWorkspace(at:)`.

---

## Files to Modify

| File | Changes |
|------|---------|
| `App/SwiftLintRuleStudioApp.swift` | Fix menu commands, `@AppStorage` settings, add tab icons |
| `UI/Views/ContentView.swift` | `.searchable()`, sidebar grouping, status bar enhancements, window subtitle, drag & drop |
| `UI/Views/RuleBrowser/RuleBrowserView.swift` | Remove custom search bar, wire to `.searchable()` |
| `UI/Views/ViolationInspector/ViolationInspectorView.swift` | Replace List with `Table` |
| `UI/ViewModels/ViolationInspectorViewModel.swift` | Add `Table` sort order support |

---

## Implementation Order

1. Sidebar reorganization (ContentView.swift — purely visual, zero risk)
2. `.searchable()` migration (ContentView + RuleBrowserView)
3. `@AppStorage` settings + tab icons (App entry point)
4. Functional menu commands (App entry point)
5. Status bar enhancements (ContentView.swift)
6. Window subtitle (ContentView.swift)
7. `Table` for violations (ViolationInspectorView + ViewModel)
8. Drag & drop (WorkspaceSelectionView + ContentView)

---

## Verification

- Build succeeds: `xcodebuild -scheme SwiftLIntRuleStudio -configuration Debug build`
- Tests pass: `xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS'`
- Manual checks:
  - Search field appears in toolbar, dismisses with Escape
  - Sidebar shows three logical sections
  - `Cmd+O` triggers file picker
  - `Cmd+Enter` triggers lint run
  - Settings changes persist across app relaunches
  - Settings tabs show icons
  - Status bar shows rule count and violation count
  - Window subtitle shows workspace name
  - Violations list shows sortable columns
  - Dropping a folder onto the window opens it as workspace
