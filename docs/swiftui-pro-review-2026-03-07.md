# SwiftUI Pro Review — 2026-03-07

Review of the SwiftLintRuleStudio codebase for SwiftUI best practices, modern API usage, and project conventions. This is the second review pass; the first pass prompted the `@Observable` migration completed in the same session.

---

## ViolationInspectorView+ListViews.swift

**Line 73: Use `.scrollIndicators(.hidden)` instead of `showsIndicators: false`.**

```swift
// Before
ScrollView(.horizontal, showsIndicators: false) {

// After
ScrollView(.horizontal) {
    ...
}
.scrollIndicators(.hidden)
```

---

## RuleBrowserView.swift

**Line 165: Redundant `style: .continuous` — it's the default for `RoundedRectangle`.**

```swift
// Before
.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

// After
.clipShape(RoundedRectangle(cornerRadius: 8))
```

**Line 213: `sheet(isPresented:)` with an `if let` guard inside — prefer `sheet(item:)` when presenting optional data.**

```swift
// Before
.sheet(isPresented: Bindable(viewModel).showBulkDiffPreview) {
    if let diff = viewModel.bulkDiff {
        ConfigDiffPreviewView(diff: diff, ...)
    }
}

// After — present the item directly; the sheet is only shown when diff is non-nil
.sheet(item: Bindable(viewModel).bulkDiff) { diff in
    ConfigDiffPreviewView(diff: diff, ...)
}
```

**Line 278: Same `showsIndicators: false` issue.**

---

## RuleDetailView.swift

**Lines 170–186 & 199–208: `sheet(isPresented:)` with `if let` guard inside — prefer `sheet(item:)`.**

```swift
// Before (line 170)
.sheet(isPresented: Bindable(viewModel).showDiffPreview) {
    if let diff = viewModel.generateDiff() {
        ConfigDiffPreviewView(diff: diff, ruleName: rule.name) { ... }
    }
}

// After
.sheet(item: .init(
    get: { viewModel.showDiffPreview ? viewModel.generateDiff() : nil },
    set: { viewModel.showDiffPreview = $0 != nil }
)) { diff in
    ConfigDiffPreviewView(diff: diff, ruleName: rule.name) { ... }
}
```

```swift
// Before (line 199)
.sheet(isPresented: $showImpactSimulation) {
    if let result = impactResult {
        ImpactSimulationView(...)
    }
}

// After
.sheet(item: $impactResult) { result in
    ImpactSimulationView(ruleId: rule.id, ruleName: rule.name, result: result, ...)
}
// (and remove @State var showImpactSimulation; set impactResult = result to show, nil to dismiss)
```

---

## GitBranchDiffView.swift

**Lines 93–96: `Binding(get:set:)` in view body — avoid this pattern.**

The optional-to-non-optional bridging here is the motivation, but it's still a manual binding in the view body. Add a non-optional computed property to the ViewModel that bridges internally:

```swift
// Before
Picker("Branch", selection: Binding(
    get: { viewModel.selectedRef ?? "" },
    set: { viewModel.selectedRef = $0.isEmpty ? nil : $0 }
))

// After — add to GitBranchDiffViewModel:
var selectedRefString: String {
    get { selectedRef ?? "" }
    set { selectedRef = newValue.isEmpty ? nil : newValue }
}

// Then in view:
Picker("Branch", selection: Bindable(viewModel).selectedRefString)
```

---

## OnboardingView.swift

**Lines 11–12: `@ObservedObject` — these classes should be migrated to `@Observable`.**

`OnboardingManager` and `WorkspaceManager` still use `ObservableObject`. They are the remaining un-migrated classes. Once they become `@Observable`, switch to `@State`/`@Bindable` here.

**Line 69: Use `Task.sleep(for:)` instead of `Task.sleep(nanoseconds:)`.**

```swift
// Before
try? await Task.sleep(nanoseconds: 500_000_000)

// After
try? await Task.sleep(for: .milliseconds(500))
```

---

## OnboardingView+Helpers.swift

**Line 155: Same `Task.sleep(nanoseconds:)` issue.**

```swift
// Before
try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

// After
try await Task.sleep(for: .seconds(seconds))
```

