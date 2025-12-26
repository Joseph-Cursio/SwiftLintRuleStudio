# Xcode Integration Requirements

## Current Status

### ✅ Already Implemented
1. **Basic "Open in Xcode" Button** (`ViolationDetailView.swift`)
   - Uses `xcode://file` URL scheme
   - Generates URLs with line and column information
   - Has fallback to open file in default editor

2. **Xcode Project Detection** (`WorkspaceManager.swift`)
   - Detects `.xcodeproj` and `.xcworkspace` files during workspace validation
   - Validates workspace contains Swift project indicators

3. **File Path Information**
   - Violations contain file path, line, and column information
   - Available in both list and detail views

### ⚠️ Limitations & Issues

1. **URL Scheme Reliability**
   - `xcode://file` scheme may not work if Xcode isn't the default handler
   - No verification that Xcode is installed
   - No error handling if URL fails to open

2. **Path Resolution**
   - Violations may have relative paths that need resolution against workspace root
   - No handling for paths outside workspace
   - No validation that file exists before attempting to open

3. **Project/Workspace Selection**
   - Doesn't detect which `.xcodeproj` or `.xcworkspace` to open
   - No handling for multiple projects in workspace
   - Doesn't open the project file, just the source file

4. **User Experience**
   - "Open in Xcode" only available in detail view, not list view
   - No keyboard shortcuts for quick navigation
   - No next/previous violation navigation
   - No indication if Xcode isn't installed

---

## Required Features

### Phase 1: Core Functionality (P0 - v1.0)

#### 1.1 Reliable File Opening
**Priority**: High  
**Effort**: Medium

**Requirements**:
- Resolve relative file paths against workspace root
- Validate file exists before attempting to open
- Handle absolute and relative paths correctly
- Support both `.xcodeproj` and `.xcworkspace` files

**Implementation**:
```swift
// New service: XcodeIntegrationService
class XcodeIntegrationService {
    func openFile(
        at path: String,
        line: Int,
        column: Int?,
        in workspace: Workspace
    ) throws -> Bool {
        // 1. Resolve path relative to workspace
        // 2. Validate file exists
        // 3. Find associated Xcode project/workspace
        // 4. Open using appropriate method
    }
}
```

**Files to Create/Modify**:
- `Core/Services/XcodeIntegrationService.swift` (new)
- `UI/Views/ViolationInspector/ViolationDetailView.swift` (update)
- `UI/Components/ViolationListItem.swift` (add button)

**Tests Required**:
- Unit tests for path resolution
- Unit tests for project detection
- Integration tests for file opening
- Error handling tests

---

#### 1.2 Xcode Project Detection
**Priority**: High  
**Effort**: Medium

**Requirements**:
- Detect `.xcodeproj` or `.xcworkspace` files in workspace
- Handle multiple projects (choose closest or most relevant)
- Support nested project structures
- Cache project locations for performance

**Implementation**:
```swift
extension XcodeIntegrationService {
    func findXcodeProject(
        for fileURL: URL,
        in workspace: Workspace
    ) -> URL? {
        // 1. Search for .xcodeproj or .xcworkspace files
        // 2. Find closest project to file
        // 3. Return project URL
    }
}
```

**Files to Create/Modify**:
- `Core/Services/XcodeIntegrationService.swift` (add methods)
- `Core/Models/Workspace.swift` (add project cache)

**Tests Required**:
- Test single project detection
- Test multiple projects (closest selection)
- Test nested project structures
- Test performance with large workspaces

---

#### 1.3 Improved URL Generation
**Priority**: High  
**Effort**: Low

**Requirements**:
- Use `xcode://` URL scheme reliably
- Fallback to `file://` if Xcode scheme fails
- Support opening project file first, then source file
- Handle Xcode not installed gracefully

**Implementation**:
```swift
extension XcodeIntegrationService {
    private func generateXcodeURL(
        fileURL: URL,
        line: Int,
        column: Int?,
        projectURL: URL?
    ) -> URL? {
        // Format: xcode://file/path/to/file.swift:line:column
        // Or: xcode://file/path/to/project.xcodeproj/file.swift:line:column
    }
    
    private func openWithXcode(_ url: URL) -> Bool {
        // Try xcode:// scheme first
        // Fallback to NSWorkspace.open if needed
        // Return success/failure
    }
}
```

**Files to Create/Modify**:
- `Core/Services/XcodeIntegrationService.swift` (add methods)

**Tests Required**:
- Test URL generation for various formats
- Test fallback behavior
- Test error handling

---

### Phase 2: Enhanced User Experience (P1 - v1.1)

#### 2.1 "Open in Xcode" in List View
**Priority**: Medium  
**Effort**: Low

**Requirements**:
- Add "Open in Xcode" button/action to `ViolationListItem`
- Quick action on hover or right-click
- Keyboard shortcut support (⌘O)

**Implementation**:
```swift
// ViolationListItem.swift
struct ViolationListItem: View {
    let violation: Violation
    let onOpenInXcode: () -> Void
    
    var body: some View {
        HStack {
            // ... existing content
            Button(action: onOpenInXcode) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
        }
        .onTapGesture(count: 2) {
            onOpenInXcode()
        }
    }
}
```

**Files to Create/Modify**:
- `UI/Components/ViolationListItem.swift` (add button)
- `UI/Views/ViolationInspector/ViolationInspectorView.swift` (wire up action)

**Tests Required**:
- UI tests for button interaction
- Keyboard shortcut tests

---

#### 2.2 Next/Previous Violation Navigation
**Priority**: Medium  
**Effort**: Medium

**Requirements**:
- Keyboard shortcuts: ⌘→ (next), ⌘← (previous)
- Navigate through filtered violations
- Auto-open in Xcode when navigating
- Visual indicator of current position

**Implementation**:
```swift
// ViolationInspectorViewModel.swift
extension ViolationInspectorViewModel {
    func selectNextViolation() {
        // Find next violation in filtered list
        // Select and optionally open in Xcode
    }
    
    func selectPreviousViolation() {
        // Find previous violation in filtered list
        // Select and optionally open in Xcode
    }
}
```

**Files to Create/Modify**:
- `UI/ViewModels/ViolationInspectorViewModel.swift` (add navigation methods)
- `UI/Views/ViolationInspector/ViolationInspectorView.swift` (add keyboard handlers)

**Tests Required**:
- Test navigation through filtered list
- Test keyboard shortcuts
- Test edge cases (first/last violation)

---

#### 2.3 Xcode Installation Detection
**Priority**: Low  
**Effort**: Low

**Requirements**:
- Check if Xcode is installed
- Show helpful message if not installed
- Provide installation guidance

**Implementation**:
```swift
extension XcodeIntegrationService {
    var isXcodeInstalled: Bool {
        // Check for Xcode.app in /Applications
        // Or check for xcode-select
    }
    
    func showXcodeNotInstalledAlert() {
        // Show alert with installation instructions
    }
}
```

**Files to Create/Modify**:
- `Core/Services/XcodeIntegrationService.swift` (add detection)
- `UI/Views/ViolationInspector/ViolationDetailView.swift` (add check)

**Tests Required**:
- Test Xcode detection
- Test alert display

---

### Phase 3: Advanced Features (P2 - v1.2+)

#### 3.1 Xcode Project Opening
**Priority**: Low  
**Effort**: Medium

**Requirements**:
- Open Xcode project/workspace file when opening violation
- Ensure project is open before opening source file
- Handle project already open scenario

**Implementation**:
```swift
extension XcodeIntegrationService {
    func openProjectAndFile(
        projectURL: URL,
        fileURL: URL,
        line: Int,
        column: Int?
    ) async throws {
        // 1. Open project in Xcode
        // 2. Wait for project to load
        // 3. Open file at line/column
    }
}
```

**Files to Create/Modify**:
- `Core/Services/XcodeIntegrationService.swift` (add async methods)

**Tests Required**:
- Test project opening
- Test file opening after project loads
- Test error handling

---

#### 3.2 Deep Linking from Xcode
**Priority**: Low  
**Effort**: High

**Requirements**:
- Handle `swiftlintrulestudio://` URL scheme
- Open specific violation from Xcode extension
- Bidirectional integration

**Implementation**:
```swift
// App-level URL handling
extension SwiftLintRuleStudioApp {
    func handleURL(_ url: URL) {
        // Parse swiftlintrulestudio:// URLs
        // Navigate to specific violation
    }
}
```

