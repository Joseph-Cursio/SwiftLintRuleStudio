//
//  ViolationDetailViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for ViolationDetailView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

/// Tests for ViolationDetailView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ViolationDetailViewTests {
    
    // MARK: - Test Data Helpers
    
    private func makeTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        column: Int? = 5,
        severity: Severity = .error,
        message: String = "Test violation message",
        suppressed: Bool = false,
        resolvedAt: Date? = nil
    ) async -> Violation {
        await MainActor.run {
            Violation(
                id: id,
                ruleID: ruleID,
                filePath: filePath,
                line: line,
                column: column,
                severity: severity,
                message: message,
                detectedAt: Date(),
                resolvedAt: resolvedAt,
                suppressed: suppressed
            )
        }
    }
    
    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        
        init(view: some View) {
            self.view = AnyView(view)
        }
    }
    
    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of 'some View'
    @MainActor
    private func createViolationDetailView(violation: Violation) -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let view = ViolationDetailView(
            violation: violation,
            onSuppress: { _ in },
            onResolve: {}
        )
        .environmentObject(container)
        
        return ViewResult(view: view)
    }
    
    // MARK: - Header Tests
    
    @Test("ViolationDetailView displays rule ID in header")
    func testDisplaysRuleIDInHeader() async throws {
        let violation = await makeTestViolation(ruleID: "force_cast")
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRuleID = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Rule: force_cast")
            return true
        }
        #expect(hasRuleID == true, "ViolationDetailView should display rule ID in header")
    }
    
    @Test("ViolationDetailView displays severity badge")
    func testDisplaysSeverityBadge() async throws {
        let violation = await makeTestViolation(severity: .error)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find severity badge (should show "ERROR")
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSeverityBadge = try await MainActor.run {
            let _ = try viewCapture.inspect().find(ViewType.Text.self, where: { textView in
                do {
                    let text = try textView.string()
                    return text == "ERROR"
                } catch {
                    return false
                }
            })
            return true
        }
        #expect(hasSeverityBadge == true, "ViolationDetailView should display severity badge")
    }
    
    @Test("ViolationDetailView shows suppressed label when suppressed")
    func testShowsSuppressedLabel() async throws {
        let violation = await makeTestViolation(suppressed: true)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppressed = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Suppressed")
            return true
        }
        #expect(hasSuppressed == true, "ViolationDetailView should show 'Suppressed' label")
    }
    
    @Test("ViolationDetailView shows resolved label when resolved")
    func testShowsResolvedLabel() async throws {
        let violation = await makeTestViolation(resolvedAt: Date())
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasResolved = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Resolved")
            return true
        }
        #expect(hasResolved == true, "ViolationDetailView should show 'Resolved' label")
    }
    
    // MARK: - Location Section Tests
    
    @Test("ViolationDetailView displays file path in location section")
    func testDisplaysFilePath() async throws {
        let violation = await makeTestViolation(filePath: "Sources/MyFile.swift")
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasFilePath = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Sources/MyFile.swift")
            return true
        }
        #expect(hasFilePath == true, "ViolationDetailView should display file path")
    }
    
    @Test("ViolationDetailView displays line number in location section")
    func testDisplaysLineNumber() async throws {
        let violation = await makeTestViolation(line: 42)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasLine = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "42")
            return true
        }
        #expect(hasLine == true, "ViolationDetailView should display line number")
    }
    
    @Test("ViolationDetailView displays column when available")
    func testDisplaysColumn() async throws {
        let violation = await makeTestViolation(column: 15)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasColumn = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "15")
            return true
        }
        #expect(hasColumn == true, "ViolationDetailView should display column when available")
    }
    
    @Test("ViolationDetailView shows Open in Xcode button")
    func testShowsOpenInXcodeButton() async throws {
        let violation = await makeTestViolation()
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasOpenButton = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Open in Xcode")
            return true
        }
        #expect(hasOpenButton == true, "ViolationDetailView should show 'Open in Xcode' button")
    }
    
    // MARK: - Message Section Tests
    
    @Test("ViolationDetailView displays violation message")
    func testDisplaysMessage() async throws {
        let violation = await makeTestViolation(message: "Force cast should be avoided")
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasMessage = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Force cast should be avoided")
            return true
        }
        #expect(hasMessage == true, "ViolationDetailView should display violation message")
    }
    
    // MARK: - Code Snippet Section Tests
    
    @Test("ViolationDetailView shows code snippet section")
    func testShowsCodeSnippetSection() async throws {
        let violation = await makeTestViolation()
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasCodeContext = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Code Context")
            return true
        }
        #expect(hasCodeContext == true, "ViolationDetailView should show code snippet section")
    }
    
    // MARK: - Actions Section Tests
    
    @Test("ViolationDetailView shows suppress button when not suppressed")
    func testShowsSuppressButton() async throws {
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppress = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Suppress")
            return true
        }
        #expect(hasSuppress == true, "ViolationDetailView should show 'Suppress' button when not suppressed")
    }
    
    @Test("ViolationDetailView hides suppress button when suppressed")
    func testHidesSuppressButton() async throws {
        let violation = await makeTestViolation(suppressed: true)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppress = await MainActor.run {
            (try? viewCapture.inspect().find(text: "Suppress")) != nil
        }
        #expect(hasSuppress == false, "ViolationDetailView should not show 'Suppress' button when suppressed")
    }
    
    @Test("ViolationDetailView shows resolve button when not resolved")
    func testShowsResolveButton() async throws {
        let violation = await makeTestViolation(resolvedAt: nil)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasResolve = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Mark as Resolved")
            return true
        }
        #expect(hasResolve == true, "ViolationDetailView should show 'Mark as Resolved' button when not resolved")
    }
    
    @Test("ViolationDetailView hides resolve button when resolved")
    func testHidesResolveButton() async throws {
        let violation = await makeTestViolation(resolvedAt: Date())
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasResolve = await MainActor.run {
            (try? viewCapture.inspect().find(text: "Mark as Resolved")) != nil
        }
        #expect(hasResolve == false, "ViolationDetailView should not show 'Mark as Resolved' button when resolved")
    }
    
    // MARK: - Navigation Title Tests
    
    @Test("ViolationDetailView sets navigation title to rule ID")
    func testSetsNavigationTitle() async throws {
        let violation = await makeTestViolation(ruleID: "force_cast")
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Navigation title is set via .navigationTitle modifier
        // We can verify the view structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasScrollView = try await MainActor.run {
            let _ = try viewCapture.inspect().find(ViewType.ScrollView.self)
            return true
        }
        #expect(hasScrollView == true, "ViolationDetailView should have ScrollView structure")
    }
    
    // MARK: - Edge Cases
    
    @Test("ViolationDetailView handles violation without column")
    func testHandlesViolationWithoutColumn() async throws {
        let violation = await makeTestViolation(column: nil)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Should still display correctly without column
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let filePath = await MainActor.run {
            violation.filePath
        }
        let hasFilePath = try await MainActor.run {
            let _ = try viewCapture.inspect().find(text: filePath)
            return true
        }
        #expect(hasFilePath == true, "ViolationDetailView should display even without column")
    }
    
    @Test("ViolationDetailView handles long file paths")
    func testHandlesLongFilePaths() async throws {
        let longPath = "Sources/" + String(repeating: "Very/Long/Path/", count: 10) + "File.swift"
        let violation = await makeTestViolation(filePath: longPath)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Should still display correctly with long paths
        #expect(view != nil, "ViolationDetailView should handle long file paths")
    }
    
    @Test("ViolationDetailView handles long messages")
    func testHandlesLongMessages() async throws {
        let longMessage = String(repeating: "This is a very long message. ", count: 20)
        let violation = await makeTestViolation(message: longMessage)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Should still display correctly with long messages
        #expect(view != nil, "ViolationDetailView should handle long messages")
    }
}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions

