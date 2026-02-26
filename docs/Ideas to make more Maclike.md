# Plan: Make SwiftLintRuleStudio More macOS-Native

## Context

The app already has a solid macOS foundation (8 improvements shipped in Feb 2026), but several
gaps remain before it feels "fully native." This plan catalogs improvements across three priority
tiers and recommends a sequenced implementation path.

**Already done (verified in code):**
- `.searchable()` on RuleBrowserView body
- Sidebar sections ("Workspace" / "Analysis" / "Configuration")
- Menu bar commands via NotificationCenter
- `@AppStorage` settings + SF Symbol tab icons
- Status bar with rule count + loading spinner
- `.navigationSubtitle()` for workspace name
- `Table` for violation inspector non-grouped mode
- Drag & drop workspace opening

---

## Tier 1 — High Impact, Low Effort

### 1.1 Context menus on Rule rows (RuleBrowserView)
Currently no context menus exist on rule rows (violations have 1; config versions have 1).

**File:** `UI/Views/RuleBrowser/RuleBrowserView.swift`
- Add `.contextMenu { }` to the `ForEach` row in list mode and grid mode
- Menu items: **Enable/Disable Rule**, **Copy Rule Identifier**, **Simulate Impact**
- "Enable/Disable" calls a new `RuleBrowserViewModel.toggleRule(_:yamlEngine:)` method
- "Copy Rule Identifier" writes `rule.identifier` to `NSPasteboard.general`
- "Simulate Impact" posts `Notifications.simulateImpactRequested` (new name) or navigates
- Requires `import AppKit` at top of file (gated `#if os(macOS)`)

**File:** `UI/ViewModels/RuleBrowserViewModel.swift`
- Add `toggleRule(_:yamlEngine:)` leveraging existing bulk-operation machinery

**File:** `Core/Utilities/Notifications.swift`
- Add `static let simulateImpactRequested = Notification.Name(...)` if navigation is via notification

### 1.2 Window default size and resizability
WindowGroup has no size declarations — macOS picks an arbitrary initial size.

**File:** `App/SwiftLintRuleStudioApp.swift`
```swift
WindowGroup { ContentView()... }
    .defaultSize(width: 1100, height: 700)
    .windowResizability(.contentMinSize)
```

### 1.3 `applicationShouldTerminateAfterLastWindowClosed` returns `false`
By default it returns `true`, causing the app to quit when the window is closed — un-macOS-like.

**File:** `App/SwiftLintRuleStudioApp.swift` → `UITestWindowBootstrapper`
```swift
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
```

### 1.4 View menu commands
No View menu exists. Should have at minimum a Show/Hide Detail Panel toggle.

**File:** `Core/Utilities/Notifications.swift`
- Add `static let toggleDetailPanelRequested = Notification.Name(...)`

**File:** `App/SwiftLintRuleStudioApp.swift` → `appCommands`
```swift
CommandMenu("View") {
    Button("Toggle Detail Panel") {
        NotificationCenter.default.post(name: Notifications.toggleDetailPanelRequested, object: nil)
    }
    .keyboardShortcut("D", modifiers: [.command, .shift])
}
```

---

## Tier 2 — Medium Effort, Clear Value

### 2.1 Dock menu with recent workspaces
Right-clicking the dock icon should show recent workspaces for quick reopening.

**File:** `App/SwiftLintRuleStudioApp.swift` → `UITestWindowBootstrapper`
```swift
func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    // Read recentWorkspaces from WorkspaceManager (via stored dependency reference)
    for workspace in recentWorkspaces.prefix(5) {
        let item = NSMenuItem(title: workspace.name, ...)
        menu.addItem(item)
    }
    return menu
}
```
Requires storing a reference to `WorkspaceManager` in `UITestWindowBootstrapper` (static, set at launch).

### 2.2 Dock badge for violation count
After analysis, the dock icon badge reflects the violation count.

**File:** `UI/ViewModels/ViolationInspectorViewModel+Loading.swift`
- After `violations = fetched`, add:
```swift
NSApp.dockTile.badgeLabel = violations.isEmpty ? nil : "\(violations.count)"
```
- `ViolationInspectorViewModel` is already `@MainActor`, so `NSApp.dockTile` access is safe.
- Clear the badge in `clearViolations()`.