**Files to Create/Modify**:
- `App/SwiftLintRuleStudioApp.swift` (add URL handling)
- `Core/Services/XcodeIntegrationService.swift` (add URL parsing)

**Tests Required**:
- Test URL parsing
- Test navigation from URL
- Test error handling

---

## Implementation Plan

### Step 1: Create XcodeIntegrationService
1. Create new service file
2. Implement path resolution
3. Implement project detection
4. Implement URL generation
5. Add unit tests

### Step 2: Update ViolationDetailView
1. Replace inline `openInXcode()` with service call
2. Add error handling
3. Add loading states
4. Update UI tests

### Step 3: Add to ViolationListItem
1. Add "Open in Xcode" button
2. Wire up action
3. Add keyboard shortcut
4. Update UI tests

### Step 4: Add Navigation
1. Implement next/previous methods
2. Add keyboard handlers
3. Add visual indicators
4. Update tests

### Step 5: Polish
1. Add Xcode installation detection
2. Improve error messages
3. Add user preferences (auto-open, etc.)
4. Documentation

---

## Technical Considerations

### URL Scheme Format
The `xcode://file` URL scheme format:
- `xcode://file/path/to/file.swift:line:column`
- `xcode://file/path/to/project.xcodeproj/file.swift:line:column`

**Note**: The exact format may vary. Testing required.

### Alternative Approaches
1. **AppleScript**: Use AppleScript to control Xcode
   - More reliable but requires permissions
   - Slower than URL scheme

2. **Command Line**: Use `xed` command if available
   - `xed --line <line> <file>`
   - Requires Xcode Command Line Tools

3. **File System**: Open project file, then use AppleScript
   - Most reliable but most complex

### Path Resolution
Violations may have:
- Absolute paths: `/Users/joe/project/File.swift`
- Relative paths: `Sources/File.swift`
- Workspace-relative: Need to resolve against `workspace.path`

### Performance
- Cache project locations to avoid repeated file system scans
- Lazy-load project detection
- Background scanning for large workspaces

---

## Testing Strategy

### Unit Tests
- Path resolution (absolute, relative, workspace-relative)
- Project detection (single, multiple, nested)
- URL generation (various formats)
- Error handling (file not found, Xcode not installed)

### Integration Tests
- End-to-end file opening
- Project detection in real workspaces
- Error scenarios

### UI Tests
- Button interactions
- Keyboard shortcuts
- Error message display
- Loading states

---

## Dependencies

### External
- None (uses Foundation and AppKit)

### Internal
- `WorkspaceManager` (for workspace information)
- `Violation` model (for file paths)
- `DependencyContainer` (for service injection)

---

## Estimated Effort

| Phase | Features | Effort | Priority |
|-------|----------|--------|----------|
| Phase 1 | Core functionality | 2-3 days | P0 |
| Phase 2 | Enhanced UX | 1-2 days | P1 |
| Phase 3 | Advanced features | 3-5 days | P2 |

**Total for v1.0 (Phase 1)**: 2-3 days

---

## Success Criteria

### Phase 1 (v1.0)
- ✅ Users can click "Open in Xcode" and file opens at correct line
- ✅ Works with both absolute and relative paths
- ✅ Handles missing files gracefully
- ✅ Detects Xcode projects in workspace

### Phase 2 (v1.1)
- ✅ "Open in Xcode" available in list view
- ✅ Keyboard shortcuts work
- ✅ Next/previous navigation works
- ✅ Clear error messages

### Phase 3 (v1.2+)
- ✅ Opens Xcode project before opening file
- ✅ Deep linking from Xcode works
- ✅ Bidirectional integration

---

## Open Questions

1. **URL Scheme Reliability**: Does `xcode://file` work reliably across macOS versions?
2. **Multiple Projects**: How to choose which project when multiple exist?
3. **Xcode Version**: Does URL scheme work with all Xcode versions?
4. **Permissions**: Do we need special permissions for AppleScript approach?

---

## References

- [Xcode URL Schemes](https://developer.apple.com/documentation/xcode/opening-files-and-projects-from-a-url)
- [NSWorkspace Documentation](https://developer.apple.com/documentation/appkit/nsworkspace)
- Current implementation: `ViolationDetailView.swift:205-220`