---

## Shared pattern: `@EnvironmentObject` across the codebase

`RuleRegistry`, `DependencyContainer`, and `WorkspaceManager` are all `ObservableObject` and injected via `@EnvironmentObject` throughout. These should be the next migration target — convert them to `@Observable` and inject via `@Environment(\.someKey)`. This eliminates the remaining `@EnvironmentObject` wrappers and their associated `ObservableObject` overhead.

---

## Shared pattern: `onTapGesture` instead of `Button`

Four locations use `.onTapGesture` with `.accessibilityAddTraits(.isButton)` — which satisfies the minimum accessibility requirement, but `Button` is still strongly preferred because it provides keyboard focus, hover effects, and correct platform semantics automatically:

- `WorkspaceSelectionView.swift:210`
- `ConfigHealthScoreView.swift:157`
- `SafeRulesDiscoveryView+Support.swift:50`
- `RulePresetPicker.swift:65`

```swift
// Before
SomeView()
    .contentShape(Rectangle())
    .accessibilityAddTraits(.isButton)
    .onTapGesture { action() }

// After
Button(action: action) {
    SomeView()
}
.buttonStyle(.plain)
```

---

## Shared pattern: `fontWeight(.bold)` → `.bold()`

18 occurrences across views — use `.bold()` so the system can choose the correct weight for the current context:

```swift
// Before
Text("Title").fontWeight(.bold)

// After
Text("Title").bold()
```

Files affected:
- `ViolationInspectorView+ListViews.swift:243`
- `ViolationDetailView.swift:81`
- `WorkspaceSelectionView.swift:29`
- `RuleDetailView+Header.swift:34`
- `RuleDetailView+Sections.swift:153`
- `ConfigComparisonView.swift:193`
- `GitBranchDiffView.swift:84, 232, 243`
- `MigrationAssistantView.swift:66, 192, 203`
- `VersionCompatibilityView.swift:60`
- `ImpactSimulationView.swift:72, 100, 110, 119`
- `SafeRulesDiscoveryView+Subviews.swift:15`

---

## Shared pattern: Custom empty state views → `ContentUnavailableView`

`RuleBrowserView` (`RuleBrowserEmptyState`) and `ViolationInspectorView+ListViews` (`emptyStateView`) hand-roll empty state views. Use the system primitive instead:

```swift
// Before
VStack {
    Image(systemName: "magnifyingglass")...
    Text("No rules found")...
    Button("Clear Filters")...
}

// After
ContentUnavailableView {
    Label("No Rules Found", systemImage: "magnifyingglass")
} description: {
    Text("Try adjusting your filters.")
} actions: {
    Button("Clear Filters", action: viewModel.clearFilters)
}
```

When `.searchable()` is active you can use `ContentUnavailableView.search` directly and it automatically incorporates the current search term — no need to pass the text manually.

---

## Summary

| Priority | File(s) | Issue |
|---|---|---|
| **High** | `OnboardingManager`, `WorkspaceManager`, `RuleRegistry`, `DependencyContainer` | Migrate remaining `ObservableObject` classes to `@Observable` + `@Environment` — eliminates all `@EnvironmentObject` usage |
| **High** | `RuleDetailView`, `RuleBrowserView` | Replace `sheet(isPresented:) { if let }` with `sheet(item:)` — prevents empty sheet flash and is the semantically correct API |
| **Medium** | `GitBranchDiffView` | Move optional-bridging out of `Binding(get:set:)` into the ViewModel |
| **Medium** | `RuleBrowserView`, `ViolationInspectorView+ListViews` | Replace custom empty states with `ContentUnavailableView` |
| **Medium** | 4 views | Replace `onTapGesture` with `Button(action:)` |
| **Low** | `OnboardingView`, `OnboardingView+Helpers` | `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` |
| **Low** | `ViolationInspectorView+ListViews`, `RuleBrowserView` | `showsIndicators: false` → `.scrollIndicators(.hidden)` |
| **Low** | 18 call sites | `fontWeight(.bold)` → `.bold()` |
| **Low** | `RuleBrowserView` | Remove redundant `style: .continuous` from `RoundedRectangle` |