### 2.3 System notification when analysis completes
Post a `UNUserNotificationCenter` notification so the user knows analysis finished while the app is in the background.

**File:** `App/SwiftLintRuleStudioApp.swift`
- Request permission (`.alert`, `.sound`) in a `.task { }` on the `WindowGroup`

**File:** `UI/ViewModels/ViolationInspectorViewModel+Loading.swift`
- After `violations = fetched`, call `postAnalysisCompleteNotification(count:)`
- Only call on the "did-analyze" path (not on storage reloads)

**File:** `App/SwiftLintRuleStudioApp.swift` → `UITestWindowBootstrapper`
- Conform to `UNUserNotificationCenterDelegate`
- `willPresent`: return `[.banner, .sound]` so notification shows even when app is foreground
- `didReceive`: call `NSApp.activate(ignoringOtherApps: true)` to bring window forward

### 2.4 Help menu
**File:** `App/SwiftLintRuleStudioApp.swift` → `appCommands`
```swift
CommandGroup(replacing: .help) {
    Button("SwiftLint Rule Studio Help") {
        NSWorkspace.shared.open(URL(string: "https://github.com/realm/SwiftLint")!)
    }
    Button("SwiftLint Rule Reference") {
        NSWorkspace.shared.open(URL(string: "https://realm.github.io/SwiftLint/rule-directory.html")!)
    }
    Divider()
    Button("Report an Issue…") {
        NSWorkspace.shared.open(URL(string: "https://github.com/Joseph-Cursio/SwiftLintRuleStudio/issues")!)
    }
}
```

---

## Tier 3 — Stretch Goals

### 3.1 Scene state persistence (`@SceneStorage`)
Persist the selected sidebar section across launches.

**File:** `UI/Views/ContentView.swift`
- Add `storageKey` / `init?(storageKey:)` to `AppSection` enum
- Replace `@State var selection` with `@SceneStorage("selectedSection") var selectionRaw: String`
- Wrap with a computed `Binding<AppSection?>` for the NavigationSplitView

### 3.2 Document type registration for `.swiftlint.yml`
Allow users to "Open With → SwiftLint Rule Studio" from Finder.

**File:** `SwiftLintRuleStudio/Info.plist`
- Add `CFBundleDocumentTypes` entry for `public.yaml` with `LSHandlerRank: Alternate`

**File:** `App/SwiftLintRuleStudioApp.swift` → `UITestWindowBootstrapper`
- Implement `application(_:open:)` delegate method
- Extract workspace dir from URL and call `workspaceManager.openWorkspace(at:)`

---

## Implementation Order

1. **1.3** — `applicationShouldTerminateAfterLastWindowClosed` (1-line, zero risk)
2. **1.2** — `.defaultSize` + `.windowResizability` (2-line addition)
3. **2.4** — Help menu (pure Commands addition)
4. **1.4** — View menu + notification name
5. **1.1** — Context menus on rule rows (moderate scope)
6. **2.1** — Dock menu
7. **2.2** — Dock badge
8. **2.3** — UNUserNotificationCenter (largest scope)
9. **3.1 / 3.2** — Optional stretch

---

## Key Files

| File | Tier 1 | Tier 2 | Tier 3 |
|------|--------|--------|--------|
| `App/SwiftLintRuleStudioApp.swift` | 1.2, 1.3, 1.4 | 2.1, 2.3, 2.4 | 3.2 |
| `UI/Views/RuleBrowser/RuleBrowserView.swift` | 1.1 | — | — |
| `UI/ViewModels/RuleBrowserViewModel.swift` | 1.1 | — | — |
| `UI/ViewModels/ViolationInspectorViewModel+Loading.swift` | — | 2.2, 2.3 | — |
| `Core/Utilities/Notifications.swift` | 1.4 | — | — |
| `UI/Views/ContentView.swift` | — | — | 3.1 |
| `SwiftLintRuleStudio/Info.plist` | — | — | 3.2 |

---

## Verification

- **Build**: `xcodebuild -scheme SwiftLIntRuleStudio -configuration Debug build`
- **Tests**: `xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS'`
- **Manual checks**:
  - Close main window → app stays alive (1.3)
  - Right-click rule row → context menu appears (1.1)
  - Complete analysis → dock badge updates, system notification fires (2.2, 2.3)
  - Help menu → items open browser (2.4)
  - Right-click dock icon → recent workspaces appear (2.1)
