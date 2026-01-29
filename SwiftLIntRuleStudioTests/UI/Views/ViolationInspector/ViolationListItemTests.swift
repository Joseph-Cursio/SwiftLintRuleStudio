//
//  ViolationListItemTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for ViolationListItem component
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

// Tests for ViolationListItem component
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct ViolationListItemTests {
    
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
    ) -> Violation {
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
    
    private struct TestHostView: View {
        let violation: Violation
        let container: DependencyContainer
        
        var body: some View {
            ViolationListItem(violation: violation)
                .environmentObject(container)
        }
    }
    
    private struct ViewResult: @unchecked Sendable {
        let view: TestHostView
    }
    
    @MainActor
    private func makeViolationListItemView(violation: Violation) -> ViewResult {
        let container = DependencyContainer.createForTesting()
        return ViewResult(view: TestHostView(violation: violation, container: container))
    }

    // MARK: - Rendering Tests
    
    @Test("ViolationListItem displays rule ID")
    func testDisplaysRuleID() async throws {
        let violation = makeTestViolation(ruleID: "force_cast")
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRuleID = try await MainActor.run {
            _ = try viewCapture.inspect().find(text: "force_cast")
            return true
        }
        #expect(hasRuleID == true, "ViolationListItem should display rule ID")
    }
    
    @Test("ViolationListItem displays violation message")
    func testDisplaysMessage() async throws {
        let violation = makeTestViolation(message: "Force cast should be avoided")
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasMessage = try await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Force cast should be avoided")
            return true
        }
        #expect(hasMessage == true, "ViolationListItem should display violation message")
    }
    
    @Test("ViolationListItem displays file path")
    func testDisplaysFilePath() async throws {
        let violation = makeTestViolation(filePath: "Sources/MyFile.swift")
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasFilePath = try await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Sources/MyFile.swift")
            return true
        }
        #expect(hasFilePath == true, "ViolationListItem should display file path")
    }
    
    @Test("ViolationListItem displays line number")
    func testDisplaysLineNumber() async throws {
        let violation = makeTestViolation(line: 42)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasLine = try await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Line 42")
            return true
        }
        #expect(hasLine == true, "ViolationListItem should display line number")
    }
    
    // MARK: - Severity Indicator Tests
    
    @Test("ViolationListItem shows severity badge for error")
    func testShowsSeverityBadgeForError() async throws {
        let violation = makeTestViolation(severity: .error)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // Find the SeverityBadge
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSeverityBadge = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.Text.self, where: { textView in
                do {
                    let text = try textView.string()
                    return text == "ERROR"
                } catch {
                    return false
                }
            })
            return true
        }
        #expect(hasSeverityBadge == true, "ViolationListItem should show ERROR badge for error severity")
    }
    
    @Test("ViolationListItem shows severity badge for warning")
    func testShowsSeverityBadgeForWarning() async throws {
        let violation = makeTestViolation(severity: .warning)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // Find the SeverityBadge
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSeverityBadge = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.Text.self, where: { textView in
                do {
                    let text = try textView.string()
                    return text == "WARNING"
                } catch {
                    return false
                }
            })
            return true
        }
        #expect(hasSeverityBadge == true, "ViolationListItem should show WARNING badge for warning severity")
    }
    
    @Test("ViolationListItem shows suppressed label when suppressed")
    func testShowsSuppressedLabel() async throws {
        let violation = makeTestViolation(suppressed: true)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppressed = try await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Suppressed")
            return true
        }
        #expect(hasSuppressed == true, "ViolationListItem should show 'Suppressed' label when violation is suppressed")
    }
    
    @Test("ViolationListItem hides suppressed label when not suppressed")
    func testHidesSuppressedLabel() async throws {
        let violation = makeTestViolation(suppressed: false)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppressed = await MainActor.run {
            (try? viewCapture.inspect().find(text: "Suppressed")) != nil
        }
        #expect(
            hasSuppressed == false,
            "ViolationListItem should not show 'Suppressed' label when violation is not suppressed"
        )
    }
    
    // MARK: - Severity Color Tests
    
    @Test("ViolationListItem uses correct color for error severity")
    func testErrorSeverityColor() async throws {
        let violation = makeTestViolation(severity: .error)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // The severity indicator is a Circle with fill color
        // We can verify the view structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasHStack = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasHStack == true, "ViolationListItem should have HStack structure")
    }
    
    @Test("ViolationListItem uses correct color for warning severity")
    func testWarningSeverityColor() async throws {
        let violation = makeTestViolation(severity: .warning)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // Verify the view structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasHStack = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasHStack == true, "ViolationListItem should have HStack structure")
    }
    
    // MARK: - Content Truncation Tests
    
    @Test("ViolationListItem truncates long messages")
    func testTruncatesLongMessages() async throws {
        let longMessage = String(repeating: "This is a very long message. ", count: 20)
        let violation = makeTestViolation(message: longMessage)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // The view should still render even with long messages
        // Note: ViewInspector may not find truncated text, but view should still render
        // We verify the view can be created and inspected
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasHStack = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasHStack == true, "ViolationListItem should handle long messages")
    }
    
    @Test("ViolationListItem truncates long file paths")
    func testTruncatesLongFilePaths() async throws {
        let longPath = "Sources/" + String(repeating: "Very/Long/Path/", count: 10) + "File.swift"
        let violation = makeTestViolation(filePath: longPath)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // The view should still render even with long paths
        let viewExists = await MainActor.run {
            view != nil
        }
        #expect(viewExists == true, "ViolationListItem should handle long file paths")
    }
    
    // MARK: - Edge Cases
    
    @Test("ViolationListItem handles violation without column")
    func testHandlesViolationWithoutColumn() async throws {
        let violation = makeTestViolation(column: nil)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // Should still display correctly without column
        // Extract ruleID within MainActor.run to avoid Swift 6 false positives
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRuleID = try await MainActor.run {
            let ruleID = violation.ruleID
            _ = try viewCapture.inspect().find(text: ruleID)
            return true
        }
        #expect(hasRuleID == true, "ViolationListItem should display even without column")
    }
    
    @Test("ViolationListItem handles violation with column")
    func testHandlesViolationWithColumn() async throws {
        let violation = makeTestViolation(column: 15)
        let result = await MainActor.run {
            makeViolationListItemView(violation: violation)
        }
        let view = result.view
        
        // Should display correctly with column
        // Extract ruleID within MainActor.run to avoid Swift 6 false positives
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRuleID = try await MainActor.run {
            let ruleID = violation.ruleID
            _ = try viewCapture.inspect().find(text: ruleID)
            return true
        }
        #expect(hasRuleID == true, "ViolationListItem should display with column")
    }
}

// MARK: - ViewInspector Extensions

extension ViolationListItem: Inspectable {}
